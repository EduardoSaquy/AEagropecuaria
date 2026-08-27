"""
Teste do modulo de Financiamentos (AEMatriz.html), lancado em 26/08/2026.

Cobre o caminho de ponta a ponta contra o app de verdade, clicando nos
botoes reais (nao so chamando funcao por funcao):

  - Custeio com atividade unica, sistema "parcela unica": cria o
    financiamento, confere a parcela gerada, marca como paga e confere
    que SO O JUROS virou um lancamento_financeiro -- a amortizacao nunca
    pode aparecer la (e a razao de toda a separacao de tabelas existir).
  - Capital de giro: a mesma parcela paga tem que virar TRES lancamentos
    iguais (Pecuaria/Cana/Graos), nao um so.
  - SAC e Price: confere a formula em si (juros decrescente, ultima
    parcela zera o saldo), sem depender da tela.

Precisou upar o stub (teste_stub_supabase.js) pra insert/update/delete
gravarem de verdade em window.__DB__ -- antes so registravam a intencao.
Os outros tres arquivos de teste nunca clicavam em "Salvar", entao essa
mudanca nao mexeu com eles (conferido rodando os tres depois).
"""
import sys
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

CENTRO_JUROS_ID = 500
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}

DB = {
    "fazendas": [],
    "fazenda_atividades": [
        {"id": 1, "fazenda_id": None, "atividade": "pecuaria", "area_ha": 300},
        {"id": 2, "fazenda_id": None, "atividade": "cana", "area_ha": 200},
        {"id": 3, "fazenda_id": None, "atividade": "graos", "area_ha": 500},
    ],
    "centros_custo": [
        {"id": CENTRO_JUROS_ID, "fazenda_id": None, "nome": "Juros e Encargos de Financiamento",
         "tipo": "saida", "subcategoria": "FINANCIAMENTOS | DESPESAS FINANCEIRAS", "ativo": True},
    ],
    "lancamentos_financeiros": [],
    "financiamentos": [],
    "parcelas_financiamento": [],
    "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [],
    "lotes": [], "profiles": [ADMIN],
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


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    page.on("dialog", lambda d: d.accept())  # confirm() de "marcar como paga"
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: erros.append(m.text) if m.type == "error" else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};"
    )
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    print("\n  FINANCIAMENTOS")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource", "ERR_CONNECTION_RESET")
    reais = [e for e in erros if not any(r in e for r in ruido)]
    conf(not reais, "abre sem erro de JavaScript", " | ".join(reais[:3]))

    # ---- formula SAC/Price/parcela unica, direto (sem UI) ----
    calc_pu = page.evaluate(
        "() => gerarParcelasFinanciamento({valorPrincipal:100000, taxaJurosAa:8, "
        "carenciaMeses:12, sistemaAmortizacao:'parcela_unica', dataContratacao:'2026-01-15'})"
    )
    conf(len(calc_pu) == 1, "parcela única gera 1 parcela só", str(calc_pu))
    if calc_pu:
        conf(abs(calc_pu[0]["valorJuros"] - 8000) < 0.5,
             "parcela única: 100.000 a 8% a.a. por 12 meses = R$ 8.000 de juros",
             f'veio {calc_pu[0]["valorJuros"]}')
        conf(abs(calc_pu[0]["saldoDevedorApos"]) < 0.01, "parcela única zera o saldo devedor")

    calc_sac = page.evaluate(
        "() => gerarParcelasFinanciamento({valorPrincipal:12000, taxaJurosAa:12, "
        "carenciaMeses:0, numeroParcelas:12, sistemaAmortizacao:'sac', dataContratacao:'2026-01-15'})"
    )
    conf(len(calc_sac) == 12, "SAC gera o número de parcelas pedido", str(len(calc_sac)))
    amorts = [round(p["valorAmortizacao"], 2) for p in calc_sac]
    conf(len(set(amorts)) == 1, "SAC: amortização constante em todas as parcelas", str(amorts))
    juros_sac = [p["valorJuros"] for p in calc_sac]
    conf(juros_sac[0] > juros_sac[-1], "SAC: juros decrescente (mais no início, menos no fim)", str(juros_sac))
    conf(abs(calc_sac[-1]["saldoDevedorApos"]) < 0.01, "SAC: última parcela zera o saldo devedor")

    calc_price = page.evaluate(
        "() => gerarParcelasFinanciamento({valorPrincipal:12000, taxaJurosAa:12, "
        "carenciaMeses:0, numeroParcelas:12, sistemaAmortizacao:'price', dataContratacao:'2026-01-15'})"
    )
    valores_price = [round(p["valorParcela"], 2) for p in calc_price[:-1]]  # última pode arredondar diferente
    conf(len(set(valores_price)) == 1, "Price: parcela de valor fixo (menos a última)", str(valores_price))
    conf(abs(calc_price[-1]["saldoDevedorApos"]) < 0.01, "Price: última parcela zera o saldo devedor")

    # ---- fluxo real: custeio, atividade única, clicando nos botões ----
    page.evaluate("() => { state.page='financiamentos'; render(); }")
    page.wait_for_timeout(300)
    corpo = page.locator("body").inner_text()
    conf("Financiamentos" in corpo, "aba Financiamentos abre")

    page.locator('[data-novo-financiamento]').click()
    page.wait_for_timeout(300)
    page.fill('#f-bancofin', 'Banco Teste')
    page.select_option('#f-finalidadefin', 'custeio')
    page.wait_for_timeout(200)
    page.select_option('#f-atividadefin', 'pecuaria')
    page.fill('#f-principalfin', '100000')
    page.fill('#f-datafin', '2026-01-15')
    page.fill('#f-taxafin', '8')
    page.fill('#f-carenciafin', '12')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)

    fins = page.evaluate("() => state.financiamentos.map(f=>({banco:f.banco, finalidade:f.finalidade, atividade:f.atividade, status:f.status}))")
    conf(len(fins) == 1, "financiamento de custeio foi criado", str(fins))
    conf(fins and fins[0]["atividade"] == "pecuaria", "atividade gravada certa", str(fins))

    corpo = page.locator("body").inner_text()
    conf("Banco Teste" in corpo, "financiamento aparece na lista")
    conf("100.000,00" in corpo or "100.000,0" in corpo, "valor contratado aparece na lista", corpo[:200])

    parcelas = page.evaluate("() => state.parcelasFinanciamento.map(p=>({juros:p.valorJuros, amort:p.valorAmortizacao, status:p.status}))")
    conf(len(parcelas) == 1, "1 parcela gerada pro financiamento de custeio", str(parcelas))
    conf(parcelas and abs(parcelas[0]["juros"] - 8000) < 0.5, "juros da parcela bate com o cálculo direto", str(parcelas))

    # ---- marcar como paga: só o juros vira lançamento ----
    financiamento_id = page.evaluate("() => state.financiamentos[0].id")
    page.evaluate(f"() => {{ state.financiamentoDetalheId = {financiamento_id}; render(); }}")
    page.wait_for_timeout(300)
    page.locator('[data-pagar-parcela]').click()
    page.wait_for_timeout(500)

    lancs = page.evaluate("() => state.lancamentos.map(l=>({tipo:l.tipo, atividade:l.atividade, valor:l.valor, centroCustoId:l.centroCustoId}))")
    conf(len(lancs) == 1, "marcar como paga gera exatamente 1 lançamento (não 2, não 0)", str(lancs))
    if lancs:
        l = lancs[0]
        conf(l["tipo"] == "despesa", "o lançamento é despesa")
        conf(abs(l["valor"] - 8000) < 0.5, "o lançamento vale só o JUROS (R$ 8.000), não a parcela inteira (R$ 108.000)", str(l))
        conf(l["centroCustoId"] == CENTRO_JUROS_ID, "cai no centro 'Juros e Encargos de Financiamento'", str(l))
        conf(l["atividade"] == "pecuaria", "atividade do lançamento é a do financiamento")

    parc_depois = page.evaluate("() => state.parcelasFinanciamento[0].status")
    conf(parc_depois == "paga", "parcela vira 'paga'", parc_depois)
    fin_depois = page.evaluate("() => state.financiamentos[0].status")
    conf(fin_depois == "quitado", "última parcela paga quita o financiamento sozinho", fin_depois)

    # ---- capital de giro: 3 lançamentos iguais ----
    page.evaluate("() => { state.financiamentoDetalheId = null; state.page='financiamentos'; render(); }")
    page.wait_for_timeout(300)
    page.locator('[data-novo-financiamento]').click()
    page.wait_for_timeout(300)
    page.fill('#f-bancofin', 'Banco Giro')
    page.select_option('#f-finalidadefin', 'capital_giro')
    page.wait_for_timeout(200)
    page.fill('#f-principalfin', '30000')
    page.fill('#f-datafin', '2026-01-15')
    page.fill('#f-taxafin', '12')
    page.fill('#f-carenciafin', '12')
    page.locator('[data-save="financiamento"]').click()
    page.wait_for_timeout(500)

    fin2_id = page.evaluate("() => state.financiamentos.find(f=>f.banco==='Banco Giro').id")
    conf(fin2_id is not None, "financiamento de capital de giro foi criado")

    # ---- card de resumo ANTES de pagar (o de custeio já quitou; só o de
    # giro está ativo agora, então é ele que deve aparecer sozinho) ----
    resumo_antes = page.evaluate("() => resumoFinanciamentos()")
    conf(abs(resumo_antes["totalContratado"] - 30000) < 0.5,
         "resumo: total contratado só conta o financiamento ATIVO (custeio já quitado, giro ainda não)",
         str(resumo_antes))
    conf(abs(resumo_antes["saldoDevedor"] - 30000) < 0.5,
         "resumo: saldo devedor mostra o valor cheio antes de pagar", str(resumo_antes))

    page.evaluate(f"() => {{ state.financiamentoDetalheId = {fin2_id}; render(); }}")
    page.wait_for_timeout(300)
    page.locator('[data-pagar-parcela]').click()
    page.wait_for_timeout(500)

    lancs_giro = page.evaluate(
        "() => state.lancamentos.filter(l=>l.descricao && l.descricao.includes('Banco Giro'))"
        ".map(l=>({atividade:l.atividade, valor:l.valor}))"
    )
    conf(len(lancs_giro) == 3, "capital de giro gera 3 lançamentos (1 por atividade)", str(lancs_giro))
    atividades_giro = sorted(l["atividade"] for l in lancs_giro)
    conf(atividades_giro == ["cana", "graos", "pecuaria"], "as 3 atividades são Pecuária/Cana/Grãos", str(atividades_giro))
    valores_giro = [round(l["valor"], 2) for l in lancs_giro]
    conf(all(abs(v - 1200) < 0.5 for v in valores_giro),
         "cada lançamento vale 1/3 do juros (R$ 3.600 / 3 = R$ 1.200)", str(valores_giro))

    # ---- card de resumo DEPOIS de pagar os dois: os dois financiamentos
    # já quitaram, então nada mais entra na soma (nem por engano soma
    # dívida que já foi paga) ----
    page.evaluate("() => { state.financiamentoDetalheId = null; render(); }")
    page.wait_for_timeout(300)
    resumo_depois = page.evaluate("() => resumoFinanciamentos()")
    conf(abs(resumo_depois["totalContratado"]) < 0.5,
         "resumo: total contratado zera depois dos dois financiamentos quitados", str(resumo_depois))
    conf(abs(resumo_depois["saldoDevedor"]) < 0.5,
         "resumo: saldo devedor zerado depois de pagar tudo", str(resumo_depois))
    conf(abs(resumo_depois["jurosPagoAno"] - 11600) < 1,
         "resumo: juros pago no ano soma o juros das duas parcelas pagas (8.000 + 3.600)", str(resumo_depois))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
