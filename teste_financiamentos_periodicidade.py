"""
Financiamentos: parcelas anuais (ou semestrais/trimestrais) e data do 1o
vencimento (pedido do Eduardo em 22/10/2026: "gerou parcelas mensais mesmo eu
colocando que o pagamento era anual").

Antes o cadastro so gerava parcela mensal, nao tinha a data do 1o vencimento
(so "carencia em meses") e abria em "parcela unica", que escondia o numero de
parcelas. O que este teste prova, com contas feitas a mao:
  - SAC anual: 560.000 em 7 parcelas anuais a 9% a.a. = 80.000 de amortizacao
    por ano, juros 50.400 / 43.200 / ..., vencimentos no mesmo dia de cada ano;
  - 1o vencimento longe da contratacao: o juros da 1a parcela conta o prazo
    real (20 meses), as outras o periodo normal;
  - Price anual: parcela fixa;
  - contrato antigo (sem data do 1o vencimento, mensal) gera igual a antes;
  - na tela: novo contrato abre em SAC anual, mostra o resumo do cronograma,
    exige numero de parcelas e 1o vencimento, nao aceita vencimento antes da
    contratacao e grava periodicidade e 1o vencimento;
  - editar um contrato mensal sem parcela paga (o caso do Eduardo) traz o 1o
    vencimento da 1a parcela e, trocando para anual, refaz o cronograma;
  - valor e juros de cada parcela digitados (os da cedula): a tabela abre com o
    calculo, a soma das amortizacoes tem que fechar com o principal, grava como
    digitado e editar depois nao troca pelo calculo;
  - Excluir apaga o contrato e as parcelas (pedido do mesmo dia: "botao de
    exclusao para eu poder apagar o contrato caso lance errado");
  - contrato que ja existia, lancado so pelo saldo (continuacao): nao entra
    como emprestimo recebido no fluxo de caixa.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}


def parc(i, fid, n, venc, amort, juros, saldo):
    return {"id": i, "financiamento_id": fid, "numero": n, "data_vencimento": venc, "valor_parcela": amort + juros,
            "valor_amortizacao": amort, "valor_juros": juros, "saldo_devedor_apos": saldo, "status": "pendente",
            "data_pagamento": None, "valor_pago": None, "lancamentos_financeiro_ids": []}


# contrato como o do print: 560.000, Price, 7 parcelas MENSAIS a partir de 15/12/2023
MENSAL = {"id": 7, "banco": "Banco Anual", "finalidade": "investimento", "valor_principal": 560000,
          "valor_iof": 0, "valor_seguro": 0, "data_contratacao": "2023-11-15", "taxa_juros_aa": 9,
          "sistema_amortizacao": "price", "numero_parcelas": 7, "carencia_meses": 0, "atividade": "graos",
          "fazenda_id": None, "garantia": None, "status": "ativo", "financiamento_origem_id": None, "observacao": None}

DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [
        {"id": 1, "fazenda_id": None, "nome": "Juros e Encargos de Financiamento", "ativo": True,
         "tipo": "saida", "subcategoria": "FINANCIAMENTOS | DESPESAS FINANCEIRAS"},
    ],
    "lancamentos_financeiros": [],
    "financiamentos": [MENSAL],
    # trocadas pelo cronograma que o app gerou (Price mensal) logo depois de abrir
    "parcelas_financiamento": [],
    "profiles": [ADMIN],
}

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def perto(a, b, tol=0.01):
    return abs(a - b) <= tol


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.accept())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};"
    )
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    # o contrato do print foi gerado pelo app: parcelas mensais de 15/12/2023 a 15/06/2024
    page.evaluate("""async () => {
      const f = {valorPrincipal:560000, taxaJurosAa:9, sistemaAmortizacao:'price', numeroParcelas:7, carenciaMeses:0, dataContratacao:'2023-11-15'};
      window.__DB__.parcelas_financiamento = gerarParcelasFinanciamento(f).map((p,i)=>({...parcelaToRow(p, 7), id:70+i,
        data_pagamento:null, valor_pago:null, lancamentos_financeiro_ids:[]}));
      await loadAll();
    }""")
    page.wait_for_timeout(300)

    print("\n  FINANCIAMENTOS: PERIODICIDADE E 1o VENCIMENTO")
    conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- formula, direto ----
    sac = page.evaluate("""() => gerarParcelasFinanciamento({valorPrincipal:560000, taxaJurosAa:9, sistemaAmortizacao:'sac',
        numeroParcelas:7, periodicidadeMeses:12, dataContratacao:'2023-11-15', primeiroVencimento:'2024-11-15'})""")
    conf([p["dataVencimento"] for p in sac] == [f"{a}-11-15" for a in range(2024, 2031)],
         "SAC anual: 7 vencimentos em 15/11, de 2024 a 2030", str([p["dataVencimento"] for p in sac]))
    conf(all(perto(p["valorAmortizacao"], 80000) for p in sac), "SAC anual: amortizacao de 80.000 por ano")
    conf(perto(sac[0]["valorJuros"], 50400) and perto(sac[1]["valorJuros"], 43200) and perto(sac[6]["valorJuros"], 7200),
         "SAC anual: juros 50.400, 43.200 ... 7.200 (9% do saldo de cada ano)", str([round(p["valorJuros"], 2) for p in sac]))
    conf(perto(sac[-1]["saldoDevedorApos"], 0), "SAC anual: ultima parcela zera o saldo")

    longe = page.evaluate("""() => gerarParcelasFinanciamento({valorPrincipal:100000, taxaJurosAa:9, sistemaAmortizacao:'sac',
        numeroParcelas:4, periodicidadeMeses:12, dataContratacao:'2024-03-15', primeiroVencimento:'2025-11-15'})""")
    esperado1 = 100000 * (1.09 ** (20 / 12) - 1)
    conf(perto(longe[0]["valorJuros"], esperado1),
         f"1o vencimento 20 meses depois: juros da 1a = R$ {esperado1:.2f} (prazo real)", str(longe[0]["valorJuros"]))
    conf(perto(longe[1]["valorJuros"], 75000 * 0.09), "a 2a parcela volta ao periodo normal (9% de 75.000)", str(longe[1]["valorJuros"]))

    price = page.evaluate("""() => gerarParcelasFinanciamento({valorPrincipal:560000, taxaJurosAa:9, sistemaAmortizacao:'price',
        numeroParcelas:7, periodicidadeMeses:12, dataContratacao:'2023-11-15', primeiroVencimento:'2024-11-15'})""")
    prest = 560000 * 0.09 / (1 - 1.09 ** -7)
    conf(all(perto(p["valorParcela"], prest, 0.02) for p in price),
         f"Price anual: 7 parcelas iguais de R$ {prest:.2f}", str([round(p["valorParcela"], 2) for p in price]))
    conf(perto(price[-1]["saldoDevedorApos"], 0), "Price anual: ultima parcela zera o saldo")

    semi = page.evaluate("""() => gerarParcelasFinanciamento({valorPrincipal:60000, taxaJurosAa:10, sistemaAmortizacao:'sac',
        numeroParcelas:4, periodicidadeMeses:6, dataContratacao:'2026-01-10', primeiroVencimento:'2026-07-10'})""")
    conf([p["dataVencimento"] for p in semi] == ["2026-07-10", "2027-01-10", "2027-07-10", "2028-01-10"],
         "semestral: vence a cada 6 meses", str([p["dataVencimento"] for p in semi]))

    antigo = page.evaluate("""() => gerarParcelasFinanciamento({valorPrincipal:12000, taxaJurosAa:12, sistemaAmortizacao:'sac',
        numeroParcelas:3, carenciaMeses:0, dataContratacao:'2026-01-15'})""")
    tm = 1.12 ** (1 / 12) - 1
    conf([p["dataVencimento"] for p in antigo] == ["2026-02-15", "2026-03-15", "2026-04-15"]
         and perto(antigo[0]["valorJuros"], 12000 * tm),
         "contrato antigo (sem 1o vencimento): mensal e juros iguais a antes", str(antigo))

    unica = page.evaluate("""() => gerarParcelasFinanciamento({valorPrincipal:100000, taxaJurosAa:8, sistemaAmortizacao:'parcela_unica',
        dataContratacao:'2026-01-15', primeiroVencimento:'2027-07-15'})""")
    conf(len(unica) == 1 and unica[0]["dataVencimento"] == "2027-07-15" and perto(unica[0]["valorJuros"], 100000 * (1.08 ** 1.5 - 1)),
         "parcela unica: vence na data informada, juros de 18 meses", str(unica))

    # ---- tela: novo contrato ----
    page.evaluate("() => { state.page='financiamentos'; render(); }")
    page.wait_for_timeout(300)
    page.locator('[data-novo-financiamento]').click()
    page.wait_for_timeout(300)
    conf(page.eval_on_selector('#f-sistemafin', 'e=>e.value') == 'sac', "novo contrato abre em SAC (numero de parcelas aparece)")
    conf(page.eval_on_selector('#f-periodicidadefin', 'e=>e.value') == '12', "novo contrato abre com pagamento Anual")
    page.fill('#f-bancofin', 'Banco Novo')
    page.select_option('#f-atividadefin', 'cana')
    page.fill('#f-principalfin', '560000')
    page.fill('#f-datafin', '2023-11-15')
    page.fill('#f-taxafin', '9')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(300)
    erro = page.evaluate("() => state.erroFinanciamento")
    conf("número de parcelas" in erro and "1º vencimento" in erro, "sem parcelas e sem 1o vencimento nao salva", erro)

    page.fill('#f-numparcelasfin', '7')
    page.fill('#f-vencfin', '2023-10-15')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(300)
    erro = page.evaluate("() => state.erroFinanciamento")
    conf("depois da data de contratação" in erro, "vencimento antes da contratacao nao salva", erro)

    page.fill('#f-vencfin', '2024-11-15')
    page.dispatch_event('#f-vencfin', 'change')
    resumo = page.inner_text('#resumo-cronogramafin')
    conf(resumo == "7 parcelas anuais, de 15/11/2024 a 15/11/2030.", "resumo do cronograma na tela", resumo)
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)
    row = page.evaluate("() => window.__DB__.financiamentos.find(f=>f.banco==='Banco Novo')")
    conf(row and row["periodicidade_meses"] == 12 and row["primeiro_vencimento"] == "2024-11-15",
         "grava periodicidade 12 e o 1o vencimento", str(row))
    conf(row and row["carencia_meses"] == 0, "carencia gravada = 0 (1o vencimento um ano depois)", str(row and row["carencia_meses"]))
    novas = page.evaluate("""() => window.__DB__.parcelas_financiamento.filter(p=>p.financiamento_id===%d)
        .map(p=>p.data_vencimento)""" % (row["id"] if row else -1))
    conf(novas == [f"{a}-11-15" for a in range(2024, 2031)], "salvo com 7 parcelas anuais", str(novas))

    # ---- editar o contrato mensal (o do print) ----
    page.evaluate("() => { state.financiamentoDetalheId = 7; render(); }")
    page.wait_for_timeout(300)
    conf("parcelas mensais" in page.inner_text("body"), "detalhe do contrato diz que as parcelas sao mensais")
    page.evaluate("() => { state.financiamentoDetalheId = null; render(); }")
    page.wait_for_timeout(300)
    page.locator('[data-editar-financiamento="7"]').click()
    page.wait_for_timeout(300)
    conf(page.eval_on_selector('#f-vencfin', 'e=>e.value') == '2023-12-15', "editar traz o 1o vencimento da 1a parcela")
    conf(page.eval_on_selector('#f-periodicidadefin', 'e=>e.value') == '1', "editar traz o pagamento Mensal que esta gravado")
    page.select_option('#f-periodicidadefin', '12')
    page.fill('#f-vencfin', '2024-11-15')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)
    refeitas = page.evaluate("""() => window.__DB__.parcelas_financiamento.filter(p=>p.financiamento_id===7)
        .sort((a,b)=>a.numero-b.numero).map(p=>[p.data_vencimento, p.valor_parcela])""")
    conf([r[0] for r in refeitas] == [f"{a}-11-15" for a in range(2024, 2031)],
         "trocar para Anual refaz as 7 parcelas, uma por ano", str(refeitas))
    conf(refeitas and all(perto(r[1], prest, 0.02) for r in refeitas), "Price anual de R$ %.2f por ano" % prest, str(refeitas))
    page.evaluate("() => { state.financiamentoDetalheId = 7; render(); }")
    page.wait_for_timeout(300)
    conf("parcelas anuais" in page.inner_text("body"), "detalhe passa a dizer parcelas anuais")

    # ---- valor e juros de cada parcela digitados (os da cedula) ----
    page.evaluate("() => { state.financiamentoDetalheId = null; state.page='financiamentos'; render(); }")
    page.wait_for_timeout(300)
    page.locator('[data-novo-financiamento]').click()
    page.wait_for_timeout(300)
    page.fill('#f-bancofin', 'Banco Cedula')
    page.select_option('#f-atividadefin', 'graos')
    page.fill('#f-principalfin', '300000')
    page.fill('#f-datafin', '2025-06-10')
    page.fill('#f-taxafin', '8')
    page.fill('#f-numparcelasfin', '3')
    page.fill('#f-vencfin', '2026-06-10')
    page.locator('[data-parcelas-manuais]').click()
    page.wait_for_timeout(300)
    conf(page.locator('[data-pm-valor]').count() == 3, "botao abre a tabela com 3 parcelas para digitar")
    conf(page.eval_on_selector('[data-pm-venc="2"]', 'e=>e.value') == '2028-06-10', "tabela ja vem com os vencimentos anuais")
    cedula = [("2026-06-10", "124000", "24000"), ("2027-06-10", "116500", "16500"), ("2028-06-10", "109300", "9300")]
    for i, (v, val, j) in enumerate(cedula):
        page.fill(f'[data-pm-venc="{i}"]', v)
        page.fill(f'[data-pm-valor="{i}"]', val)
        page.fill(f'[data-pm-juros="{i}"]', j)
    page.fill('[data-pm-valor="2"]', '109000')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(300)
    erro = page.evaluate("() => state.erroFinanciamento")
    conf("soma das amortizações" in erro, "amortizacao que nao fecha com o principal nao salva", erro)
    conf(page.eval_on_selector('[data-pm-juros="1"]', 'e=>e.value') == '16500', "o que foi digitado continua na tabela depois do erro")
    page.fill('[data-pm-valor="2"]', '109300')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)
    fid = page.evaluate("() => window.__DB__.financiamentos.find(f=>f.banco==='Banco Cedula')?.id")
    ced = page.evaluate("""(fid) => window.__DB__.parcelas_financiamento.filter(p=>p.financiamento_id===fid)
        .sort((a,b)=>a.numero-b.numero).map(p=>[p.data_vencimento, p.valor_parcela, p.valor_juros, p.valor_amortizacao, p.saldo_devedor_apos])""", fid)
    conf(ced == [["2026-06-10", 124000, 24000, 100000, 200000], ["2027-06-10", 116500, 16500, 100000, 100000],
                 ["2028-06-10", 109300, 9300, 100000, 0]],
         "grava parcela, juros, amortizacao e saldo como digitados", str(ced))
    page.locator(f'[data-editar-financiamento="{fid}"]').click()
    page.wait_for_timeout(300)
    conf(page.eval_on_selector('[data-pm-juros="0"]', 'e=>e.value') == '24000',
         "editar contrato com valores digitados abre a tabela com eles (nao troca pelo calculo)")
    page.locator('[data-close="1"]').first.click()
    page.wait_for_timeout(200)

    # ---- excluir contrato lancado errado ----
    page.evaluate(f"() => {{ state.financiamentoDetalheId = {fid}; render(); }}")
    page.wait_for_timeout(300)
    page.locator(f'[data-excluir-financiamento="{fid}"]').click()
    page.wait_for_timeout(500)
    sobrou = page.evaluate("""(fid) => [window.__DB__.financiamentos.some(f=>f.id===fid),
        window.__DB__.parcelas_financiamento.filter(p=>p.financiamento_id===fid).length]""", fid)
    conf(sobrou == [False, 0], "Excluir apaga o contrato e as parcelas", str(sobrou))
    conf(page.evaluate("() => state.financiamentoDetalheId") is None, "depois de excluir volta para a lista")


    # ---- contrato que ja existia, lancado so pelo saldo ----
    page.evaluate("() => { state.financiamentoDetalheId = null; state.page='financiamentos'; render(); }")
    page.wait_for_timeout(300)
    page.locator('[data-novo-financiamento]').click()
    page.wait_for_timeout(300)
    page.fill('#f-bancofin', 'Banco Saldo')
    page.check('#f-continuacaofin')
    page.select_option('#f-atividadefin', 'pecuaria')
    page.fill('#f-principalfin', '200000')
    page.fill('#f-datafin', '2025-11-15')
    page.fill('#f-taxafin', '10')
    page.fill('#f-numparcelasfin', '2')
    page.fill('#f-vencfin', '2026-11-15')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)
    row = page.evaluate("() => window.__DB__.financiamentos.find(f=>f.banco==='Banco Saldo')")
    conf(row and row.get("continuacao") is True, "grava continuacao = true", str(row))
    fluxo = page.evaluate("""() => {
      const f = state.financiamentos.find(x=>x.banco==='Banco Saldo');
      const com = calcularFluxoEmpresa({tipo:'ano', ano:2025}).financiamento.emprestimosRecebidos;
      f.continuacao = false;
      const sem = calcularFluxoEmpresa({tipo:'ano', ano:2025}).financiamento.emprestimosRecebidos;
      f.continuacao = true;
      return [com, sem];
    }""")
    conf(fluxo == [0, 200000], "contrato que ja existia nao entra como emprestimo recebido (sem a marca entraria 200.000)", str(fluxo))
    sid = row["id"] if row else -1
    page.evaluate(f"() => {{ state.financiamentoDetalheId = {sid}; render(); }}")
    page.wait_for_timeout(300)
    conf("contrato que já existia" in page.inner_text("body"), "detalhe mostra que e contrato que ja existia")
    page.evaluate("() => { state.financiamentoDetalheId = null; render(); }")
    page.wait_for_timeout(200)
    page.locator(f'[data-editar-financiamento="{sid}"]').click()
    page.wait_for_timeout(300)
    conf(page.is_checked('#f-continuacaofin'), "editar traz a caixa marcada")
    page.locator('[data-close="1"]').first.click()

    conf(not erros, "nenhum erro de JavaScript no caminho todo", " | ".join(erros[:3]))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
