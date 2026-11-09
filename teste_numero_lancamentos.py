"""
Numero (id) de cada lancamento, conta e contrato no AE Matriz (pedido do Eduardo e das secretarias, 09/11/2026:
"identificacao em todos os lancamentos, um numero de ID, para contas a pagar, a receber, financiamentos...").

Prova, com o app de verdade e o Supabase simulado:
  - Financeiro (despesas, receitas e investimentos): "N 1234" embaixo da data de cada linha, inclusive recorrente;
    a busca aparece nas tres abas e acha pelo numero ("#1234", "n 1234", "1234"); "#..." acha so o numero, os
    algarismos sozinhos acham o numero e tambem o texto; trocar de aba nao deixa busca escondida filtrando;
  - a linha diz de onde veio o lancamento que o sistema criou: "veio da baixa da conta N ..." e "juros do contrato N ...";
  - a janela de editar lancamento mostra o numero; a de lancamento novo nao (o banco ainda nao deu);
  - Pagar/Receber: numero embaixo do vencimento, busca pelo numero, janela de editar, de baixar, de baixar em lote e
    a lista de baixas com o numero da conta;
  - Financiamentos: numero na lista e na tela do contrato, busca pelo numero, janelas de editar contrato, registrar
    pagamento, editar parcela e quitar dizem o numero do contrato; renegociacao cita "N" (era "#");
  - nada rola de lado em 1280 e 390 px; nenhum erro de JavaScript.
Falha no codigo anterior (nao havia numero nenhum na tela).
"""
import json
import datetime
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
HOJE = datetime.date.today()
D = lambda n: (HOJE + datetime.timedelta(days=n)).isoformat()
MES = HOJE.isoformat()[:7]


def lanc(i, tipo, desc, valor, data, **kw):
    l = {"id": i, "tipo": tipo, "atividade": "graos", "fazenda_id": None, "centro_custo_id": 90, "descricao": desc,
         "valor": valor, "data": data, "mes": data[:7] if data else None, "fornecedor": kw.pop("fornecedor", ""),
         "observacao": "", "areas": [], "titulo_baixa_id": kw.pop("titulo_baixa_id", None)}
    l.update(kw)
    return l


def tit(i, tipo, ent, desc, valor, venc, **kw):
    t = {"id": i, "tipo": tipo, "entidade_id": ent, "descricao": desc, "valor": valor, "vencimento": venc,
         "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False, "valor_baixado": 0, "situacao": "aberto",
         "conta_bancaria_id": None}
    t.update(kw)
    return t


DB = {
    "fazendas": [{"id": 4, "nome": "Faz. Invernada", "estado": "TO", "area_ha": 1694, "ativo": True}],
    "fazenda_atividades": [], "lotes": [], "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [],
    "culturas": [], "movimentos_financiamento": [],
    "centros_custo": [{"id": 90, "fazenda_id": None, "nome": "PECAS E MANUTENCAO", "frente": None, "ativo": True,
                       "tipo": "saida", "subcategoria": "OPERACIONAL | MANUTENCAO"},
                      {"id": 92, "fazenda_id": None, "nome": "Juros e Encargos de Financiamento", "frente": None,
                       "ativo": True, "tipo": "saida", "subcategoria": "FINANCIAMENTOS | DESPESAS FINANCEIRAS"},
                      {"id": 95, "fazenda_id": None, "nome": "VENDA DE GRAOS", "frente": None, "ativo": True,
                       "tipo": "entrada", "subcategoria": "OPERACIONAL | RECEITAS"}],
    "entidades": [{"id": 5, "nome": "BERTINI", "documento": "", "papel": "fornecedor", "ativo": True},
                  {"id": 6, "nome": "COOPERATIVA", "documento": "", "papel": "cliente", "ativo": True}],
    "contas_bancarias": [],
    "lancamentos_financeiros": [
        lanc(24801, "despesa", "Pecas plantadeira", 8140.00, D(-10), fornecedor="BERTINI", titulo_baixa_id=7),
        lanc(24802, "despesa", "Juros BASA (parcela 1/1)", 1234.56, D(-9), centro_custo_id=92, fornecedor="Banco X"),
        lanc(1113, "despesa", "Frete 24801 da nota", 300.00, D(-8)),          # texto com o numero de outro lancamento
        lanc(77, "despesa", "Energia (recorrente)", 500.00, None, mes=None),  # recorrente
        lanc(5001, "receita", "Venda de soja", 90000.00, D(-5), centro_custo_id=95),
        lanc(5002, "receita", "Venda de milho", 40000.00, D(-4), centro_custo_id=95),
        lanc(6001, "investimento", "Plantadeira nova", 250000.00, D(-3)),
    ],
    "titulos": [
        tit(113, "pagar", 5, "PECAS PARA A PLANTADEIRA", 8140.00, D(-10), valor_baixado=8140.00, situacao="pago"),
        tit(114, "pagar", 5, "Oleo", 500.00, D(10)),
        tit(115, "pagar", 5, "Filtro 113", 90.00, D(12)),                     # texto com "113"
        tit(201, "receber", 6, "Venda de soja", 1000.00, D(15)),
    ],
    "titulo_rateios": [{"id": i, "titulo_id": t, "fazenda_id": 4, "atividade": "graos", "centro_custo_id": 90,
                        "competencia": MES, "valor": v}
                       for i, (t, v) in enumerate([(113, 8140.0), (114, 500.0), (115, 90.0), (201, 1000.0)], 1)],
    "titulo_baixas": [{"id": 7, "titulo_id": 113, "data": D(-10), "valor": 8140.00, "conta_bancaria_id": None}],
    "financiamentos": [
        {"id": 4, "banco": "Banco X", "finalidade": "custeio", "valor_principal": 100000, "valor_iof": 0, "valor_seguro": 0,
         "data_contratacao": D(-300), "taxa_juros_aa": 9.3, "sistema_amortizacao": "parcela_unica", "numero_parcelas": 1,
         "carencia_meses": 10, "periodicidade_meses": 12, "primeiro_vencimento": D(-9), "continuacao": False,
         "atividade": "graos", "fazenda_id": 4, "garantia": None, "status": "quitado", "financiamento_origem_id": None,
         "observacao": None},
        {"id": 7, "banco": "Banco Y", "finalidade": "investimento", "valor_principal": 60000, "valor_iof": 0, "valor_seguro": 0,
         "data_contratacao": D(-30), "taxa_juros_aa": 8.8, "sistema_amortizacao": "sac", "numero_parcelas": 2,
         "carencia_meses": 0, "periodicidade_meses": 12, "primeiro_vencimento": D(335), "continuacao": False,
         "atividade": "graos", "fazenda_id": None, "garantia": None, "status": "ativo", "financiamento_origem_id": 4,
         "observacao": None},
    ],
    "parcelas_financiamento": [
        {"id": 31, "financiamento_id": 4, "numero": 1, "data_vencimento": D(-9), "valor_parcela": 101234.56,
         "valor_amortizacao": 100000, "valor_juros": 1234.56, "saldo_devedor_apos": 0, "status": "paga",
         "data_pagamento": D(-9), "valor_pago": 101234.56, "lancamentos_financeiro_ids": [24802]},
        {"id": 41, "financiamento_id": 7, "numero": 1, "data_vencimento": D(335), "valor_parcela": 35000,
         "valor_amortizacao": 30000, "valor_juros": 5000, "saldo_devedor_apos": 30000, "status": "pendente",
         "data_pagamento": None, "valor_pago": None, "lancamentos_financeiro_ids": []},
        {"id": 42, "financiamento_id": 7, "numero": 2, "data_vencimento": D(700), "valor_parcela": 32500,
         "valor_amortizacao": 30000, "valor_juros": 2500, "saldo_devedor_apos": 0, "status": "pendente",
         "data_pagamento": None, "valor_pago": None, "lancamentos_financeiro_ids": []},
    ],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

passes = falhas = 0


def conf(ok, nome, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {nome}")
    else:
        falhas += 1
        print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lancamentos && state.lancamentos.length === 7"
                           " && state.titulos && state.titulos.length === 4 && state.financiamentos.length === 2", timeout=20000)
    ev = page.evaluate

    def financeiro(aba, busca=""):
        ev("(a) => { state.modal=null; editDraft=null; state.page='financeiro'; state.abaFinanceiro=a.aba; state.filtroAtividade='';"
           " state.filtroMesDespesas=''; state.searchDespesas=a.busca; state.limiteListaFinanceiro=100; render(); }",
           {"aba": aba, "busca": busca})
        page.wait_for_timeout(150)

    def numeros_na_tela():
        return ev("() => [...document.querySelectorAll('#root table [data-num-id]')].map(e => e.dataset.numId)")

    def rola_de_lado():
        return ev("() => document.documentElement.scrollWidth > document.documentElement.clientWidth + 1")

    print("\n  NUMERO DE CADA LANCAMENTO, CONTA E CONTRATO")
    print("\n  -- Financeiro --")
    financeiro("despesa")
    nums = numeros_na_tela()
    conf(sorted(nums) == sorted(["24801", "24802", "1113", "77"]), "cada despesa tem o numero na linha (inclusive a recorrente)", str(nums))
    txt = ev("() => document.querySelector('[data-num-id=\"77\"]').closest('td').innerText")
    conf("Recorrente" in txt and "Nº 77" in txt, "o numero fica embaixo da data (ou de 'Recorrente')", txt)
    linha_baixa = ev("() => document.querySelector('[data-num-id=\"24801\"]').closest('tr').innerText")
    conf("veio da baixa da conta Nº 113" in linha_baixa, "lancamento criado pela baixa diz de qual conta veio", linha_baixa)
    linha_juros = ev("() => document.querySelector('[data-num-id=\"24802\"]').closest('tr').innerText")
    conf("juros do contrato Nº 4" in linha_juros, "juros de parcela diz de qual contrato veio", linha_juros)
    conf(ev("() => document.querySelectorAll('[data-origem-lancamento]').length") == 2, "so os dois que o sistema criou dizem a origem")

    financeiro("despesa", "#24801")
    conf(numeros_na_tela() == ["24801"], "busca '#24801' acha so o lancamento 24801 (nao o frete que cita 24801)", str(numeros_na_tela()))
    financeiro("despesa", "nº 24801")
    conf(numeros_na_tela() == ["24801"], "busca 'nº 24801' tambem", str(numeros_na_tela()))
    financeiro("despesa", "24801")
    conf(sorted(numeros_na_tela()) == ["1113", "24801"], "so os algarismos acham o numero e o texto com 24801", str(numeros_na_tela()))
    financeiro("despesa", "#999999")
    conf(numeros_na_tela() == [], "numero que nao existe nao acha nada")
    financeiro("despesa", "plantadeira")
    conf(numeros_na_tela() == ["24801"], "busca por texto continua como antes", str(numeros_na_tela()))

    for aba, esperados in (("receita", ["5001", "5002"]), ("investimento", ["6001"])):
        financeiro(aba)
        conf(page.locator("[data-search-despesas]").count() == 1, f"a busca aparece em {aba}")
        conf(sorted(numeros_na_tela()) == esperados, f"{aba}: numero em cada linha", str(numeros_na_tela()))
    financeiro("receita", "#5002")
    conf(numeros_na_tela() == ["5002"], "busca pelo numero em receitas", str(numeros_na_tela()))
    conf(page.locator("[data-search-despesas]").input_value() == "#5002", "a busca que filtra esta visivel na aba (nao fica escondida)")

    financeiro("despesa")
    page.click("[data-edit-lancamento='24801']")
    page.wait_for_timeout(200)
    titulo = page.inner_text(".modal-head h3")
    conf("Editar" in titulo and "Nº 24801" in titulo, "janela de editar lancamento mostra o numero", titulo)
    ev("() => { state.modal=null; editDraft=null; render(); }")
    page.click("[data-novo-lancamento]")
    page.wait_for_timeout(200)
    titulo = page.inner_text(".modal-head h3")
    conf("Nº" not in titulo, "lancamento novo nao tem numero (o banco da ao gravar)", titulo)
    ev("() => { state.modal=null; editDraft=null; render(); }")
    conf(not rola_de_lado(), "Financeiro nao rola de lado em 1280 px")

    print("\n  -- Pagar/Receber --")

    def contas(aba, filtro="todos", busca=""):
        ev("(a) => { state.modal=null; editDraft=null; state.page='contas'; state.abaContas=a.aba; state.filtroContas=a.filtro;"
           " state.searchContas=a.busca; state.contasSelecionadas=[]; render(); }", {"aba": aba, "filtro": filtro, "busca": busca})
        page.wait_for_timeout(150)

    contas("pagar")
    conf(sorted(numeros_na_tela()) == ["113", "114", "115"], "cada conta a pagar tem o numero", str(numeros_na_tela()))
    cel = ev("() => document.querySelector('[data-num-id=\"113\"]').closest('td').innerText")
    conf("Nº 113" in cel, "o numero fica junto do vencimento", cel)
    contas("pagar", busca="#113")
    conf(numeros_na_tela() == ["113"], "busca '#113' acha so a conta 113 (nao o filtro que cita 113)", str(numeros_na_tela()))
    contas("pagar", busca="113")
    conf(sorted(numeros_na_tela()) == ["113", "115"], "busca '113' acha a conta e o texto com 113", str(numeros_na_tela()))
    contas("receber")
    conf(numeros_na_tela() == ["201"], "conta a receber tem o numero", str(numeros_na_tela()))
    contas("pagar")
    page.click("[data-edit-titulo='114']")
    page.wait_for_timeout(200)
    conf("Nº 114" in page.inner_text(".modal-head h3"), "janela de editar conta mostra o numero", page.inner_text(".modal-head h3"))
    contas("pagar")
    page.click("[data-baixar-titulo='114']")
    page.wait_for_timeout(200)
    conf("Nº 114" in page.inner_text(".modal-body"), "janela de baixar mostra o numero da conta")
    contas("pagar")
    page.click("[data-ver-baixas='113']")
    page.wait_for_timeout(200)
    conf("Nº 113" in page.inner_text(".modal-head h3"), "lista de baixas mostra o numero da conta", page.inner_text(".modal-head h3"))
    contas("pagar", filtro="abertos")
    page.check("[data-selecionar-titulo='114']")
    page.check("[data-selecionar-titulo='115']")
    page.wait_for_timeout(150)
    page.click("[data-baixar-selecionados]")
    page.wait_for_timeout(200)
    corpo = page.inner_text(".modal-body")
    conf("Nº 114" in corpo and "Nº 115" in corpo, "baixa em lote lista o numero de cada conta", corpo[:300])
    contas("pagar")
    conf(not rola_de_lado(), "Pagar/Receber nao rola de lado em 1280 px")

    print("\n  -- Financiamentos --")

    def financiamentos(busca="", detalhe=None):
        ev("(a) => { state.modal=null; editDraft=null; state.page='financiamentos'; state.searchFinanciamentos=a.busca;"
           " state.financiamentoDetalheId=a.det; render(); }", {"busca": busca, "det": detalhe})
        page.wait_for_timeout(150)

    financiamentos()
    conf(sorted(numeros_na_tela()) == ["4", "7"], "cada contrato tem o numero na lista", str(numeros_na_tela()))
    financiamentos("#7")
    conf(numeros_na_tela() == ["7"], "busca pelo numero do contrato", str(numeros_na_tela()))
    financiamentos("banco x")
    conf(numeros_na_tela() == ["4"], "busca pelo banco continua", str(numeros_na_tela()))
    financiamentos(detalhe=7)
    cab = page.inner_text(".card.card-pad h3")
    conf("Nº 7" in cab, "tela do contrato mostra o numero", cab)
    corpo = page.inner_text("#root")
    conf("renegociação do financiamento Nº 4" in corpo and "financiamento #4" not in corpo, "renegociacao cita o numero com 'Nº'")
    page.click('.toolbar [data-editar-financiamento="7"]')
    page.wait_for_timeout(200)
    conf("Nº 7" in page.inner_text(".modal-head h3"), "janela de editar contrato mostra o numero", page.inner_text(".modal-head h3"))
    financiamentos(detalhe=7)
    page.click('[data-pagamento-parcela="41"]')
    page.wait_for_timeout(200)
    t = page.inner_text(".modal-head h3")
    conf("parcela 1" in t and "Nº 7" in t, "registrar pagamento diz a parcela e o numero do contrato", t)
    financiamentos(detalhe=7)
    page.click('[data-editar-parcela="42"]')
    page.wait_for_timeout(200)
    t = page.inner_text(".modal-head h3")
    conf("parcela 2" in t and "Nº 7" in t, "editar parcela diz o numero do contrato", t)
    financiamentos(detalhe=7)
    page.click('[data-quitar-financiamento="7"]')
    page.wait_for_timeout(200)
    conf("Nº 7" in page.inner_text(".modal-head h3"), "quitar diz o numero do contrato", page.inner_text(".modal-head h3"))
    financiamentos(detalhe=7)
    conf(not rola_de_lado(), "tela do contrato nao rola de lado em 1280 px")

    print("\n  -- celular (390 px) --")
    page.set_viewport_size({"width": 390, "height": 844})
    for nome, abrir in (("Financeiro", lambda: financeiro("despesa")), ("Pagar/Receber", lambda: contas("pagar")),
                        ("Financiamentos", lambda: financiamentos()), ("contrato", lambda: financiamentos(detalhe=7))):
        abrir()
        conf(not rola_de_lado(), f"{nome} nao rola de lado em 390 px")
    financeiro("despesa")
    conf(page.locator("[data-num-id='24801']").is_visible(), "o numero aparece no celular")

    reais = [e for e in erros if "ServiceWorker" not in e]
    conf(not reais, "nenhum erro de JavaScript", " | ".join(reais[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
