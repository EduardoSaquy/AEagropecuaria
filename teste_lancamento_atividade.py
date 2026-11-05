"""
Lancamento sem atividade nao passa; conta que serve a mais de uma atividade
e dividida (pedido do Eduardo em 05/11/2026: "nao poder lancar sem atividade;
se for para ratear, lanca as tres atividades para nao gerar confusao").

Por que: um lancamento 'geral' sem as partes do ERP nao cai em nenhuma das
tres atividades nos resultados (R$ 979 mil ficaram de fora assim), e a tela de
custo por hectare o reparte por outra regra. Prova:
  - lancamento novo nasce SEM atividade e a lista nao oferece "Geral";
  - salvar sem escolher atividade e barrado;
  - "Dividir entre as atividades" comeca em partes iguais e grava UM
    lancamento por atividade, somando exatamente o valor (900 -> 300+300+300,
    100 -> 33,33+33,33+33,34), todos numa chamada so;
  - percentual que nao fecha 100% e divisao com uma atividade so sao barrados
    e nada e gravado;
  - 'geral' antigo (do ERP) abre travado e segue 'geral' ao editar outro campo;
  - conta a pagar tambem pede a atividade de cada rateio.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [
        {"id": 9, "fazenda_id": None, "nome": "Energia", "frente": None, "ativo": True, "tipo": "saida",
         "subcategoria": "DESPESAS OPERACIONAIS | Energia"},
        {"id": 10, "fazenda_id": None, "nome": "Adubo da cana", "frente": "cana", "ativo": True, "tipo": "saida",
         "subcategoria": "DESPESAS OPERACIONAIS | Insumos"},
    ],
    # Sem data e sem mes: recorrente, aparece na lista de qualquer mes.
    "lancamentos_financeiros": [
        {"id": 1, "tipo": "despesa", "atividade": "geral", "fazenda_id": None, "centro_custo_id": 9,
         "descricao": "Contador", "valor": 1000, "data": None, "mes": None, "areas": []},
        {"id": 2, "tipo": "despesa", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 10,
         "descricao": "Adubo avulso", "valor": 500, "data": None, "mes": None, "areas": []},
    ],
    "financiamentos": [], "parcelas_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
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


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    lancs = lambda: page.evaluate("() => window.__DB__.lancamentos_financeiros")
    novos = lambda: [l for l in lancs() if l["id"] > 2]
    opcoes = lambda sel: page.eval_on_selector(sel, "e => [...e.options].map(o => o.value)")
    texto = lambda sel: page.eval_on_selector(sel, "e => e.textContent")
    erro_tela = lambda: page.evaluate("() => state.erroLancamento")

    def abrir_novo():
        page.evaluate("() => { state.page='financeiro'; state.abaFinanceiro='despesa'; state.filtroAtividade=''; state.erroLancamento=''; state.modal=null; editDraft=null; render(); }")
        page.wait_for_timeout(250)
        page.locator("[data-novo-lancamento]").click()
        page.wait_for_timeout(250)

    def digitar_valor(v):
        page.click("#f-valorlanc")
        page.fill("#f-valorlanc", "")
        page.keyboard.type(v)

    def preencher_basico(valor):
        page.select_option("#f-centrocustolanc", "9")
        page.fill("#f-descricaolanc", "Conta de teste")
        digitar_valor(valor)

    print("\n  LANCAMENTO NOVO PEDE A ATIVIDADE")
    abrir_novo()
    conf(page.eval_on_selector("#f-atividadelanc", "e => e.value") == "",
         "lancamento novo nasce sem atividade escolhida")
    ops = opcoes("#f-atividadelanc")
    conf(ops == ["", "pecuaria", "cana", "graos", "dividir"],
         "a lista oferece as tres atividades e a divisao, sem Geral", str(ops))

    preencher_basico("900")
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(300)
    conf("atividade" in erro_tela() and len(novos()) == 0,
         "salvar sem escolher atividade e barrado e nada e gravado", f"{erro_tela()} / {len(novos())}")

    print("\n  DIVIDIR ENTRE AS ATIVIDADES (partes iguais)")
    page.select_option("#f-atividadelanc", "dividir")
    page.wait_for_timeout(250)
    conf(page.locator("#bloco-divisao").count() == 1, "dividir mostra os tres percentuais")
    vals = [page.eval_on_selector(f"#f-divisao-{k}", "e => e.value") for k in ("pecuaria", "cana", "graos")]
    conf(vals == ["33,333", "33,333", "33,334"], "comeca em partes iguais", str(vals))
    reais = [texto(f"#f-divisao-valor-{k}") for k in ("pecuaria", "cana", "graos")]
    conf(reais == ["R$ 300,00"] * 3, "mostra quanto cada atividade leva (900 -> 300 cada)", str(reais))
    conf("Soma 100%" in texto("#f-divisao-aviso"), "avisa que a soma fecha", texto("#f-divisao-aviso"))
    conf(page.eval_on_selector("#f-descricaolanc", "e => e.value") == "Conta de teste",
         "trocar para dividir nao apaga o que ja foi digitado")

    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(500)
    n = novos()
    conf(len(n) == 3 and sorted(l["atividade"] for l in n) == ["cana", "graos", "pecuaria"],
         "grava um lancamento por atividade", str([(l["atividade"], l["valor"]) for l in n]))
    conf(all(abs(l["valor"] - 300) < 0.001 for l in n), "900 divide em 300 + 300 + 300",
         str([l["valor"] for l in n]))
    conf(all(l["centro_custo_id"] == 9 and l["descricao"] == "Conta de teste" for l in n),
         "todos levam o mesmo centro de custo e descricao")
    conf(all("Dividido entre atividades: parte" in (l.get("observacao") or "") for l in n),
         "cada um leva o rastro de que e a mesma conta dividida", str([l.get("observacao") for l in n]))
    conf(page.evaluate("() => state.modal") is None, "fecha o formulario depois de salvar")
    escritas = [e for e in page.evaluate("() => window.__ESCRITAS__")
                if e["tabela"] == "lancamentos_financeiros" and e["op"] == "insert"]
    conf(len(escritas) == 1 and isinstance(escritas[0]["v"], list) and len(escritas[0]["v"]) == 3,
         "as tres partes vao numa chamada so (todas entram ou nenhuma)", str(len(escritas)))

    print("\n  OS CENTAVOS FECHAM")
    abrir_novo()
    page.select_option("#f-atividadelanc", "dividir")
    page.wait_for_timeout(200)
    preencher_basico("100")
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(500)
    n2 = [l for l in novos() if l["id"] > 5]
    vs = sorted(round(l["valor"], 2) for l in n2)
    conf(vs == [33.33, 33.33, 33.34] and round(sum(vs), 2) == 100.0,
         "100 divide em 33,33 + 33,33 + 33,34 (soma exata)", str(vs))

    print("\n  PERCENTUAL ESCOLHIDO")
    abrir_novo()
    page.select_option("#f-atividadelanc", "dividir")
    page.wait_for_timeout(200)
    preencher_basico("1000")
    page.fill("#f-divisao-pecuaria", "50")
    page.fill("#f-divisao-cana", "0")
    page.fill("#f-divisao-graos", "50")
    page.wait_for_timeout(100)
    conf(texto("#f-divisao-valor-pecuaria") == "R$ 500,00" and texto("#f-divisao-valor-cana") == "—"
         and texto("#f-divisao-valor-graos") == "R$ 500,00",
         "os reais acompanham a digitacao (500 / - / 500)",
         f"{texto('#f-divisao-valor-pecuaria')} / {texto('#f-divisao-valor-cana')} / {texto('#f-divisao-valor-graos')}")
    antes = len(lancs())
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(500)
    n3 = lancs()[antes:]
    conf(sorted((l["atividade"], l["valor"]) for l in n3) == [("graos", 500), ("pecuaria", 500)],
         "50 / 0 / 50 grava so duas partes de 500", str([(l["atividade"], l["valor"]) for l in n3]))

    print("\n  DIVISAO QUE NAO PODE")
    abrir_novo()
    page.select_option("#f-atividadelanc", "dividir")
    page.wait_for_timeout(200)
    preencher_basico("600")
    antes = len(lancs())
    for k in ("pecuaria", "cana", "graos"):
        page.fill(f"#f-divisao-{k}", "40")
    page.wait_for_timeout(100)
    conf("120,000" in texto("#f-divisao-aviso"), "mostra a soma errada enquanto digita", texto("#f-divisao-aviso"))
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(300)
    conf("100%" in erro_tela() and len(lancs()) == antes,
         "40 + 40 + 40 e barrado e nada e gravado", f"{erro_tela()} / {len(lancs()) - antes}")

    page.fill("#f-divisao-pecuaria", "100")
    page.fill("#f-divisao-cana", "0")
    page.fill("#f-divisao-graos", "0")
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(300)
    conf("pelo menos duas" in erro_tela() and len(lancs()) == antes,
         "dividir com uma atividade so e barrado (escolha ela na lista)", f"{erro_tela()} / {len(lancs()) - antes}")

    print("\n  ATIVIDADE UNICA CONTINUA IGUAL")
    abrir_novo()
    page.select_option("#f-atividadelanc", "cana")
    page.wait_for_timeout(200)
    preencher_basico("250")
    antes = len(lancs())
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(500)
    n4 = lancs()[antes:]
    conf(len(n4) == 1 and n4[0]["atividade"] == "cana" and n4[0]["valor"] == 250 and not (n4[0].get("observacao") or ""),
         "uma atividade grava um lancamento so, sem rastro de divisao", str(n4))

    print("\n  FILTRO DA TELA")
    page.evaluate("() => { state.filtroAtividade='graos'; state.modal=null; render(); }")
    page.wait_for_timeout(200)
    page.locator("[data-novo-lancamento]").click()
    page.wait_for_timeout(200)
    conf(page.eval_on_selector("#f-atividadelanc", "e => e.value") == "graos",
         "com o filtro em Graos, o lancamento novo ja vem em Graos")
    page.evaluate("() => { state.filtroAtividade='geral'; state.modal=null; render(); }")
    page.wait_for_timeout(200)
    page.locator("[data-novo-lancamento]").click()
    page.wait_for_timeout(200)
    conf(page.eval_on_selector("#f-atividadelanc", "e => e.value") == "",
         "com o filtro em Geral, o lancamento novo NAO herda Geral")

    print("\n  LANCAMENTO 'GERAL' ANTIGO")
    page.evaluate("() => { state.filtroAtividade=''; state.modal=null; editDraft=null; render(); }")
    page.wait_for_timeout(200)
    page.locator('[data-edit-lancamento="1"]').click()
    page.wait_for_timeout(250)
    conf(page.eval_on_selector("#f-atividadelanc", "e => e.disabled") is True
         and page.eval_on_selector("#f-atividadelanc", "e => e.value") == "geral",
         "abre travado em Geral (trocar nao desfaz a divisao do ERP)")
    conf("dividir" not in opcoes("#f-atividadelanc"), "editar nao oferece dividir")
    page.fill("#f-descricaolanc", "Contador ajustado")
    page.locator('[data-save="lancamento"]').click()
    page.wait_for_timeout(500)
    l1 = [l for l in lancs() if l["id"] == 1][0]
    conf(l1["descricao"] == "Contador ajustado" and l1["atividade"] == "geral",
         "editar outro campo grava e segue Geral", f"{l1['descricao']} / {l1['atividade']}")

    page.locator('[data-edit-lancamento="2"]').click()
    page.wait_for_timeout(250)
    conf(page.eval_on_selector("#f-atividadelanc", "e => e.disabled") is False
         and opcoes("#f-atividadelanc") == ["", "pecuaria", "cana", "graos"],
         "lancamento de uma atividade edita normal, sem Geral e sem dividir", str(opcoes("#f-atividadelanc")))
    page.locator('[data-close="1"]').first.click()
    page.wait_for_timeout(200)

    print("\n  CONTA A PAGAR TAMBEM PEDE A ATIVIDADE")
    page.evaluate("""() => {
      window.__ESCRITAS__ = [];
      state.page='contas'; state.abaContas='pagar'; state.erroTitulo=''; state.modal=null;
      editDraft = {tipo:'pagar', valor:'', vencimento:'2026-12-10', parcelas:1,
                   intervaloDias:'', previsao:false, rateios:[rateioVazio()]};
      state.modal = {type:'titulo'}; render();
    }""")
    page.wait_for_timeout(250)
    conf(page.eval_on_selector("#f-rat-atividade-0", "e => e.value") == "",
         "o rateio da conta a pagar nasce sem atividade")
    ops_t = opcoes("#f-rat-atividade-0")
    conf(ops_t == ["", "pecuaria", "cana", "graos"], "e nao oferece Geral", str(ops_t))

    def preencher_titulo(seletor, valor):
        el = page.locator(seletor)
        el.click()
        el.fill("")
        el.type(valor)
        page.keyboard.press("Tab")
        page.wait_for_timeout(80)

    preencher_titulo("#f-tit-entidade", "FORNECEDOR DE TESTE")
    preencher_titulo("#f-tit-descricao", "Frete")
    preencher_titulo("#f-tit-valor", "800")
    page.select_option("#f-rat-centro-0", "9")
    page.click("[data-save='titulo']")
    page.wait_for_timeout(400)
    esc = [e for e in page.evaluate("() => window.__ESCRITAS__") if e["tabela"] in ("titulos", "titulo_rateios")]
    conf(not esc and "atividade" in page.evaluate("() => state.erroTitulo"),
         "salvar a conta sem atividade e barrado e nada e gravado",
         f"{page.evaluate('() => state.erroTitulo')} / {esc}")
    page.select_option("#f-rat-atividade-0", "cana")
    page.click("[data-save='titulo']")
    page.wait_for_timeout(500)
    rats = [e for e in page.evaluate("() => window.__ESCRITAS__") if e["tabela"] == "titulo_rateios" and e["op"] == "insert"]
    conf(len(rats) >= 1, "com a atividade escolhida, a conta e salva", str(rats))

    conf(not erros, "nenhum erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
