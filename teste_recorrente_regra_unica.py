"""
A regra da despesa recorrente tem UMA implementacao (core.js: vigentesNoMes), usada pelo AE Matriz e pelo
AE Pecuaria (13/11/2026). Antes cada app tinha a sua copia (a Pecuaria comparava o NOME do centro de custo);
uma segunda copia divergindo foi o que fez um mes de R$ 43.928,73 virar R$ 1.230.390,69.
Prova:
  - nenhum dos dois apps define de novo vigentesNoMes, gruposDeVigentes ou chaveDoRecorrente;
  - a Pecuaria (custosFixosDoMes) da exatamente a resposta e a ordem da versao antiga dela, num sorteio
    com contas de nome igual em centros, fazendas e areas diferentes, recorrentes e do mes;
  - com os mesmos lancamentos, o Matriz e a Pecuaria escolhem as MESMAS despesas em todo mes;
  - areas em outra ordem ([pasto,cria] e [cria,pasto]) contam como a mesma conta nos dois;
  - a lista guardada (cache) nao devolve resposta velha quando a lista cresce.
"""
import json
import random
import re
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}
exe = "/opt/pw-browsers/chromium"
ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")

passes = falhas = 0


def conf(ok, nome, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {nome}")
    else:
        falhas += 1
        print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


print("\n  CODIGO")
for arq in ("AEMatriz.html", "AEpecuaria.html"):
    txt = (REPO / arq).read_text(encoding="utf-8")
    for nome in ("vigentesNoMes", "gruposDeVigentes", "chaveDoRecorrente"):
        conf(not re.search(r"function\s+%s\s*\(" % nome, txt), f"{arq} nao define {nome} (vem do core.js)")
core = (REPO / "core.js").read_text(encoding="utf-8")
conf(all(re.search(r"function\s+%s\s*\(" % n, core) for n in ("vigentesNoMes", "gruposDeVigentes", "chaveDoRecorrente")),
     "core.js tem vigentesNoMes, gruposDeVigentes e chaveDoRecorrente")

# ---- sorteio de lancamentos com muitas colisoes de chave ----
rnd = random.Random(20261113)
CENTROS = [{"id": 71, "nome": "ENERGIA ELETRICA"}, {"id": 72, "nome": "SALARIOS"}, {"id": 73, "nome": "MANUTENCAO"},
           {"id": 94, "nome": "Vendas"}]
AREAS = [[], ["confinamento"], ["pasto", "cria"], ["cria", "pasto"], ["cria"]]
MESES = [f"2026-{m:02d}" for m in range(1, 8)]
lancs = []
for i in range(1, 701):
    mes = None if rnd.random() < 0.3 else rnd.choice(MESES[:6])
    lancs.append({"id": i, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": rnd.choice([None, 1, 2]),
                  "centro_custo_id": rnd.choice([71, 72, 73]), "descricao": rnd.choice(["Energia", "Folha", "Peças", "Frete"]),
                  "valor": round(rnd.uniform(10, 900), 2), "data": (mes + "-10") if mes else None, "mes": mes,
                  "areas": rnd.choice(AREAS), "fornecedor": ""})

DB = {
    "lotes": [], "dietas": [], "ingredientes": [], "animais": [], "pesagens": [], "pesagens_animais": [], "manejos": [],
    "movimentos": [], "leituras_cocho": [], "pasto": [], "producoes_racao": [], "reproducao_custos": [],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [], "abates": [], "custos_fixos": [], "precos_arroba": [],
    "investimentos": [], "receitas": [], "config_financeiro": [{"id": 1}], "config_fazenda": [], "funcionarios": [],
    "funcionario_atividades": [], "fazendas": [{"id": 1, "nome": "Santa Alice"}, {"id": 2, "nome": "Palhadao"}],
    "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "financiamentos": [], "parcelas_financiamento": [],
    "movimentos_financiamento": [], "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [],
    "titulo_baixas": [],
    "centros_custo": [dict(c, ativo=True, tipo="entrada" if c["id"] == 94 else "saida", fazenda_id=None, frente=None,
                           subcategoria="GRUPO | " + c["nome"]) for c in CENTROS],
    "lancamentos_financeiros": lancs, "profiles": [ADMIN],
}

# a versao antiga da Pecuaria (ate 13/11/2026), copiada como era, para comparar
ANTIGA_PEC = """(mesStr) => {
  const grupos = new Map();
  state.custosFixos.forEach(c=>{
    const chaveAreas = (c.areas||[]).slice().sort().join(',');
    const chave = `${c.nome}||${c.categoria||''}||pecuaria||${c.fazendaId ?? ''}||${chaveAreas}`;
    if(!grupos.has(chave)) grupos.set(chave, []);
    grupos.get(chave).push(c);
  });
  const resultado = [];
  grupos.forEach(rows=>{
    const doMes = rows.filter(c=>c.mes===mesStr);
    resultado.push(...(doMes.length>0 ? doMes : rows.filter(c=>!c.mes)));
  });
  return resultado;
}"""


def abre(page, arquivo):
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)};"
                         "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_timeout(1800)
    return erros


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()

    print("\n  AE PECUARIA: mesma resposta e ordem da versao antiga")
    pec = browser.new_page()
    erros = abre(pec, "AEpecuaria.html")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))
    r = pec.evaluate("""(meses) => {
      const antiga = %s;
      const out = {n: state.custosFixos.length, dif: [], porMes: {}};
      for(const m of meses){
        const a = antiga(m).map(c=>c.id).join(','), b = custosFixosDoMes(m).map(c=>c.id).join(',');
        if(a !== b) out.dif.push(m);
        out.porMes[m] = custosFixosDoMes(m).map(c=>c.id).sort((x,y)=>x-y);
      }
      // a lista cresce (mesmo array): o guardado nao pode devolver resposta velha
      const antes = custosFixosDoMes('2026-07').length;
      state.custosFixos.push({id: 99999, nome:'Conta nova', categoria:'SALARIOS', centroCustoId:72, atividade:'pecuaria',
                              fazendaId:null, areas:[], mes:null, valorMensal:5});
      out.cresceu = custosFixosDoMes('2026-07').length === antes + 1;
      state.custosFixos.pop();
      return out;
    }""" % ANTIGA_PEC, MESES)
    conf(r["n"] == len(lancs), f"a Pecuaria carregou as {len(lancs)} despesas", str(r["n"]))
    conf(not r["dif"], "custosFixosDoMes = versao antiga (resultado e ordem) em %d meses" % len(MESES), str(r["dif"]))
    conf(r["cresceu"], "lista que cresce nao devolve resposta velha (conta nova recorrente aparece)")
    pec_por_mes = r["porMes"]

    print("\n  AE MATRIZ x AE PECUARIA: as mesmas despesas em todo mes")
    mat = browser.new_page()
    erros = abre(mat, "AEMatriz.html")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))
    mat_por_mes = mat.evaluate("""(meses) => {
      const desp = state.lancamentos.filter(l=>l.tipo==='despesa' && l.atividade==='pecuaria');
      const out = {};
      for(const m of meses) out[m] = vigentesNoMes(desp, m).map(l=>l.id).sort((x,y)=>x-y);
      return out;
    }""", MESES)
    iguais = [m for m in MESES if mat_por_mes.get(m) == pec_por_mes.get(m)]
    conf(len(iguais) == len(MESES), f"Matriz e Pecuaria escolhem as mesmas despesas nos {len(MESES)} meses",
         str([m for m in MESES if m not in iguais]))
    conf(any(len(v) for v in mat_por_mes.values()) and len(mat_por_mes["2026-07"]) > 0,
         "o sorteio tem recorrentes valendo num mes sem lancamento proprio (julho)")

    areas = mat.evaluate("""() => {
      const base = {descricao:'X', centroCustoId:1, atividade:'pecuaria', fazendaId:null};
      const l = [Object.assign({id:1, mes:null, areas:['pasto','cria']}, base),
                 Object.assign({id:2, mes:'2026-03', areas:['cria','pasto']}, base)];
      return [vigentesNoMes(l, '2026-03').map(x=>x.id), vigentesNoMes(l, '2026-04').map(x=>x.id)];
    }""")
    conf(areas == [[2], [1]], "areas em outra ordem sao a mesma conta: o do mes substitui a recorrente", str(areas))
    browser.close()

print(f"\n  {passes} ok, {falhas} falharam")
sys.exit(1 if falhas else 0)
