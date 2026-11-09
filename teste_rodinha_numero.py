"""
Rodinha do mouse nao muda numero de campo (pedido do Eduardo e das secretarias, 09/11/2026): com o cursor parado em cima de
um campo numerico ainda selecionado (ex.: no de parcelas da conta a pagar), girar a rodinha para rolar a tela somava ou tirava
1 do campo e a conta refazia o valor de cada parcela. Regra no core.js (Matriz, Pecuaria, Cana, Cereais, Combustivel) e a
mesma no Adubacao.html (que nao usa o nucleo).

Prova, nos seis apps:
  - campo numerico selecionado + rodinha em cima dele: o valor NAO muda, o campo perde a selecao e a pagina rola;
  - a rodinha de novo em cima do campo (ja sem selecao) tambem nao muda;
  - teclado continua igual (seta para cima soma 1) e digitar continua;
  - rodinha em OUTRO lugar da tela nao tira a selecao do campo (so quando o cursor esta em cima dele).
No AE Matriz, o caso que as secretarias viveram: conta a pagar de R$ 900,00 em 3 parcelas, rodinha em cima do no de parcelas
selecionado: continua 3 parcelas de R$ 300,00; e o no de parcelas do financiamento tambem nao muda.
Falha no codigo anterior (a rodinha mudava 3 para 4 e a pagina nao rolava).
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
DB_MATRIZ = {
    "fazendas": [{"id": 1, "nome": "Fazenda A", "estado": "GO", "area_ha": 300, "ativo": True}],
    "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [{"id": 9, "fazenda_id": None, "nome": "Manutencao", "frente": None, "ativo": True, "tipo": "saida",
                       "subcategoria": "DESPESAS | Manutencao"}],
    "equipamentos": [], "lancamentos_financeiros": [], "financiamentos": [], "parcelas_financiamento": [],
    "entidades": [{"id": 5, "nome": "BERTINI", "documento": "", "papel": "fornecedor", "ativo": True}], "contas_bancarias": [],
    "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
}
APPS = ("AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html", "Adubacao.html")

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, arquivo, db=None):
    page = browser.new_page(viewport={"width": 1280, "height": 800})
    page.erros = []
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    if db is not None:
        page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_timeout(1500)
    return page


def sobre(page, seletor):
    caixa = page.locator(seletor).bounding_box()
    page.mouse.move(caixa["x"] + caixa["width"] / 2, caixa["y"] + caixa["height"] / 2)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    print("\n  RODINHA DO MOUSE NAO MUDA NUMERO DE CAMPO")
    for arquivo in APPS:
        print(f"\n  -- {arquivo} --")
        page = abre(browser, arquivo)
        # campo numerico de teste fora do #root (o redesenho do app nao o apaga) e pagina comprida para poder rolar
        page.evaluate("""() => {
          const caixa = document.createElement('div'); caixa.id = 'teste-rodinha';
          caixa.innerHTML = '<input id="tr-num" type="number" value="3" style="font-size:20px; width:120px">'
            + '<button id="tr-outro" style="margin-left:300px">outro</button><div style="height:4000px"></div>';
          document.body.prepend(caixa); window.scrollTo(0, 0);
        }""")
        page.click("#tr-num")
        sobre(page, "#tr-num")
        page.mouse.wheel(0, 300)
        page.wait_for_timeout(250)
        conf(page.input_value("#tr-num") == "3", "rodinha em cima do campo selecionado nao muda o numero", page.input_value("#tr-num"))
        conf(page.evaluate("() => document.activeElement && document.activeElement.id") != "tr-num", "o campo perde a selecao")
        conf(page.evaluate("() => window.scrollY") > 0, "a pagina rola", str(page.evaluate("() => window.scrollY")))
        page.evaluate("() => window.scrollTo(0, 0)")
        page.wait_for_timeout(100)
        sobre(page, "#tr-num")
        page.mouse.wheel(0, -300)
        page.wait_for_timeout(200)
        conf(page.input_value("#tr-num") == "3", "rodinha de novo (campo ja sem selecao) tambem nao muda")
        page.click("#tr-num")
        page.keyboard.press("ArrowUp")
        conf(page.input_value("#tr-num") == "4", "teclado continua igual: seta para cima soma 1", page.input_value("#tr-num"))
        page.fill("#tr-num", "12")
        conf(page.input_value("#tr-num") == "12", "digitar continua igual")
        page.click("#tr-num")
        sobre(page, "#tr-outro")
        page.mouse.wheel(0, 100)
        page.wait_for_timeout(200)
        conf(page.evaluate("() => document.activeElement && document.activeElement.id") == "tr-num",
             "rodinha em outro lugar da tela nao tira a selecao do campo")
        conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
        page.close()

    print("\n  -- AE Matriz: no de parcelas da conta a pagar e do financiamento --")
    page = abre(browser, "AEMatriz.html", DB_MATRIZ)
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.entidades && state.entidades.length === 1", timeout=20000)
    page.evaluate("() => { state.page = 'contas'; state.abaContas = 'pagar'; render(); }")
    page.wait_for_timeout(200)
    page.click("[data-novo-titulo='pagar']")
    page.wait_for_timeout(300)
    page.fill("#f-tit-valor", "900")
    page.locator("#f-tit-valor").blur()
    page.fill("#f-tit-parcelas", "3")
    page.locator("#f-tit-parcelas").dispatch_event("change")
    page.wait_for_timeout(300)

    def valores():
        return page.evaluate("() => [...document.querySelectorAll('[id^=\"f-tit-valorparc-\"]')].map(e => e.value)")

    antes = valores()
    conf(len(antes) == 3, "conta de R$ 900 em 3 parcelas montada", str(antes))
    page.click("#f-tit-parcelas")
    sobre(page, "#f-tit-parcelas")
    page.mouse.wheel(0, -200)
    page.wait_for_timeout(300)
    page.mouse.wheel(0, 200)
    page.wait_for_timeout(300)
    conf(page.input_value("#f-tit-parcelas") == "3", "rodinha em cima do no de parcelas selecionado: continua 3", page.input_value("#f-tit-parcelas"))
    conf(valores() == antes, "o valor de cada parcela nao muda", f"{antes} -> {valores()}")
    page.evaluate("() => { state.modal = null; editDraft = null; state.page = 'financiamentos'; state.financiamentoDetalheId = null; render(); }")
    page.wait_for_timeout(200)
    page.click("[data-novo-financiamento]")
    page.wait_for_timeout(300)
    if page.locator("#f-numparcelasfin").count():
        page.fill("#f-numparcelasfin", "5")
        page.click("#f-numparcelasfin")
        sobre(page, "#f-numparcelasfin")
        page.mouse.wheel(0, -200)
        page.wait_for_timeout(300)
        conf(page.input_value("#f-numparcelasfin") == "5", "no de parcelas do financiamento tambem nao muda", page.input_value("#f-numparcelasfin"))
    else:
        conf(False, "campo de no de parcelas do financiamento existe")
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
