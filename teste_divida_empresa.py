"""
Resultados > Empresa, Fase 2: a divida no tempo (pedido do Eduardo, 14-15/10/2026:
"endividamento, taxa media de juros pagos e valor dos juros pagos por ano e por
ano safra").

O que este teste prova, com contas conhecidas (hoje = 14/10/2026):
  - vencimentos da divida: o que vence em 12 meses x depois, por ano e por
    ano-safra (maio a abril), juntando parcelas em aberto dos contratos lancados
    (com o juros estimado) e linhas do ERP que nenhum contrato assumiu (so
    principal); o total bate com o card "Divida";
  - taxa media dos contratos = ponderada pelo saldo devedor;
  - saldo medio da divida (escada: sobe no inicio do contrato, cai a cada
    pagamento) e custo medio = juros pagos / saldo medio, so em periodo fechado;
  - lancar o contrato do ERP nao muda o saldo medio estimado (a data do
    contrato lancado e a mesma que o app estimava para as linhas soltas);
  - a tela mostra os cards, a tabela de vencimentos e as colunas novas do
    historico, sem rolar de lado de 1280 a 320 px.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

RELOGIO = """(() => {
  const R = Date, FIXO = new R(2026, 9, 14, 12, 0, 0).getTime();
  class D extends R {
    constructor(...a){ if(a.length === 0) super(FIXO); else super(...a); }
    static now(){ return FIXO; }
  }
  window.Date = D;
})();"""

def centro(i, nome, tipo, sub):
    return {"id": i, "fazenda_id": None, "nome": nome, "frente": None, "ativo": True, "tipo": tipo, "subcategoria": sub}

def lanc(i, tipo, centro_id, valor, mes, desc):
    return {"id": i, "tipo": tipo, "atividade": "geral", "fazenda_id": None, "centro_custo_id": centro_id,
            "descricao": desc, "valor": valor, "data": f"{mes}-10", "mes": mes, "areas": []}

def fin(i, banco, principal, data, taxa, n, status="ativo", obs=None):
    return {"id": i, "banco": banco, "finalidade": "custeio", "valor_principal": principal, "valor_iof": 0, "valor_seguro": 0,
            "data_contratacao": data, "taxa_juros_aa": taxa, "sistema_amortizacao": "sac", "numero_parcelas": n,
            "carencia_meses": 0, "atividade": "graos", "fazenda_id": None, "garantia": None, "status": status,
            "financiamento_origem_id": None, "observacao": obs}

def parc(i, fid, n, venc, amort, juros, saldo, status="pendente", pago=None):
    return {"id": i, "financiamento_id": fid, "numero": n, "data_vencimento": venc, "valor_parcela": amort + juros,
            "valor_amortizacao": amort, "valor_juros": juros, "saldo_devedor_apos": saldo, "status": status,
            "data_pagamento": pago, "valor_pago": (amort + juros) if pago else None, "lancamentos_financeiro_ids": []}

def mov(i, data, valor, contrato, fid=None):
    return {"id": i, "data": data, "tipo": "amortizacao", "valor": valor, "credor": "BANCO X", "contrato": contrato,
            "descricao": "", "origem": "erp", "erp_id": 1000 + i, "financiamento_id": fid}

OBS_ERP = ("Importado do ERP (contrato I-1): cronograma real, uma parcela por linha do ERP; "
             "juros das parcelas a vencer estimado pela taxa informada.")

DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "centros_custo": [
        centro(1, "VENDAS", "entrada", "ATIVIDADES OPERACIONAIS"),
        centro(2, "DESPESA GERAL", "saida", "OPERACIONAL | OUTRAS"),
        centro(3, "JUROS PAGOS OU INCORRIDOS", "saida", "FINANCIAMENTOS | DESPESAS FINANCEIRAS"),
    ],
    "lancamentos_financeiros": [
        lanc(1, "receita", 1, 900000, "2025-06", "Venda"),
        lanc(2, "despesa", 2, 300000, "2025-07", "Custo"),
        lanc(3, "despesa", 3, 60000, "2025-03", "Juros 2025"),
        lanc(4, "receita", 1, 500000, "2026-03", "Venda 2026"),
        lanc(5, "despesa", 3, 5000, "2026-02", "Juros 2026 (parcial)"),
    ],
    "financiamentos": [
        fin(1, "Banco A", 120000, "2026-04-14", 12, 4),                       # a mao, em aberto
        fin(2, "Banco I", 200000, "2025-01-01", 10, 2, obs=OBS_ERP),       # importado do ERP
    ],
    "parcelas_financiamento": [
        parc(1, 1, 1, "2026-11-10", 30000, 1200, 90000),
        parc(2, 1, 2, "2027-02-10", 30000, 900, 60000),
        parc(3, 1, 3, "2027-10-14", 30000, 600, 30000),     # exatamente hoje + 12 meses: ainda e "12 meses"
        parc(4, 1, 4, "2027-12-10", 30000, 300, 0),
        parc(5, 2, 1, "2025-11-15", 100000, 0, 100000, status="paga", pago="2025-11-15"),
        parc(6, 2, 2, "2026-11-16", 100000, 5000, 0),
    ],
    "movimentos_financiamento": [
        # linhas do contrato importado (ja assumidas: nao contam no ERP)
        mov(1, "2025-11-15", 100000, "I-1", 2), mov(2, "2026-11-16", 100000, "I-1", 2),
        # contrato que ainda so existe no ERP: 1 paga + 2 a vencer
        mov(3, "2026-05-15", 50000, "X-1"), mov(4, "2028-05-15", 50000, "X-1"), mov(5, "2029-05-15", 50000, "X-1"),
    ],
    "profiles": [{"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}],
}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def perto(a, b, tol=0.01):
    return a is not None and abs(a - b) < tol

exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(RELOGIO)
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)};"
        "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_timeout(2500)

    print("\n  RESULTADOS > EMPRESA > DIVIDA NO TEMPO")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- 1. vencimentos ----
    v = page.evaluate("() => vencimentosDaDivida()")
    conf(len(v["itens"]) == 7, "7 vencimentos: 4 parcelas do contrato A + 1 do importado + 2 linhas soltas do ERP", str(len(v["itens"])))
    conf(perto(v["curto"]["principal"], 190000) and perto(v["curto"]["juros"], 7700),
         "vence em 12 meses (ate 14/10/2027): principal 90.000 (A) + 100.000 (importado) = R$ 190.000; juros estimado 2.700 + 5.000 = R$ 7.700", str(v["curto"]))
    conf(perto(v["longo"]["principal"], 130000) and perto(v["longo"]["juros"], 300),
         "depois de 12 meses: 30.000 (A) + 100.000 (ERP solto) = R$ 130.000; juros estimado 300", str(v["longo"]))
    conf(perto(v["vencido"]["principal"], 0), "nada vencido em aberto")
    por_ano = {x["chave"]: x for x in v["porAno"]}
    conf(sorted(por_ano) == ["2026", "2027", "2028", "2029"]
         and perto(por_ano["2026"]["principal"], 130000) and perto(por_ano["2026"]["juros"], 6200)
         and perto(por_ano["2027"]["principal"], 90000) and perto(por_ano["2027"]["juros"], 1800)
         and perto(por_ano["2028"]["principal"], 50000) and perto(por_ano["2029"]["principal"], 50000),
         "por ano: 2026 R$ 130.000 (juros 6.200), 2027 R$ 90.000 (1.800), 2028 R$ 50.000, 2029 R$ 50.000", str(v["porAno"]))
    por_safra = {x["chave"]: x for x in v["porSafra"]}
    conf(sorted(por_safra) == ["2026", "2027", "2028", "2029"]
         and perto(por_safra["2026"]["principal"], 160000) and perto(por_safra["2026"]["juros"], 7100)
         and perto(por_safra["2027"]["principal"], 60000) and perto(por_safra["2027"]["juros"], 900)
         and perto(por_safra["2028"]["principal"], 50000) and perto(por_safra["2029"]["principal"], 50000),
         "por ano-safra (maio a abril): 2026/27 R$ 160.000 (nov/26, nov/26 e fev/27), 2027/28 R$ 60.000, 2028/29 e 2029/30 R$ 50.000 cada", str(v["porSafra"]))
    por_origem = {x["chave"]: (x["doContrato"], x["doErp"]) for x in v["porAno"]}
    conf(perto(por_origem["2028"][1], 50000) and perto(por_origem["2028"][0], 0) and perto(por_origem["2026"][0], 130000),
         "cada periodo separa o que e de contrato lancado do que ainda so esta no ERP", str(por_origem))
    d = page.evaluate("() => dividaEmpresa()")
    conf(perto(v["total"]["principal"], d["valor"]) and perto(d["valor"], 320000) and d["origem"] == "ambos",
         "o total dos vencimentos (principal R$ 320.000) bate com o card 'Divida': 220.000 em contratos + 100.000 no ERP", f"{v['total']} {d}")

    # ---- 2. taxa media dos contratos ----
    t = page.evaluate("() => taxaMediaContratos()")
    esperada = (120000 * 12 + 100000 * 10) / 220000
    conf(t and perto(t["taxa"], esperada, 0.0001) and t["contratos"] == 2 and perto(t["saldo"], 220000),
         f"taxa media ponderada pelo saldo: (120.000 x 12% + 100.000 x 10%) / 220.000 = {esperada:.4f}% a.a.", str(t))

    # ---- 3. saldo medio e custo medio ----
    # periodo em andamento (2026): tem saldo, mas nao tem custo medio (juros incompletos)
    h0 = page.evaluate("() => historicoEmpresa()")
    a26_0 = {x["rotulo"]: x for x in h0["anos"]}["2026"]
    conf(a26_0["parcial"] and a26_0["saldoMedio"] > 0 and a26_0["custoMedio"] is None,
         "2026 em andamento tem saldo medio da divida, mas nenhum custo medio", str(a26_0))
    # cenario limpo: 1 contrato de R$ 1.200.000 desde 01/01/2025, quitado em 01/07/2025
    page.evaluate("""() => {
        state.financiamentos = [{id:1, banco:'S', finalidade:'custeio', valorPrincipal:1200000, dataContratacao:'2025-01-01', taxaJurosAa:10,
          sistemaAmortizacao:'sac', numeroParcelas:1, carenciaMeses:0, atividade:'graos', fazendaId:null, garantia:'', status:'quitado', financiamentoOrigemId:null, observacao:''}];
        state.parcelasFinanciamento = [{id:1, financiamentoId:1, numero:1, dataVencimento:'2025-07-01', valorParcela:1260000, valorAmortizacao:1200000,
          valorJuros:60000, saldoDevedorApos:0, status:'paga', dataPagamento:'2025-07-01', valorPago:1260000, lancamentosFinanceiroIds:[]}];
        state.movimentosFinanciamento = []; }""")
    h = page.evaluate("() => historicoEmpresa()")
    a25 = {x["rotulo"]: x for x in h["anos"]}["2025"]
    esperado_medio = 1200000 * 181 / 365          # 01/01 a 01/07 = 181 dias de 365
    conf(perto(a25["saldoMedio"], esperado_medio, 0.5),
         f"saldo medio de 2025 = 1.200.000 x 181/365 = R$ {esperado_medio:,.2f} (o saldo cai a zero em 01/07)", str(a25["saldoMedio"]))
    conf(perto(a25["custoMedio"], 60000 / esperado_medio, 1e-6),
         f"custo medio de 2025 = juros pagos 60.000 / saldo medio = {60000/esperado_medio*100:.2f}% a.a.", str(a25["custoMedio"]))
    a26 = {x["rotulo"]: x for x in h["anos"]}["2026"]
    conf(a26["parcial"] and a26["custoMedio"] is None and a26["saldoMedio"] == 0,
         "2026 (em andamento) nao tem custo medio, e nao ha saldo (contrato quitado em 2025)", str(a26))
    safras = {x["rotulo"]: x for x in h["safras"]}
    s2425 = safras["2024/25"]
    # safra 2024/25 = 01/05/2024 a 30/04/2025: o contrato existe de 01/01 a 30/04/2025 = 120 dias
    esperado_s = 1200000 * 120 / 365
    conf(perto(s2425["saldoMedio"], esperado_s, 0.5),
         f"saldo medio da safra 2024/25 (mai/24 a abr/25) = 1.200.000 x 120/365 = R$ {esperado_s:,.2f}", str(s2425["saldoMedio"]))

    # ---- 4. lancar o contrato do ERP nao muda o saldo medio estimado ----
    page.evaluate("""() => {
        state.financiamentos = []; state.parcelasFinanciamento = [];
        state.movimentosFinanciamento = [
          {id:1, data:'2025-06-15', tipo:'amortizacao', valor:100000, credor:'BANCO X', contrato:'Z-9', descricao:'', origem:'erp', financiamentoId:null},
          {id:2, data:'2026-06-15', tipo:'amortizacao', valor:100000, credor:'BANCO X', contrato:'Z-9', descricao:'', origem:'erp', financiamentoId:null},
          {id:3, data:'2027-06-15', tipo:'amortizacao', valor:100000, credor:'BANCO X', contrato:'Z-9', descricao:'', origem:'erp', financiamentoId:null}];
        state.page = 'resultados'; }""")
    antes = page.evaluate("() => { const j = janelaDoPeriodo({tipo:'ano', ano:2025}); return saldoMedioDivida(linhaDoTempoDivida(), j.ini, j.fim); }")
    inicio = page.evaluate("() => inicioEstimadoErp(state.movimentosFinanciamento.map(m => m))")
    conf(inicio == "2024-06-15",
         "data estimada do contrato = 1a parcela (15/06/2025) menos o intervalo tipico entre parcelas (365 dias): 15/06/2024", str(inicio))
    page.evaluate("""(ini) => {
        state.financiamentos = [{id:7, banco:'Banco X', finalidade:'custeio', valorPrincipal:300000, dataContratacao:ini, taxaJurosAa:10,
          sistemaAmortizacao:'sac', numeroParcelas:3, carenciaMeses:0, atividade:'graos', fazendaId:null, garantia:'', status:'ativo', financiamentoOrigemId:null,
          observacao:'Importado do ERP (contrato Z-9): cronograma real, uma parcela por linha do ERP; juros das parcelas a vencer estimado pela taxa informada.'}];
        state.parcelasFinanciamento = [
          {id:1, financiamentoId:7, numero:1, dataVencimento:'2025-06-15', valorParcela:100000, valorAmortizacao:100000, valorJuros:0, saldoDevedorApos:200000, status:'paga', dataPagamento:'2025-06-15', valorPago:100000, lancamentosFinanceiroIds:[]},
          {id:2, financiamentoId:7, numero:2, dataVencimento:'2026-06-15', valorParcela:100000, valorAmortizacao:100000, valorJuros:0, saldoDevedorApos:100000, status:'paga', dataPagamento:'2026-06-15', valorPago:100000, lancamentosFinanceiroIds:[]},
          {id:3, financiamentoId:7, numero:3, dataVencimento:'2027-06-15', valorParcela:110000, valorAmortizacao:100000, valorJuros:10000, saldoDevedorApos:0, status:'pendente', dataPagamento:null, valorPago:null, lancamentosFinanceiroIds:[]}];
        state.movimentosFinanciamento = state.movimentosFinanciamento.map(m => ({...m, financiamentoId: 7})); }""", inicio)
    depois = page.evaluate("() => { const j = janelaDoPeriodo({tipo:'ano', ano:2025}); return saldoMedioDivida(linhaDoTempoDivida(), j.ini, j.fim); }")
    esperado_z = (300000 * 165 + 200000 * 200) / 365    # 300.000 de 15/06/2024 a 15/06/2025; depois 200.000
    conf(perto(antes, esperado_z, 0.01),
         f"saldo medio de 2025 do contrato ainda so no ERP = (300.000 x 165 + 200.000 x 200) / 365 = R$ {esperado_z:,.2f}", str(antes))
    conf(perto(antes, depois, 0.01) and antes > 0,
         f"lancar o contrato nao muda o saldo medio de 2025 (R$ {antes:,.2f} antes, R$ {depois:,.2f} depois)", f"{antes} x {depois}")

    # ---- 5. a tela ----
    page.reload()
    page.wait_for_timeout(2500)
    page.evaluate("() => { state.periodo = {tipo:'ano', ano:2026, mes:'2026-10', safra:2026}; state.page = 'resultados'; state.subAbaResultados = 'empresa'; render(); }")
    page.wait_for_timeout(500)
    texto = page.evaluate("() => document.body.innerText.toLowerCase()")
    for trecho in ["vence em 12 meses", "r$ 197.700,00", "r$ 190.000,00 de principal + r$ 7.700,00 de juros estimado",
                   "vence depois de 12 meses", "r$ 130.300,00", "taxa média dos contratos", "11,09 % a.a.",
                   "ponderada pelo saldo de 2 contrato(s) lançado(s)", "custo médio da dívida",
                   "vencimentos da dívida — por ano e por ano-safra", "ano (janeiro a dezembro), a partir de hoje",
                   "ano-safra (maio a abril), a partir de hoje", "2026/27", "só no erp", "contratos lançados",
                   "saldo médio da dívida (estimado)"]:
        conf(trecho in texto, f"tela mostra: {trecho}")
    cab = page.evaluate("() => [...document.querySelectorAll('table.tabela-em-blocos')].map(t => [...t.querySelectorAll('thead th')].map(th => th.innerText.toLowerCase()))")
    conf(len(cab) == 2 and len(cab[0]) == 9 and len(cab[1]) == 6, "o historico tem 9 colunas (saldo medio e custo medio entraram) e os vencimentos 6", str([len(c) for c in cab]))

    medir = """() => {
        const raiz = document.documentElement, main = document.querySelector('.main');
        const limite = main.getBoundingClientRect().right - parseFloat(getComputedStyle(main).paddingRight) + 0.5;
        const sobram = [...main.children].filter(e => e.getBoundingClientRect().right > limite).map(e => String(e.className));
        const cards = [...document.querySelectorAll('.card')].map(c => c.scrollWidth - c.clientWidth);
        return {pagina: raiz.scrollWidth - raiz.clientWidth, maiorCard: Math.max(0, ...cards), sobram};
    }"""
    for largura, altura in [(1280, 800), (1100, 800), (800, 900), (390, 844), (376, 800), (320, 640)]:
        page.set_viewport_size({"width": largura, "height": altura})
        page.wait_for_timeout(250)
        m = page.evaluate(medir)
        conf(m["pagina"] <= 0 and m["maiorCard"] <= 1 and not m["sobram"],
             f"{largura} px: cards, historico e vencimentos cabem na tela, sem rolar de lado (pagina={m['pagina']}, maior card={m['maiorCard']})", str(m))
    page.set_viewport_size({"width": 1280, "height": 720})

    conf(not [e for e in erros if not any(r in e for r in ruido)], "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))
    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
sys.exit(1 if falhas else 0)
