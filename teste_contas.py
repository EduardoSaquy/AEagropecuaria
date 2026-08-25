"""
Teste do Contas a Pagar / a Receber do AE Matriz.

O que mais importa aqui e a ARITMETICA. Duas contas precisam fechar ate o
centavo, senao o rateio nao passa pela restricao do banco e o custo vai
parar no lugar errado:

  1. repartir(total, n)         a soma das parcelas tem que dar o total
  2. rateio de cada parcela     a soma tem que dar o valor DAQUELA parcela

O resto (situacao, filtros, permissao) e verificado contra a tela.
"""
import json, sys, datetime
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

HOJE    = datetime.date.today()
ONTEM   = (HOJE - datetime.timedelta(days=10)).isoformat()
AMANHA  = (HOJE + datetime.timedelta(days=10)).isoformat()
HOJE_S  = HOJE.isoformat()

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 500, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 400}],
    "centros_custo": [
        {"id": 90, "fazenda_id": None, "nome": "ADUBOS E FERTILIZANTES", "frente": None,
         "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | INSUMOS"},
        {"id": 91, "fazenda_id": None, "nome": "NUTRICAO ANIMAL", "frente": None,
         "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | INSUMOS"},
    ],
    "lancamentos_financeiros": [],
    "lotes": [], "funcionarios": [], "funcionario_atividades": [],
    "talhoes_areas": [], "culturas": [],
    "entidades": [
        {"id": 5, "nome": "AGROSAQUY", "documento": "", "papel": "fornecedor", "ativo": True},
        {"id": 6, "nome": "MULTITRATORES", "documento": "", "papel": "fornecedor", "ativo": True},
    ],
    "contas_bancarias": [{"id": 2, "nome": "SICOOB 36381 - COCRED EDUARDO", "ativo": True}],
    "titulos": [
        # vencido, em aberto
        {"id": 1, "tipo": "pagar", "entidade_id": 5, "descricao": "Adubo atrasado", "valor": 5000.00,
         "vencimento": ONTEM, "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False,
         "valor_baixado": 0, "situacao": "aberto"},
        # vence hoje
        {"id": 2, "tipo": "pagar", "entidade_id": 6, "descricao": "Trator parcela", "valor": 10000.00,
         "vencimento": HOJE_S, "parcela": 2, "parcelas": 6, "previsao": False, "cancelado": False,
         "valor_baixado": 0, "situacao": "aberto"},
        # parcial
        {"id": 3, "tipo": "pagar", "entidade_id": 5, "descricao": "Racao parcial", "valor": 5000.00,
         "vencimento": AMANHA, "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False,
         "valor_baixado": 3000.00, "situacao": "parcial"},
        # pago
        {"id": 4, "tipo": "pagar", "entidade_id": 5, "descricao": "Ja quitado", "valor": 800.00,
         "vencimento": ONTEM, "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False,
         "valor_baixado": 800.00, "situacao": "pago"},
        # previsao
        {"id": 5, "tipo": "pagar", "entidade_id": 6, "descricao": "Esperado", "valor": 2000.00,
         "vencimento": AMANHA, "parcela": 1, "parcelas": 1, "previsao": True, "cancelado": False,
         "valor_baixado": 0, "situacao": "aberto"},
        # a receber
        {"id": 6, "tipo": "receber", "entidade_id": 6, "descricao": "Venda de cana", "valor": 50000.00,
         "vencimento": AMANHA, "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False,
         "valor_baixado": 0, "situacao": "aberto"},
    ],
    "titulo_rateios": [
        {"id": 1, "titulo_id": 1, "fazenda_id": 1, "atividade": "cana",
         "centro_custo_id": 90, "competencia": "2026-07", "valor": 3000.00},
        {"id": 2, "titulo_id": 1, "fazenda_id": None, "atividade": "pecuaria",
         "centro_custo_id": 91, "competencia": "2026-07", "valor": 2000.00},
        {"id": 3, "titulo_id": 2, "fazenda_id": 1, "atividade": "cana",
         "centro_custo_id": 90, "competencia": "2026-08", "valor": 10000.00},
        {"id": 4, "titulo_id": 3, "fazenda_id": 1, "atividade": "pecuaria",
         "centro_custo_id": 91, "competencia": "2026-08", "valor": 5000.00},
        {"id": 6, "titulo_id": 6, "fazenda_id": 1, "atividade": "cana",
         "centro_custo_id": 90, "competencia": "2026-08", "valor": 50000.00},
    ],
    "titulo_baixas": [
        {"id": 1, "titulo_id": 3, "data": HOJE_S, "valor": 3000.00, "conta_bancaria_id": 2},
        {"id": 2, "titulo_id": 4, "data": HOJE_S, "valor": 800.00, "conta_bancaria_id": None},
    ],
}

ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}
DONO  = {"id": "u1", "nome": "Alice", "usuario": "alice", "papel": "proprietario",
         "permissoes": {"pec_financeiro": "editar"}, "ativo": True}
ESCRIT = {"id": "u1", "nome": "Creunice", "usuario": "creunice", "papel": "colaborador",
          "permissoes": {"matriz_financeiro": "editar", "contas": "editar"}, "ativo": True}
SEM_CONTAS = {"id": "u1", "nome": "SoFin", "usuario": "sofin", "papel": "colaborador",
              "permissoes": {"matriz_financeiro": "editar"}, "ativo": True}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def preencher(page, seletor, valor):
    """Preenche como uma pessoa: escreve e sai do campo.

    page.fill() troca o valor e dispara input, mas nao dispara change. Os
    campos do titulo que recalculam escutam change — com fill() o app nunca
    enxergaria o que foi digitado, e o teste estaria medindo o Playwright.
    """
    el = page.locator(seletor)
    tipo = el.get_attribute("type") or "text"
    if tipo in ("month", "date"):
        # campos de data/mes nao aceitam digitacao caractere a caractere;
        # fill() escreve certo neles. O change sai no Tab logo abaixo.
        el.fill(valor)
    else:
        el.click()
        el.fill("")
        el.type(valor)
    page.keyboard.press("Tab")
    page.wait_for_timeout(80)


def abrir(pw, perfil):
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: erros.append(m.text) if m.type == "error" else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[perfil]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1000)
    return browser, page, erros

with sync_playwright() as pw:
    print("\n  CONTAS A PAGAR / A RECEBER")

    # ================= aritmetica =================
    browser, page, erros = abrir(pw, ADMIN)
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    reais = [e for e in erros if not any(r in e for r in ruido)]
    conf(not reais, "abre sem erro de JavaScript", " | ".join(reais[:3]))

    print("\n  -- aritmetica (a que nao pode errar) --")
    for total, n in [(100, 3), (5000, 6), (1000.01, 7), (0.05, 4), (60000, 6), (33.33, 2)]:
        r = page.evaluate(f"() => repartir({total}, {n})")
        soma = round(sum(r), 2)
        conf(soma == round(total, 2) and len(r) == n,
             f"repartir({total}, {n}) soma exato",
             f"deu {soma} em {len(r)} partes: {r}")

    # vencimento mensal com dia 31
    v = page.evaluate("() => [0,1,2,3].map(i => vencimentoDaParcela('2026-01-31', i, ''))")
    conf(v == ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
         "parcela mensal do dia 31 cai no ultimo dia de cada mes", str(v))
    v30 = page.evaluate("() => [0,1,2].map(i => vencimentoDaParcela('2026-01-15', i, '30'))")
    conf(v30 == ['2026-01-15', '2026-02-14', '2026-03-16'],
         "parcela de 30 em 30 dias", str(v30))

    # o rateio de CADA parcela tem que fechar com o valor daquela parcela
    print("\n  -- rateio por parcela --")
    calc = page.evaluate("""() => {
      const total = 1000.01, n = 3;
      const rat = [{valor: 333.34}, {valor: 333.34}, {valor: 333.33}];
      const parcelas = repartir(total, n);
      return parcelas.map(vp => {
        let acumulado = 0;
        const linhas = rat.map((r, i) => {
          const parte = (i === rat.length - 1)
            ? Math.round((vp - acumulado) * 100) / 100
            : Math.round((vp * (Number(r.valor) / total)) * 100) / 100;
          if (i < rat.length - 1) acumulado += parte;
          return parte;
        });
        return {vp, soma: Math.round(linhas.reduce((a,b)=>a+b,0) * 100) / 100};
      });
    }""")
    for c in calc:
        conf(c["soma"] == c["vp"],
             f"rateio da parcela de R$ {c['vp']} fecha", f"somou {c['soma']}")

    # ================= tela =================
    print("\n  -- tela --")
    page.evaluate("() => { state.page='contas'; render(); }")
    page.wait_for_timeout(200)
    corpo = page.inner_text("body")
    conf("Contas a Pagar" in corpo, "abre a tela de Contas a Pagar")
    conf("Adubo atrasado" in corpo, "lista o titulo vencido")
    conf("Vencido" in corpo, "marca como Vencido")
    conf("Vence hoje" in corpo, "marca o que vence hoje")

    est = page.evaluate("""() => ({
      vencido: estadoDoVencimento(state.titulos.find(t=>t.id===1)),
      hoje:    estadoDoVencimento(state.titulos.find(t=>t.id===2)),
      aberto:  estadoDoVencimento(state.titulos.find(t=>t.id===3)),
      pago:    estadoDoVencimento(state.titulos.find(t=>t.id===4)),
    })""")
    conf(est == {"vencido": "vencido", "hoje": "hoje", "aberto": "aberto", "pago": "pago"},
         "classifica cada situacao certo", str(est))

    saldo = page.evaluate("() => saldoDoTitulo(state.titulos.find(t=>t.id===3))")
    conf(saldo == 2000.0, "saldo do parcial e 5000 - 3000", str(saldo))

    # a aba A Receber nao mistura com a A Pagar
    page.evaluate("() => { state.abaContas='receber'; state.filtroContas='todos'; render(); }")
    page.wait_for_timeout(150)
    receber = page.inner_text("body")
    conf("Venda de cana" in receber, "aba A Receber mostra o titulo de receita")
    conf("Adubo atrasado" not in receber, "aba A Receber nao mistura conta a pagar")

    # filtro de previsao
    page.evaluate("() => { state.abaContas='pagar'; state.filtroContas='previsao'; render(); }")
    page.wait_for_timeout(150)
    prev = page.inner_text("body")
    conf("Esperado" in prev, "filtro Previsao mostra so o marcado como previsao")
    conf("Adubo atrasado" not in prev, "filtro Previsao esconde os demais")

    # o titulo sem rateio e denunciado
    page.evaluate("""() => { state.filtroContas='todos';
      state.titulos.push({id:99, tipo:'pagar', entidadeId:5, descricao:'Sem rateio nenhum',
        valor:100, vencimento:'2026-12-01', parcela:1, parcelas:1, previsao:false,
        cancelado:false, valorBaixado:0, situacao:'aberto'}); render(); }""")
    page.wait_for_timeout(150)
    conf("sem rateio" in page.inner_text("body"),
         "titulo sem rateio aparece marcado (a baixa dele falharia)")
    # ---- fornecedor novo e cadastrado no proprio lancamento ----
    # O Eduardo pediu isto explicitamente. Em vez de afirmar que funciona,
    # o teste preenche o formulario com um nome que NAO existe em entidades
    # e confere que a tela mandou o insert.
    page.evaluate("""() => {
      window.__ESCRITAS__ = [];
      state.page='contas'; state.abaContas='pagar'; state.erroTitulo='';
      editDraft = {tipo:'pagar', valor:'', vencimento:'2026-12-10', parcelas:1,
                   intervaloDias:'', previsao:false, rateios:[rateioVazio()]};
      state.modal = {type:'titulo'}; render();
    }""")
    page.wait_for_timeout(200)
    # digitar e sair do campo, como uma pessoa faz. page.fill() nao dispara
    # o evento change, entao os campos que recalculam nao veriam o valor —
    # o teste passaria a testar o Playwright, nao o app.
    preencher(page, "#f-tit-entidade", "TRANSPORTADORA NUNCA VISTA LTDA")
    preencher(page, "#f-tit-descricao", "Frete do adubo")
    preencher(page, "#f-tit-valor", "1500")
    page.select_option("#f-rat-centro-0", "90")
    preencher(page, "#f-rat-comp-0", "2026-12")
    preencher(page, "#f-rat-valor-0", "1500")
    page.click("[data-save='titulo']")
    page.wait_for_timeout(400)

    escritas = page.evaluate("() => window.__ESCRITAS__")
    ents = [e for e in escritas if e["tabela"] == "entidades" and e["op"] == "insert"]
    conf(len(ents) == 1, "fornecedor desconhecido e cadastrado ao salvar a conta",
         f"escritas em entidades: {ents}")
    if ents:
        conf(ents[0]["v"].get("nome") == "TRANSPORTADORA NUNCA VISTA LTDA",
             "cadastra com o nome digitado", str(ents[0]["v"]))
        conf(ents[0]["v"].get("criado_por") == "Eduardo",
             "registra quem cadastrou", str(ents[0]["v"]))
    tits = [e for e in escritas if e["tabela"] == "titulos" and e["op"] == "insert"]
    conf(len(tits) == 1, "e o titulo e salvo na mesma acao", str(len(tits)))

    # ---- fornecedor que JA existe nao vira duplicata ----
    # O indice unico do banco e por lower(btrim(nome)): se a tela comparasse
    # de outro jeito, "agrosaquy  " tentaria criar e tomaria erro 23505.
    page.evaluate("""() => {
      window.__ESCRITAS__ = [];
      editDraft = {tipo:'pagar', valor:'', vencimento:'2026-12-10', parcelas:1,
                   intervaloDias:'', previsao:false, rateios:[rateioVazio()]};
      state.modal = {type:'titulo'}; render();
    }""")
    page.wait_for_timeout(200)
    preencher(page, "#f-tit-entidade", "  agrosaquy  ")
    preencher(page, "#f-tit-descricao", "Compra qualquer")
    preencher(page, "#f-tit-valor", "200")
    page.select_option("#f-rat-centro-0", "90")
    preencher(page, "#f-rat-comp-0", "2026-12")
    preencher(page, "#f-rat-valor-0", "200")
    page.click("[data-save='titulo']")
    page.wait_for_timeout(400)
    escritas2 = page.evaluate("() => window.__ESCRITAS__")
    ents2 = [e for e in escritas2 if e["tabela"] == "entidades" and e["op"] == "insert"]
    conf(len(ents2) == 0,
         "fornecedor que ja existe (outra caixa e com espacos) nao e duplicado",
         f"tentou cadastrar de novo: {ents2}")

    browser.close()

    # ================= permissao =================
    print("\n  -- permissao --")
    for perfil, deve_ver, deve_excluir, rotulo in [
        (ADMIN,      True,  True,  "admin"),
        (DONO,       True,  True,  "proprietario"),
        (ESCRIT,     True,  False, "colaborador com a chave contas"),
        (SEM_CONTAS, False, False, "financeiro mas sem a chave contas"),
    ]:
        browser, page, _ = abrir(pw, perfil)
        paginas = page.evaluate("() => paginasVisiveis().map(p=>p.key)")
        conf(("contas" in paginas) == deve_ver,
             f"{rotulo}: {'ve' if deve_ver else 'NAO ve'} a aba Contas", str(paginas))
        if deve_ver:
            page.evaluate("() => { state.page='contas'; state.filtroContas='todos'; render(); }")
            page.wait_for_timeout(200)
            tem_excluir = page.locator("[data-del-titulo]").count() > 0
            conf(tem_excluir == deve_excluir,
                 f"{rotulo}: {'pode' if deve_excluir else 'NAO pode'} excluir")
        browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
