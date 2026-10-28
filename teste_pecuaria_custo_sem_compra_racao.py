"""
AE Pecuaria: o custo por animal e por lote conta a racao pelo CONSUMO e o fixo
SEM a compra de racao; o resultado financeiro continua contando a COMPRA.

Decisao do Eduardo (28/10/2026): a compra de racao ja e despesa lancada (centro
Nutricao animal); a saida de racao (kg x preco da dieta) so serve para saber o
custo por animal. O custo por animal/lote somava as duas e contava a racao
duas vezes. Prova:
  - a despesa lancada inteira (fixosMes, resultadoMes) nao muda: a compra segue
    no resultado financeiro;
  - fixosCustoMes tira so a compra de racao (centro Nutricao animal ou conta
    lancada a mao com esse nome exato) e nada mais (fornecedor com "nutricao
    animal" no nome em outro centro, reproducao e salarios ficam);
  - totalMes, custo por animal, custo da area, fixo por lote, taxa de fixo por
    animal/dia e totais do ano usam o fixo sem a compra;
  - a tela avisa quanto da compra ficou de fora;
  - sem compra de racao lancada, nada muda.
"""
import json, sys
from datetime import date
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

HOJE = date.today()
MES = HOJE.strftime("%Y-%m")
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

def desp(i, centro, desc, valor):
    return {"id": i, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": None, "centro_custo_id": centro,
            "descricao": desc, "valor": valor, "data": HOJE.isoformat(), "mes": MES, "areas": []}

def base_db(lancamentos):
    return {
        "lotes": [{"id": 30, "nome": "Curral Teste", "destino": "confinamento", "numero_animais": 10,
                   "data_inicio": HOJE.replace(day=1).isoformat(), "data_fim": None, "dieta_id": 1, "sexo": "macho"}],
        "dietas": [{"id": 1, "nome": "Dieta", "tipo": "confinamento", "kg_animal_dia": 10,
                    "itens": [{"ingredienteId": 1, "pct": 100}]}],
        "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "ms": 88, "pb": 9, "ndt": 80, "preco_kg": 2.0}],
        "fazendas": [], "fazenda_atividades": [],
        "centros_custo": [
            {"id": 90, "nome": "NUTRIÇÃO ANIMAL"}, {"id": 91, "nome": "INSUMOS PECUÁRIOS"},
            {"id": 92, "nome": "SALÁRIOS"}, {"id": 93, "nome": "Manutenção de Infraestrutura"},
            {"id": 94, "nome": "Vendas"},
        ],
        "lancamentos_financeiros": lancamentos,
        # consumo: 1.500 kg x R$ 2,00 = R$ 3.000
        "saidas_racao": [{"id": 1, "data": HOJE.isoformat(), "lote_id": 30, "dieta_id": 1, "quantidade_kg": 1500}],
        "animais": [], "pesagens": [], "pesagens_animais": [], "manejos": [], "movimentos": [],
        "leituras_cocho": [], "pasto": [], "producoes_racao": [], "reproducao_custos": [],
        "diagnosticos_gestacionais": [], "partos": [], "desmamas": [], "abates": [],
        "custos_fixos": [], "precos_arroba": [], "investimentos": [], "receitas": [],
        "config_financeiro": [{"id": 1}], "config_fazenda": [], "funcionarios": [],
    }

RECEITA = {"id": 9, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": None, "centro_custo_id": 94,
           "descricao": "Venda", "valor": 20000.0, "data": HOJE.isoformat(), "mes": MES, "areas": []}
COM_COMPRA = [
    desp(1, 90, "FORNECEDOR X - NUTRIÇÃO ANIMAL", 5000.0),     # compra de racao (pelo centro)
    desp(2, 91, "Nutrição animal", 2000.0),                     # compra de racao (conta lancada a mao)
    desp(3, 92, "Salarios", 4000.0),
    desp(4, 93, "OUROFOS NUTRICAO ANIMAL LTDA", 300.0),         # fornecedor com o nome, outro centro: NAO e racao
    desp(5, 91, "Reprodução animal", 700.0),                    # insumo de reproducao: NAO e racao
    RECEITA,
]
SEM_COMPRA = [l for l in COM_COMPRA if l["id"] not in (1, 2)]

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))
def perto(a, b, tol=0.01): return a is not None and abs(a - b) < tol

ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
exe = "/opt/pw-browsers/chromium"

def roda(db, js):
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
        page = browser.new_page()
        erros = []
        page.on("pageerror", lambda e: erros.append(str(e)))
        page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        page.add_init_script(STUB)
        page.add_init_script(f"window.__DB__ = {json.dumps(dict(db, profiles=[ADMIN]))};"
                             f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        page.goto((REPO / "AEpecuaria.html").as_uri())
        page.wait_for_timeout(1500)
        res = page.evaluate(js)
        browser.close()
        return res, [e for e in erros if not any(r in e for r in ruido)]

JS = """() => {
  const d = dadosFinanceiro();
  const lote = custosDiariosPorLote().custosPorLote.find(r=>r.lote.id===30);
  const html = PageFinanceiroResumo();
  return {d, fixoLote: lote ? lote.fixoAlocado : null, fixoDia: fixoPorAnimalDiaPorTipo().confinamento,
          tem_aviso_mes: html.includes('são compra de ração'), tem_aviso_ano: html.includes('ficam de fora do "com fixo"'),
          nomes: [
            ehCompraDeRacao({categoria:'NUTRIÇÃO ANIMAL', nome:'X'}), ehCompraDeRacao({categoria:'INSUMOS PECUÁRIOS', nome:'Nutrição animal'}),
            ehCompraDeRacao({categoria:'Manutenção de Infraestrutura', nome:'OUROFOS NUTRICAO ANIMAL LTDA'}),
            ehCompraDeRacao({categoria:'INSUMOS PECUÁRIOS', nome:'Reprodução animal'}), ehCompraDeRacao({categoria:'', nome:''})]};
}"""

print("\n  COM COMPRA DE RACAO LANCADA (R$ 7.000) -- consumo R$ 3.000, fixo lancado R$ 12.000")
r, erros = roda(base_db(COM_COMPRA), JS)
d = r["d"]
conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))
conf(perto(d["fixosMes"], 12000), "despesa lancada inteira (financeiro) continua R$ 12.000, compra incluida", str(d["fixosMes"]))
conf(perto(d["resultadoMes"], 20000 - 12000), "resultado do mes = receita - despesa lancada inteira = R$ 8.000", str(d["resultadoMes"]))
conf(perto(d["compraRacaoMes"], 7000), "compra de racao reconhecida = R$ 7.000 (centro Nutricao animal + conta a mao)", str(d["compraRacaoMes"]))
conf(perto(d["fixosCustoMes"], 5000), "fixo do custo por animal = R$ 5.000 (salarios 4.000 + fornecedor 300 + reproducao 700)", str(d["fixosCustoMes"]))
conf(perto(d["variavelMes"], 3000), "consumo de racao do mes = R$ 3.000", str(d["variavelMes"]))
conf(perto(d["totalMes"], 8000), "total do mes = consumo 3.000 + fixo sem compra 5.000 = R$ 8.000 (nao R$ 15.000)", str(d["totalMes"]))
conf(perto(d["custoTotalPorAnimalMes"], 800), "custo por animal no mes = R$ 800 (8.000 / 10)", str(d["custoTotalPorAnimalMes"]))
conf(perto(d["fixoConfinamento"], 12000) and perto(d["fixoConfinamentoCusto"], 5000), "fixo do confinamento: despesas por area R$ 12.000, custo por animal R$ 5.000",
     f'{d["fixoConfinamento"]} / {d["fixoConfinamentoCusto"]}')
conf(perto(d["custoTotalConfinamentoMes"], 8000), "custo do confinamento no mes = 3.000 + 5.000 = R$ 8.000", str(d["custoTotalConfinamentoMes"]))
conf(perto(r["fixoLote"], 5000 / 30, 0.001), "fixo diario do lote (Por Lote) = 5.000 / 30, sem a compra (com ela seria 12.000 / 30 = 400)", str(r["fixoLote"]))
conf(perto(r["fixoDia"], 5000 / 30 / 10, 0.001), "taxa de fixo por animal/dia (custo por @) = 5.000 / 30 / 10, sem a compra", str(r["fixoDia"]))
conf(perto(d["fixosAno"], 12000) and perto(d["compraRacaoAno"], 7000) and perto(d["totalAno"], 8000),
     "ano: despesa lancada 12.000, compra 7.000 de fora, total 8.000", f'{d["fixosAno"]} / {d["compraRacaoAno"]} / {d["totalAno"]}')
conf(perto(d["custoTotalPorAnimalAno"], 800), "custo por animal no ano = R$ 800", str(d["custoTotalPorAnimalAno"]))
conf(r["tem_aviso_mes"] and r["tem_aviso_ano"], "a tela do Resumo avisa quanto da compra de racao ficou de fora (mes e ano)")
conf(r["nomes"] == [True, True, False, False, False], "so centro Nutricao animal ou conta com esse nome exato contam como compra de racao", str(r["nomes"]))

print("\n  SEM COMPRA DE RACAO LANCADA -- nada muda")
r2, erros2 = roda(base_db(SEM_COMPRA), JS)
d2 = r2["d"]
conf(not erros2, "abre sem erro de JavaScript", " | ".join(erros2[:3]))
conf(perto(d2["fixosMes"], 5000) and perto(d2["fixosCustoMes"], 5000) and perto(d2["compraRacaoMes"], 0), "fixo lancado = fixo do custo = R$ 5.000 e nenhuma compra de racao",
     f'{d2["fixosMes"]} / {d2["fixosCustoMes"]} / {d2["compraRacaoMes"]}')
conf(perto(d2["totalMes"], 8000), "total do mes = R$ 8.000 (igual a antes)", str(d2["totalMes"]))
conf(not r2["tem_aviso_mes"] and not r2["tem_aviso_ano"], "sem compra de racao a tela nao mostra aviso")

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
