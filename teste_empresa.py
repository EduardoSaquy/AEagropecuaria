"""
Resultados > Empresa (AEMatriz.html): a empresa inteira como uma atividade so.

Pedido do Eduardo em 14/10/2026: fluxo de caixa, juros pagos por ano e por
ano-safra, cobertura de juros e divida, olhando a empresa toda.

O que este teste prova, com contas conhecidas (cenario de 2025):
  - os blocos do fluxo de caixa saem do GRUPO do plano de contas (operacional,
    investimento, financiamento, variacoes nao operacionais);
  - juros e despesas financeiras NAO entram no resultado operacional;
  - amortizacao e entrada de emprestimo (movimentos_financiamento e modulo
    Financiamentos) entram no fluxo, mas nao viram despesa/receita;
  - o juros das parcelas pagas do modulo NAO e somado de novo (ja esta em
    lancamentos_financeiros);
  - contrato nascido de renegociacao nao e dinheiro novo entrando;
  - movimento com data no futuro e divida a vencer, nao fluxo realizado;
  - sem movimentos nem modulo, a variacao de caixa bate com o Fluxo de Caixa
    que ja existe em Relatorios (mesma base de lancamentos);
  - a aba le o Financeiro direto, nao a visao rateada (que em 2026 estava R$ 645
    mil abaixo), e avisa na tela quando a visao rateada tem menos despesa;
  - ano e ano-safra (maio a abril) pegam as janelas certas.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

# "hoje" fixo em 14/10/2026: a janela de anos/safras e o corte realizado x a
# vencer nao podem depender do dia em que o teste roda.
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

def lanc(i, tipo, centro_id, valor, mes, desc, data=True):
    return {"id": i, "tipo": tipo, "atividade": "geral", "fazenda_id": None, "centro_custo_id": centro_id,
            "descricao": desc, "valor": valor, "data": f"{mes}-10" if data else None, "mes": mes, "areas": []}

DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "centros_custo": [
        centro(1, "VENDAS", "entrada", "ATIVIDADES OPERACIONAIS"),
        centro(2, "DESPESA GERAL", "saida", "OPERACIONAL | OUTRAS"),
        centro(3, "JUROS PAGOS OU INCORRIDOS", "saida", "FINANCIAMENTOS | DESPESAS FINANCEIRAS"),
        centro(4, "IOF", "saida", "FINANCIAMENTOS | DESPESAS FINANCEIRAS"),
        centro(5, "COMPRA DE MAQUINAS", "saida", "INVESTIMENTOS | SAIDA PARA INVESTIMENTOS"),
        centro(6, "ENTRADA DE FINANCIAMENTOS", "entrada", "ATIVIDADES DE FINANCIAMENTO"),
        centro(7, "RENDIMENTOS DE APLICAÇÕES FINANCEIRAS", "entrada", "ATIVIDADES DE FINANCIAMENTO"),
        centro(8, "DISTRIBUIÇÃO DE LUCROS", "saida", "DIVIDENDOS"),
        # as duas grafias do mesmo grupo existem no plano de verdade
        centro(9, "AJUSTE DE SALDO BANCÁRIO", "saida", "VARIACOES NAO OPERACIONAIS DE CAIXA"),
        centro(10, "RESGATE DE APLICAÇÕES FINANCEIRAS", "entrada", "VARIAÇÕES NÃO OPERACIONAIS DE CAIXA"),
        centro(11, "Juros e Encargos de Financiamento", "saida", "FINANCIAMENTOS | DESPESAS FINANCEIRAS"),
    ],
    "lancamentos_financeiros": [
        lanc(1, "receita", 1, 1000000, "2025-06", "Venda"),
        lanc(2, "despesa", 2, 400000, "2025-07", "Custeio"),
        lanc(3, "despesa", 3, 50000, "2025-08", "Juros banco"),
        lanc(4, "despesa", 4, 2000, "2025-08", "IOF"),
        lanc(5, "investimento", 5, 100000, "2025-09", "Trator"),
        lanc(6, "receita", 6, 300000, "2025-03", "Entrada de financiamento"),
        lanc(7, "receita", 7, 1000, "2025-03", "Rendimento"),
        lanc(8, "despesa", 8, 20000, "2025-10", "Distribuicao"),
        lanc(9, "despesa", 9, 500, "2025-11", "Ajuste"),
        lanc(10, "receita", 10, 5000, "2025-11", "Resgate"),
        lanc(11, "despesa", 11, 7000, "2025-12", "Juros do modulo"),
        # fevereiro/2026 pertence ao ano 2026 e ao ano-safra 2025/26
        lanc(12, "despesa", 3, 30000, "2026-02", "Juros banco 2026"),
        # recorrente: sem data e sem mes, vale todo mes (1000 x 12 = 12000 no ano)
        {"id": 13, "tipo": "despesa", "atividade": "geral", "fazenda_id": None, "centro_custo_id": 2,
         "descricao": "Aluguel", "valor": 1000, "data": None, "mes": None, "areas": []},
    ],
    "movimentos_financiamento": [
        {"id": 1, "data": "2025-04-10", "tipo": "amortizacao", "valor": 80000, "credor": "BANCO X", "descricao": "", "origem": "conag"},
        {"id": 2, "data": "2024-12-15", "tipo": "amortizacao", "valor": 50000, "credor": "BANCO X", "descricao": "", "origem": "conag"},
        {"id": 3, "data": "2099-01-01", "tipo": "amortizacao", "valor": 200000, "credor": "BANCO X", "descricao": "", "origem": "conag"},
        {"id": 4, "data": "2025-02-01", "tipo": "entrada", "valor": 40000, "credor": "BANCO X", "descricao": "", "origem": "manual"},
    ],
    "financiamentos": [
        {"id": 1, "banco": "BB", "finalidade": "investimento", "valor_principal": 150000, "valor_iof": 0, "valor_seguro": 0,
         "data_contratacao": "2025-05-20", "taxa_juros_aa": 9, "sistema_amortizacao": "price", "numero_parcelas": 6,
         "carencia_meses": 0, "atividade": "pecuaria", "fazenda_id": None, "garantia": None, "status": "renegociado",
         "financiamento_origem_id": None, "observacao": None},
        # nasceu da renegociacao do 1: NAO e dinheiro novo entrando
        {"id": 2, "banco": "BB", "finalidade": "investimento", "valor_principal": 120000, "valor_iof": 0, "valor_seguro": 0,
         "data_contratacao": "2025-11-10", "taxa_juros_aa": 8, "sistema_amortizacao": "price", "numero_parcelas": 4,
         "carencia_meses": 0, "atividade": "pecuaria", "fazenda_id": None, "garantia": None, "status": "ativo",
         "financiamento_origem_id": 1, "observacao": None},
    ],
    "parcelas_financiamento": [
        {"id": 1, "financiamento_id": 1, "numero": 1, "data_vencimento": "2025-09-20", "valor_parcela": 28000,
         "valor_amortizacao": 25000, "valor_juros": 3000, "saldo_devedor_apos": 125000, "status": "paga",
         "data_pagamento": "2025-09-20", "valor_pago": 28000, "lancamentos_financeiro_ids": []},
        {"id": 2, "financiamento_id": 1, "numero": 2, "data_vencimento": "2025-10-20", "valor_parcela": 28000,
         "valor_amortizacao": 25000, "valor_juros": 3000, "saldo_devedor_apos": 100000, "status": "cancelada",
         "data_pagamento": None, "valor_pago": None, "lancamentos_financeiro_ids": []},
        {"id": 3, "financiamento_id": 2, "numero": 1, "data_vencimento": "2026-12-10", "valor_parcela": 31000,
         "valor_amortizacao": 30000, "valor_juros": 1000, "saldo_devedor_apos": 90000, "status": "pendente",
         "data_pagamento": None, "valor_pago": None, "lancamentos_financeiro_ids": []},
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

    print("\n  RESULTADOS > EMPRESA")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- 1. blocos do fluxo de caixa: ano 2025 ----
    f = page.evaluate("() => fluxoEmpresa({tipo:'ano', ano:2025})")
    op, inv, fin, nao = f["operacional"], f["investimento"], f["financiamento"], f["naoOperacional"]
    conf(perto(op["entradas"], 1000000) and perto(op["saidas"], 412000) and perto(op["liquido"], 588000),
         "operacional: recebimentos 1.000.000, pagamentos 412.000 (400.000 + 12 x 1.000 de recorrente), liquido 588.000 antes dos juros",
         str(op))
    conf(perto(inv["compras"], 100000) and perto(inv["liquido"], -100000),
         "investimento: compra de 100.000 (lancamento tipo investimento)", str(inv))
    conf(perto(fin["juros"], 57000),
         "juros pagos = 50.000 (JUROS PAGOS OU INCORRIDOS) + 7.000 (Juros e Encargos de Financiamento, centro do modulo)", str(fin))
    conf(perto(fin["outrasDespesasFinanceiras"], 2000) and perto(fin["dividendos"], 20000) and perto(fin["receitasFinanceiras"], 1000),
         "financiamento: IOF 2.000 em outras despesas financeiras, dividendos 20.000, rendimentos 1.000 em receitas financeiras", str(fin))
    conf(perto(nao["entradas"], 5000) and perto(nao["saidas"], 500) and perto(nao["liquido"], 4500),
         "variacoes nao operacionais: as duas grafias do grupo (VARIACOES/VARIAÇÕES) caem no mesmo bloco", str(nao))
    conf(perto(op["saidas"] + fin["juros"] + fin["outrasDespesasFinanceiras"], 412000 + 57000 + 2000),
         "juros e encargos nao estao no operacional (so no bloco financiamento)")

    # ---- 2. principal: movimentos + modulo, sem duplicar o juros ----
    conf(perto(fin["amortizacao"], 105000),
         "amortizacao 2025 = 80.000 (movimento) + 25.000 (parcela paga do modulo); o de 2024, o futuro e a parcela cancelada ficam de fora", str(fin))
    conf(perto(fin["emprestimosRecebidos"], 490000),
         "emprestimos recebidos = 300.000 (lancamento) + 40.000 (movimento) + 150.000 (contrato 1); o contrato 2 e renegociacao, nao entra", str(fin))
    conf(perto(fin["liquido"], 307000),
         "financiamento liquido = 490.000 + 1.000 - 105.000 - 57.000 - 2.000 - 20.000 = 307.000 (juros da parcela paga NAO somado de novo)", str(fin))
    conf(perto(f["variacaoCaixa"], 799500),
         "variacao de caixa = 588.000 - 100.000 + 307.000 + 4.500 = 799.500", str(f["variacaoCaixa"]))

    # ---- 3. bate com o Fluxo de Caixa que ja existia (mesma base de lancamentos) ----
    rel = page.evaluate("() => fluxoCaixaRelatorio({tipo:'ano', ano:2025})")
    liquido_principal = (40000 + 150000) - (80000 + 25000)   # o que movimentos e modulo somam
    conf(perto(f["variacaoCaixa"] - liquido_principal, rel["resultadoPeriodo"]),
         "sem o principal de movimentos/modulo, a variacao de caixa bate com Relatorios > Fluxo de Caixa (714.500)",
         f"{f['variacaoCaixa'] - liquido_principal} x {rel['resultadoPeriodo']}")

    # ---- 3b. le o Financeiro direto, nao a visao rateada ----
    # Em 14/10/2026 a visao rateada estava R$ 645 mil abaixo do Financeiro em 2026
    # (rateio incompleto de custos gerais de maio/2026 em diante). A aba da
    # empresa inteira nao pode herdar esse buraco.
    indep = page.evaluate("""() => { const salvo = state.lancamentosRateados; state.lancamentosRateados = [];
        const r = calcularFluxoEmpresa({tipo:'ano', ano:2025}); state.lancamentosRateados = salvo; return r; }""")
    conf(perto(indep["variacaoCaixa"], f["variacaoCaixa"]) and perto(indep["operacional"]["saidas"], 412000),
         "o fluxo nao muda com a visao rateada vazia: a aba le lancamentos_financeiros direto", str(indep["operacional"]))

    # ---- 4. ano-safra (maio a abril) ----
    s = page.evaluate("() => fluxoEmpresa({tipo:'safra', safra:2025})")
    conf(perto(s["financiamento"]["juros"], 87000),
         "safra 2025/26 (mai/25 a abr/26): juros 50.000 + 7.000 + 30.000 de fevereiro/2026 = 87.000", str(s["financiamento"]))
    conf(perto(s["financiamento"]["emprestimosRecebidos"], 150000) and perto(s["financiamento"]["amortizacao"], 25000),
         "safra 2025/26: entrada de marco/25 e amortizacao de abril/25 ficam de fora (sao da safra anterior); entram o contrato 1 e a parcela paga",
         str(s["financiamento"]))
    a24 = page.evaluate("() => fluxoEmpresa({tipo:'ano', ano:2024})")
    conf(perto(a24["financiamento"]["amortizacao"], 50000), "ano 2024: amortizacao de dezembro/24 (50.000)", str(a24["financiamento"]))

    # ---- 5. historico por ano e por ano-safra ----
    h = page.evaluate("() => historicoEmpresa()")
    anos = {x["rotulo"]: x for x in h["anos"]}
    safras = {x["rotulo"]: x for x in h["safras"]}
    conf(list(anos) == ["2023", "2024", "2025", "2026"] and list(safras) == ["2023/24", "2024/25", "2025/26", "2026/27"],
         "historico: 4 anos (2023-2026) e 4 anos-safra (2023/24 a 2026/27) com 'hoje' em 14/10/2026", f"{list(anos)} {list(safras)}")
    conf(perto(anos["2025"]["juros"], 57000) and perto(anos["2025"]["coberturaJuros"], 588000/57000, 0.001),
         "2025: juros 57.000 e cobertura de juros = 588.000 / 57.000 = 10,3 x", str(anos["2025"]))
    conf(perto(anos["2025"]["coberturaServico"], 588000/(57000+105000), 0.001),
         "2025: cobertura do servico da divida = 588.000 / (57.000 juros + 105.000 principal) = 3,6 x", str(anos["2025"]))
    conf(perto(safras["2025/26"]["juros"], 87000) and perto(anos["2026"]["juros"], 30000),
         "juros por ano-safra (87.000 em 2025/26) e por ano (30.000 em 2026) usam janelas diferentes", f"{safras['2025/26']} {anos['2026']}")
    conf(anos["2026"]["parcial"] is True and anos["2025"]["parcial"] is False and safras["2026/27"]["parcial"] is True,
         "ano e safra correntes marcados como parciais ('ate hoje')")
    conf(anos["2023"]["coberturaJuros"] is None,
         "periodo sem juros: cobertura vem vazia (nao divide por zero)", str(anos["2023"]))

    # ---- 6. divida ----
    d = page.evaluate("() => dividaEmpresa()")
    conf(d["origem"] == "ambos" and perto(d["saldoModulo"], 120000) and perto(d["aVencerConag"], 200000) and perto(d["valor"], 320000),
         "divida = saldo do contrato ativo (120.000) + o que o Conag ainda tem a vencer e nenhum contrato assumiu (200.000, data futura) = 320.000", str(d))
    d2 = page.evaluate("() => { const salvo = state.financiamentos; state.financiamentos = []; const r = dividaEmpresa(); state.financiamentos = salvo; return r; }")
    conf(d2["origem"] == "conag" and perto(d2["valor"], 200000),
         "divida: sem contrato no modulo, mostra a estimativa do Conag (so movimentos com data futura)", str(d2))

    # ---- 6b. contrato que assumiu linhas do Conag: elas deixam de contar ----
    # (Lancar contrato do Conag grava financiamento_id; ver teste_financiamentos_conag.py)
    page.evaluate("() => { state.movimentosFinanciamento = state.movimentosFinanciamento.map(m => m.id === 3 ? {...m, financiamentoId: 2} : m); }")
    d3 = page.evaluate("() => dividaEmpresa()")
    conf(d3["origem"] == "modulo" and perto(d3["valor"], 120000) and perto(d3["aVencerConag"], 0),
         "linha futura do Conag assumida pelo contrato 2: a divida volta a ser so o saldo dele (120.000), sem contar a mesma divida duas vezes", str(d3))
    page.evaluate("() => { state.movimentosFinanciamento = state.movimentosFinanciamento.map(m => m.id === 1 ? {...m, financiamentoId: 2} : m); }")
    f_assumida = page.evaluate("() => fluxoEmpresa({tipo:'ano', ano:2025})")
    conf(perto(f_assumida["financiamento"]["amortizacao"], 25000),
         "linha paga do Conag (80.000) assumida pelo contrato: sai do fluxo de 2025 (fica so os 25.000 da parcela paga do modulo)", str(f_assumida["financiamento"]))
    page.evaluate("() => { state.financiamentos = state.financiamentos.map(f => f.id === 2 ? {...f, status: 'cancelado'} : f); }")
    f_cancelado = page.evaluate("() => fluxoEmpresa({tipo:'ano', ano:2025})")
    d4 = page.evaluate("() => dividaEmpresa()")
    conf(perto(f_cancelado["financiamento"]["amortizacao"], 25000 + 80000) and perto(d4["aVencerConag"], 200000),
         "contrato cancelado devolve as linhas ao Conag: amortizacao de 2025 volta a 105.000 e a divida a vencer a 200.000", f"{f_cancelado['financiamento']} {d4}")
    # volta ao cenario original para as checagens da tela
    page.evaluate("""() => {
      state.movimentosFinanciamento = state.movimentosFinanciamento.map(m => ({...m, financiamentoId: null}));
      state.financiamentos = state.financiamentos.map(f => f.id === 2 ? {...f, status: 'ativo'} : f); }""")

    # ---- 7. a tela ----
    page.evaluate("() => { state.periodo = {tipo:'ano', ano:2025, mes:'2025-06', safra:2025}; state.page = 'resultados'; render(); }")
    page.wait_for_timeout(300)
    botoes = page.evaluate("() => [...document.querySelectorAll('[data-suba-resultados]')].map(b => b.innerText)")
    conf(botoes == ["Geral", "Operacional", "Relatórios", "Empresa"], "Resultados tem a aba 'Empresa' ao lado de Geral, Operacional e Relatorios", str(botoes))
    page.click('[data-suba-resultados="empresa"]')
    page.wait_for_timeout(500)
    texto = page.evaluate("() => document.body.innerText.toLowerCase()")
    for trecho in ["a empresa como uma atividade só", "fluxo de caixa", "resultado operacional (antes dos juros)",
                   "amortização do principal", "variação de caixa do período", "cobertura de juros",
                   "ano (janeiro a dezembro)", "ano-safra (maio a abril)", "dívida (contratos + conag)", "r$ 320.000,00",
                   "r$ 120.000,00 em contratos lançados + r$ 200.000,00 ainda só no conag"]:
        conf(trecho in texto, f"tela mostra: {trecho}")
    conf("r$ 799.500,00" in texto, "tela mostra a variacao de caixa de 2025 (R$ 799.500,00)")
    conf("rode financiamentos_02_movimentos_conag.sql" not in texto, "com a tabela de movimentos existindo, nao pede o script")
    conf("a menos de despesa que o financeiro" not in texto,
         "visao rateada igual ao Financeiro: nenhum aviso de diferenca")

    # ---- 7b. sem rolar de lado (pedido do Eduardo, 14/10/2026) ----
    # A tabela do historico tem 7 colunas e, com os titulos em linha unica,
    # passava 21 px do card em tela de 1280. Nenhum card da aba pode precisar
    # de barra de rolagem lateral, nem a pagina inteira; no celular cada linha
    # do historico vira um bloco com o nome da coluna ao lado do valor.
    # A pagina so rola de lado se algo passar da coluna central (.main), nao
    # apenas da janela: com barra de rolagem vertical (Windows) a janela tem
    # 15 px a menos que innerWidth, e as 4 abas de Resultados (361 px) passavam
    # da tela de 376 px sem este teste perceber.
    medir = """() => {
        const raiz = document.documentElement;
        const pagina = raiz.scrollWidth - raiz.clientWidth;
        const cards = [...document.querySelectorAll('.card')].map(c => c.scrollWidth - c.clientWidth);
        const main = document.querySelector('.main');
        const limite = main.getBoundingClientRect().right - parseFloat(getComputedStyle(main).paddingRight) + 0.5;
        const sobram = [...main.children].filter(e => e.getBoundingClientRect().right > limite)
            .map(e => (String(e.className) || e.tagName) + '=' + Math.round(e.getBoundingClientRect().right) + '>' + Math.round(limite));
        const th = document.querySelector('.tabela-em-blocos thead th');
        const blocos = document.querySelectorAll('.tabela-em-blocos tbody tr:not(.linha-secao)').length;
        const rotulos = [...document.querySelectorAll('.tabela-em-blocos td[data-rotulo]')].slice(0, 6)
            .map(td => getComputedStyle(td, '::before').content);
        return {pagina, maiorCard: Math.max(0, ...cards), sobram, cabecalhoVisivel: !!th && th.offsetParent !== null, blocos, rotulos};
    }"""
    for largura, altura in [(1280, 800), (1000, 800), (800, 900), (390, 844), (376, 800), (360, 800), (320, 640)]:
        page.set_viewport_size({"width": largura, "height": altura})
        page.wait_for_timeout(300)
        m = page.evaluate(medir)
        conf(m["pagina"] <= 0 and m["maiorCard"] <= 1 and not m["sobram"],
             f"{largura} px: a pagina, os cards e as abas de Resultados cabem na tela, sem rolar de lado (pagina={m['pagina']}, maior card={m['maiorCard']}, passam da coluna={m['sobram']})", str(m))
        if largura > 900:
            conf(m["cabecalhoVisivel"], f"{largura} px: o historico continua tabela, com cabecalho")
        else:
            conf(not m["cabecalhoVisivel"] and m["blocos"] == 8
                 and all(r not in ('none', 'normal', '""') for r in m["rotulos"]),
                 f"{largura} px: cada um dos 8 periodos do historico vira um bloco com o nome da coluna ao lado do valor", str(m))
    page.set_viewport_size({"width": 1280, "height": 720})
    page.wait_for_timeout(200)

    # simula o buraco: a visao rateada perde o lancamento de custeio de 400.000
    page.evaluate("() => { state.lancamentosRateados = state.lancamentosRateados.filter(l => l.id !== 2); render(); }")
    page.wait_for_timeout(300)
    texto_buraco = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("tem r$ 400.000,00 a menos de despesa que o financeiro" in texto_buraco
         and "rateio_confere_soma_das_partes.sql" in texto_buraco,
         "visao rateada com R$ 400.000 a menos: a tela avisa quanto falta e qual script rodar")
    conf("r$ 799.500,00" in texto_buraco,
         "mesmo com o buraco na visao rateada, a variacao de caixa da empresa continua R$ 799.500,00")

    page.evaluate("() => { state.movimentosFinanciamentoOk = false; render(); }")
    page.wait_for_timeout(200)
    texto2 = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("financiamentos_02_movimentos_conag.sql" in texto2 and "ainda não importada do conag" in texto2,
         "tabela de movimentos ausente: a tela avisa qual script rodar, em vez de quebrar")

    # mes sem nenhum juros: cobertura em branco, tela nao quebra
    page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2023-03', safra:2022, ano:2023}; render(); }")
    page.wait_for_timeout(200)
    texto3 = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("sem juros pagos no período" in texto3, "mes sem juros: o card de cobertura explica em vez de mostrar numero")

    conf(not [e for e in erros if not any(r in e for r in ruido)], "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))
    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
sys.exit(1 if falhas else 0)
