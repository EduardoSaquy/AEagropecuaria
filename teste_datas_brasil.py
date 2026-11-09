"""
Datas no formato do Brasil em qualquer navegador (09/11/2026).

Pedido do Eduardo: "as datas tem aparecido tipo data americana. Coloca na data normal, igual a gente olha no Brasil."
Duas causas:
  1. o campo de data do navegador (<input type="date">, "month", "datetime-local") se desenha no idioma do
     NAVEGADOR: num Chrome em ingles 10 de julho aparece 07/10/2026. Agora todo campo de data dos cinco apps vira
     um campo de texto dd/mm/aaaa (core.js), com o calendario do navegador num icone ao lado;
  2. Financiamentos (vencimento, data do contrato, pagamento) e a competencia em Pagar/Receber mostravam a data
     crua do banco (2026-07-10, 2026-08).

Prova, num navegador em INGLES (en-US, o padrao do Chromium de teste):
  - os campos de data mostram dd/mm/aaaa (mm/aaaa no mes; dd/mm/aaaa hh:mm com hora) e el.value continua no
    formato do banco (o resto do app nao mudou);
  - digitar so numeros poe as barras; "9/9/26" vira 09/09/2026 ao sair; data impossivel fica vazia e vermelha;
    apagar em cima da barra apaga o numero do lado; colar o formato do banco tambem funciona;
  - "change" sai uma vez quando a data fica completa e nao se repete ao sair do campo;
  - o calendario: um campo de data de verdade, invisivel, por cima do icone (44 px, fora da ordem do Tab, sem
    leitor de tela), com a data do campo; escolher nele preenche o campo e avisa o app uma vez; no tablet o toque
    vai para ele (e nao abre o teclado do campo de texto); campo desabilitado deixa o calendario desabilitado;
  - nos cinco apps (Matriz, Pecuaria, Cana, Cereais, Combustivel) nenhum campo de data do navegador fica a mostra;
  - Financiamentos e Pagar/Receber nao mostram mais data no formato do banco; rotulo continua ligado ao campo;
  - nada rola de lado no celular; nenhum erro de JavaScript.
Falha no codigo anterior (campo do navegador em ingles, data crua em Financiamentos).
"""
import json
import re
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
EXE = "/opt/pw-browsers/chromium"


def carrega(arquivo):
    src = (REPO / arquivo).read_text().split("with sync_playwright")[0]
    g = {"__file__": str(REPO / arquivo), "__name__": "fixture"}
    exec(src, g)
    return g


PAG = carrega("teste_pagamento_parcela_data_safra.py")
STUB, RELOGIO = PAG["STUB"], PAG["RELOGIO"]
DB_MATRIZ = PAG["DB"]
DB_MATRIZ["centros_custo"].append({"id": 90, "fazenda_id": None, "nome": "MANUTENCAO DA FROTA", "frente": None, "ativo": True,
                                   "tipo": "saida", "subcategoria": "OPERACIONAL | X"})
DB_MATRIZ["fazendas"] = [{"id": 1, "nome": "Mata Verde", "estado": "GO", "area_ha": 100, "ativo": True}]
DB_MATRIZ["entidades"] = [{"id": 5, "nome": "OFICINA X", "tipo": "fornecedor", "ativo": True}]
DB_MATRIZ["titulos"] = [{"id": 7, "tipo": "pagar", "entidade_id": 5, "descricao": "Pecas", "valor": 500.0, "vencimento": "2026-11-20",
                         "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False, "valor_baixado": 0, "situacao": "aberto"}]
DB_MATRIZ["titulo_rateios"] = [{"id": 70, "titulo_id": 7, "fazenda_id": 1, "atividade": "cana", "centro_custo_id": 90,
                                "competencia": "2026-08", "valor": 500.0}]
ADMIN = DB_MATRIZ["profiles"][0]

COMB = carrega("teste_custo_hora_equipamento.py")
LAV = carrega("teste_apps_lavoura.py")

DB_PEC = {
    "lotes": [{"id": 1, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 60, "data_inicio": "2026-08-01", "data_fim": None,
               "dieta_id": 1, "sexo": "macho"}],
    "dietas": [{"id": 1, "nome": "Terminacao", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}], "consumo_direto": False}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1.2, "estoque_kg": 5000}],
    "animais": [], "pesagens": [], "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "reproducao_custos": [],
    "saidas_racao": [], "leituras_cocho": [], "pasto": [], "producoes_racao": [], "abates": [], "precos_arroba": [],
    "movimentos": [], "manejos": [], "fazendas": [], "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "config_financeiro": [], "funcionarios": [], "pesagens_animais": [], "protocolos_inseminacao": [], "profiles": [ADMIN],
}

passes = falhas = 0


def conf(ok, nome, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {nome}")
    else:
        falhas += 1
        print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


TELA = "(s) => { const e = document.querySelector(s); return e ? Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').get.call(e) : null; }"
VALOR = "(s) => { const e = document.querySelector(s); return e ? e.value : null; }"
# campo de data do navegador ainda a mostra (o calendario invisivel tem a classe campo-data-seletor)
NATIVOS = """() => [...document.querySelectorAll('input[type=date], input[type=month], input[type=datetime-local]')]
  .filter(e => !e.classList.contains('campo-data-seletor')).map(e => e.id || e.outerHTML.slice(0, 60))"""
ISO_NA_TELA = r"""(raiz) => { const t = document.querySelector(raiz).innerText;
  return [...new Set(t.match(/\b\d{4}-\d{2}(-\d{2})?\b/g) || [])]; }"""


def nova_pagina(browser, arquivo, db, uid="u1", largura=1280, altura=900, toque=False, relogio=True):
    ctx = browser.new_context(viewport={"width": largura, "height": altura}, has_touch=toque, is_mobile=toque, locale="en-US")
    page = ctx.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.accept())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    if relogio:
        page.add_init_script(RELOGIO)
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'{uid}'}}, access_token:'x'}};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil", timeout=20000)
    page.wait_for_timeout(700)
    return page, erros


def digitar(page, sel, texto, sair=True):
    page.click(sel)
    page.keyboard.press("Control+A")
    page.keyboard.press("Backspace")
    page.keyboard.type(texto)
    if sair:
        page.keyboard.press("Tab")
    page.wait_for_timeout(60)


def contar_mudancas(page, sel):
    page.evaluate("(s) => { window.__mud = 0; window.__inp = 0; const e = document.querySelector(s); if (e.__contando) return;"
                  " e.__contando = true; e.addEventListener('change', () => window.__mud++); e.addEventListener('input', () => window.__inp++); }", sel)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=EXE) if Path(EXE).exists() else pw.chromium.launch()

    print("\n  AE MATRIZ, NAVEGADOR EM INGLES")
    page, erros = nova_pagina(browser, "AEMatriz.html", DB_MATRIZ)
    conf(page.evaluate("navigator.language") == "en-US", "o navegador de teste esta em ingles (en-US)")

    # Financiamentos: datas da tela
    page.evaluate("() => { state.page = 'financiamentos'; state.financiamentoDetalheId = null; state.modal = null; render(); }")
    page.wait_for_timeout(200)
    lista = page.locator("#root").inner_text()
    conf("28/08/2025" in lista and "10/07/2026" in lista, "lista de contratos: data do contrato e proxima parcela em dd/mm/aaaa")
    conf(page.evaluate(ISO_NA_TELA, "#root") == [], "lista de contratos sem data no formato do banco", str(page.evaluate(ISO_NA_TELA, "#root")))
    page.evaluate("() => { state.financiamentoDetalheId = 1; render(); }")
    page.wait_for_timeout(200)
    det = page.locator("#root").inner_text()
    conf("Contratado em 28/08/2025" in det and "10/07/2026" in det, "contrato: 'Contratado em 28/08/2025' e vencimento 10/07/2026")
    conf(page.evaluate(ISO_NA_TELA, "#root") == [], "contrato sem data no formato do banco", str(page.evaluate(ISO_NA_TELA, "#root")))

    # Registrar pagamento: o campo de data
    page.click('[data-pagamento-parcela="11"]')
    page.wait_for_timeout(250)
    S = "#f-pagdata"
    info = page.evaluate("""(s) => { const e = document.querySelector(s); const c = e.closest('.campo-data-caixa');
      const sel = c && c.querySelector('input.campo-data-seletor');
      const r = e.getBoundingClientRect(), rs = sel ? sel.getBoundingClientRect() : null;
      return {tipo: e.type, ph: e.placeholder, modo: e.inputMode, sel: sel ? sel.type : null, selValor: sel ? sel.value : null,
              aria: sel ? sel.getAttribute('aria-hidden') : null, tab: sel ? sel.tabIndex : null,
              larg: rs ? Math.round(rs.width) : 0, direita: rs ? Math.round(r.right - rs.right) : null,
              dentro: rs ? rs.left >= r.right - 45 && rs.top >= r.top - 1 && rs.bottom <= r.bottom + 1 : false,
              icone: !!(c && c.querySelector('svg.campo-data-icone')), opac: sel ? getComputedStyle(sel).opacity : null}; }""", S)
    conf(page.evaluate(TELA, S) == "10/07/2026" and page.evaluate(VALOR, S) == "2026-07-10",
         "campo mostra 10/07/2026 e o app le 2026-07-10", f"{page.evaluate(TELA, S)} / {page.evaluate(VALOR, S)}")
    conf(info["tipo"] == "text" and info["ph"] == "dd/mm/aaaa" and info["modo"] == "numeric",
         "campo de texto com 'dd/mm/aaaa' e teclado numerico", str(info))
    conf(page.evaluate(NATIVOS) == [], "nenhum campo de data do navegador a mostra na janela", str(page.evaluate(NATIVOS)))
    conf(info["sel"] == "date" and info["selValor"] == "2026-07-10" and info["icone"],
         "icone de calendario com um campo de data de verdade, ja com a data do campo", str(info))
    conf(info["aria"] == "true" and info["tab"] == -1 and info["opac"] == "0",
         "o calendario e invisivel, fora do Tab e do leitor de tela", str(info))
    conf(info["larg"] == 44 and info["direita"] == 0 and info["dentro"], "o calendario ocupa os 44 px da direita do campo", str(info))

    # digitar so numeros
    contar_mudancas(page, S)
    digitar(page, S, "15092026", sair=False)
    conf(page.evaluate(TELA, S) == "15/09/2026" and page.evaluate(VALOR, S) == "2026-09-15",
         "digitar 15092026 vira 15/09/2026 (2026-09-15)", str(page.evaluate(TELA, S)))
    conf(page.evaluate("window.__mud") == 1, "change sai uma vez, quando a data fica completa", str(page.evaluate("window.__mud")))
    aviso = page.evaluate("() => document.getElementById('f-pag-aviso').textContent")
    conf("67 dias depois do vencimento" in aviso, "o app ve a data nova na hora (aviso de 67 dias)", aviso)
    conf(page.evaluate("() => document.querySelector('#f-pagdata').closest('.campo-data-caixa').querySelector('.campo-data-seletor').value") == "2026-09-15",
         "o calendario acompanha o que foi digitado")
    page.keyboard.press("Tab")
    page.wait_for_timeout(60)
    conf(page.evaluate("window.__mud") == 1, "sair do campo nao repete o change", str(page.evaluate("window.__mud")))

    # 9/9/26 -> 09/09/2026 ao sair
    contar_mudancas(page, S)
    digitar(page, S, "9/9/26", sair=False)
    conf(page.evaluate(TELA, S) == "09/09/26" and page.evaluate(VALOR, S) == "", "digitando 9/9/26: o 0 do dia e do mes entra na barra; ano incompleto",
         str(page.evaluate(TELA, S)))
    page.keyboard.press("Tab")
    page.wait_for_timeout(60)
    conf(page.evaluate(TELA, S) == "09/09/2026" and page.evaluate(VALOR, S) == "2026-09-09", "ao sair: 09/09/2026 (2026-09-09)",
         str(page.evaluate(TELA, S)))
    conf(page.evaluate("window.__mud") == 1, "e o change sai uma vez, ao sair", str(page.evaluate("window.__mud")))

    # data impossivel
    digitar(page, S, "31022026")
    invalido = page.evaluate("(s) => document.querySelector(s).classList.contains('campo-data-invalido')", S)
    conf(page.evaluate(VALOR, S) == "" and invalido, "31/02/2026 nao existe: o app le vazio e o campo fica vermelho",
         f"{page.evaluate(TELA, S)} {invalido}")

    # apagar em cima da barra
    page.evaluate("(s) => { const e = document.querySelector(s); e.value = '2026-07-10'; }", S)
    conf(page.evaluate(TELA, S) == "10/07/2026", "o app grava 2026-07-10 e o campo mostra 10/07/2026")
    page.click(S)
    page.evaluate("(s) => document.querySelector(s).setSelectionRange(3, 3)", S)
    page.keyboard.press("Backspace")
    conf(page.evaluate(TELA, S) == "1/07/2026", "Backspace logo depois da barra apaga o numero do dia", str(page.evaluate(TELA, S)))
    page.keyboard.type("2")
    conf(page.evaluate(TELA, S) == "12/07/2026" and page.evaluate(VALOR, S) == "2026-07-12", "e digitar de novo corrige: 12/07/2026",
         str(page.evaluate(TELA, S)))

    # colar o formato do banco
    page.fill(S, "2026-07-10")
    conf(page.evaluate(TELA, S) == "10/07/2026" and page.evaluate(VALOR, S) == "2026-07-10", "colar 2026-07-10 tambem vira 10/07/2026")

    # escolher no calendario
    contar_mudancas(page, S)
    page.evaluate("""(s) => { const sel = document.querySelector(s).closest('.campo-data-caixa').querySelector('.campo-data-seletor');
      window.__vazou = 0; document.getElementById('root').addEventListener('input', ev => { if (ev.target === sel) window.__vazou++; });
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(sel, '2026-08-20');
      sel.dispatchEvent(new Event('input', {bubbles: true})); sel.dispatchEvent(new Event('change', {bubbles: true})); }""", S)
    page.wait_for_timeout(50)
    conf(page.evaluate(TELA, S) == "20/08/2026" and page.evaluate(VALOR, S) == "2026-08-20", "escolher 20/08/2026 no calendario preenche o campo")
    conf(page.evaluate("window.__mud") == 1 and page.evaluate("window.__inp") == 1, "e o app recebe um input e um change",
         f"{page.evaluate('window.__mud')} {page.evaluate('window.__inp')}")
    conf(page.evaluate("window.__vazou") == 0, "o evento do calendario invisivel nao chega ao app")

    # salvar digitando no formato do Brasil
    digitar(page, S, "10/07/2026")
    page.fill("#f-pagjuros", "23000.00")
    page.click('[data-save="pagamentoParcela"]')
    page.wait_for_timeout(500)
    p11 = next(p for p in page.evaluate("() => window.__DB__.parcelas_financiamento") if p["id"] == 11)
    conf(p11["status"] == "paga" and p11["data_pagamento"] == "2026-07-10", "pagamento digitado 10/07/2026 grava 2026-07-10", str(p11))
    pago = page.locator("#root").inner_text()
    conf("em 10/07/2026" in pago, "a parcela paga mostra 'em 10/07/2026'")

    # campo de mes: periodo dos Resultados
    page.evaluate("() => { state.page = 'resultados'; state.subAbaResultados = 'geral'; state.periodo.tipo = 'mes'; state.periodo.mes = '2026-11'; render(); }")
    page.wait_for_timeout(200)
    conf(page.evaluate(TELA, "#f-periodo-mes") == "11/2026" and page.evaluate("() => document.getElementById('f-periodo-mes').placeholder") == "mm/aaaa",
         "Resultados: o mes aparece 11/2026 (mm/aaaa)", str(page.evaluate(TELA, "#f-periodo-mes")))
    digitar(page, "#f-periodo-mes", "082026", sair=False)
    page.wait_for_timeout(200)
    conf(page.evaluate("() => state.periodo.mes") == "2026-08" and page.evaluate(TELA, "#f-periodo-mes") == "08/2026",
         "digitar 082026 troca o periodo para 2026-08 (08/2026)", str(page.evaluate("() => state.periodo.mes")))

    # Pagar/Receber: competencia
    page.evaluate("() => { state.page = 'contas'; state.abaContas = 'pagar'; state.filtroContas = 'todos'; state.modal = null; render(); }")
    page.wait_for_timeout(200)
    conf("Ago/2026" in page.locator("#root").inner_text() and page.evaluate(ISO_NA_TELA, "#root") == [],
         "Pagar/Receber: a competencia aparece Ago/2026, nao 2026-08", str(page.evaluate(ISO_NA_TELA, "#root")))
    page.evaluate("() => { editDraft = {tipo:'pagar', valor:'', vencimento:'2026-12-10', parcelas:1, intervaloDias:'', previsao:false,"
                  " rateios:[rateioVazio()]}; state.modal = {type:'titulo'}; render(); }")
    page.wait_for_timeout(200)
    conf(page.evaluate(TELA, "#f-tit-vencimento") == "10/12/2026" and page.evaluate(TELA, "#f-rat-comp-0") == "11/2026",
         "conta nova: vencimento 10/12/2026 e competencia 11/2026", f"{page.evaluate(TELA, '#f-tit-vencimento')} {page.evaluate(TELA, '#f-rat-comp-0')}")
    conf(page.evaluate(NATIVOS) == [], "conta nova sem campo de data do navegador a mostra")

    # campo desabilitado e navegador sem calendario de mes
    page.evaluate("""() => { document.body.insertAdjacentHTML('beforeend',
      '<div id="t-desab"><input id="t-d1" type="date" value="2026-01-02" disabled/></div>'); }""")
    page.wait_for_timeout(50)
    conf(page.evaluate(TELA, "#t-d1") == "02/01/2026" and page.evaluate("() => document.querySelector('#t-desab .campo-data-seletor').disabled"),
         "campo desabilitado: calendario desabilitado tambem")
    page.evaluate("""() => { TIPO_DATA_TEM_CALENDARIO['month'] = false;
      document.body.insertAdjacentHTML('beforeend', '<div id="t-sem"><input id="t-m1" type="month" value="2026-03"/></div>'); }""")
    page.wait_for_timeout(50)
    conf(page.evaluate(TELA, "#t-m1") == "03/2026" and page.evaluate("() => document.querySelector('#t-sem .campo-data-seletor')") is None
         and page.evaluate("() => document.querySelector('#t-sem .campo-data-caixa').classList.contains('sem-calendario')"),
         "navegador sem calendario de mes: so digitando, sem icone")
    conf(not erros, "AE Matriz: nenhum erro de JavaScript", str(erros[:3]))
    page.context.close()

    print("\n  AE MATRIZ NO CELULAR")
    page, erros = nova_pagina(browser, "AEMatriz.html", DB_MATRIZ, largura=390, altura=800, toque=True)
    page.evaluate("() => { state.page = 'financiamentos'; state.financiamentoDetalheId = 1; render(); }")
    page.wait_for_timeout(200)
    page.click('[data-pagamento-parcela="11"]')
    page.wait_for_timeout(250)
    lado = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(lado <= 1, f"janela de pagamento sem rolar de lado em 390 px ({lado} px)")
    alt = page.evaluate("() => Math.round(document.getElementById('f-pagdata').getBoundingClientRect().height)")
    conf(alt >= 44, f"campo de data com {alt} px de altura no toque")
    page.tap("#f-pagdata ~ .campo-data-seletor")
    page.wait_for_timeout(100)
    foco = page.evaluate("() => document.activeElement && document.activeElement.className")
    conf("campo-data-seletor" in str(foco), "tocar no icone vai para o calendario de verdade (no iPad e o que abre o calendario)", str(foco))
    page.tap("#f-pagdata", position={"x": 30, "y": 20})
    page.wait_for_timeout(100)
    conf(page.evaluate("() => document.activeElement && document.activeElement.id") == "f-pagdata", "tocar no texto vai para o campo (teclado numerico)")
    conf(not erros, "nenhum erro de JavaScript", str(erros[:3]))
    page.context.close()

    print("\n  AE PECUARIA")
    page, erros = nova_pagina(browser, "AEpecuaria.html", DB_PEC, relogio=True)
    page.evaluate("() => { openNewModal('movimento'); render(); }")
    page.wait_for_timeout(300)
    conf(page.evaluate(TELA, "#f-data") == "09/11/2026" and page.evaluate(VALOR, "#f-data") == "2026-11-09",
         "movimento de estoque: data de hoje em 09/11/2026", str(page.evaluate(TELA, "#f-data")))
    conf(page.evaluate(NATIVOS) == [], "nenhum campo de data do navegador a mostra")
    page.wait_for_timeout(200)
    conf(page.evaluate("() => !!document.querySelector('label[for=\"f-data\"]')"), "o rotulo 'Data' continua ligado ao campo (o calendario nao atrapalha)")
    digitar(page, "#f-data", "01112026")
    conf(page.evaluate(VALOR, "#f-data") == "2026-11-01", "digitar 01112026: o app le 2026-11-01")
    conf(not erros, "AE Pecuaria: nenhum erro de JavaScript", str(erros[:3]))
    page.context.close()

    print("\n  AE COMBUSTIVEL")
    page, erros = nova_pagina(browser, "AECombustivel.html", dict(COMB["DB"], profiles=[COMB["ADMIN"]]), relogio=True)
    page.evaluate("() => { state.rateioFiltro = {dataInicio: '2026-10-01', dataFim: '2026-10-31'}; state.page = 'rateioEquipamento'; render(); }")
    page.wait_for_timeout(250)
    conf(page.evaluate(TELA, "#f-rateio-inicio") == "01/10/2026" and page.evaluate(TELA, "#f-rateio-fim") == "31/10/2026",
         "Rateio: periodo de 01/10/2026 a 31/10/2026")
    conf(page.evaluate(NATIVOS) == [], "nenhum campo de data do navegador a mostra no Rateio")
    page.evaluate("() => { abrirNovoAbastecimento(); render(); }")
    page.wait_for_timeout(250)
    tela = page.evaluate(TELA, "#f-ab-data-hora")
    conf(bool(re.fullmatch(r"09/11/2026 \d\d:\d\d", tela or "")) and page.evaluate("() => document.getElementById('f-ab-data-hora').placeholder") == "dd/mm/aaaa hh:mm",
         "abastecimento: data e hora em dd/mm/aaaa hh:mm", str(tela))
    digitar(page, "#f-ab-data-hora", "081120260730")
    conf(page.evaluate(TELA, "#f-ab-data-hora") == "08/11/2026 07:30" and page.evaluate(VALOR, "#f-ab-data-hora") == "2026-11-08T07:30",
         "digitar 081120260730: 08/11/2026 07:30 (2026-11-08T07:30)", str(page.evaluate(TELA, "#f-ab-data-hora")))
    conf(not erros, "AE Combustivel: nenhum erro de JavaScript", str(erros[:3]))
    page.context.close()

    for arquivo, rotulo in (("AECana.html", "AE CANA"), ("AECereais.html", "AE CEREAIS")):
        print(f"\n  {rotulo}")
        page, erros = nova_pagina(browser, arquivo, dict(LAV["DB"], profiles=[LAV["PERFIS"]["admin"]]),
                                  uid=LAV["PERFIS"]["admin"]["id"], relogio=False)
        page.evaluate("() => { abrirNovoCadastro('safras'); render(); }")
        page.wait_for_timeout(250)
        conf(page.evaluate(NATIVOS) == [] and page.evaluate("() => document.querySelectorAll('.modal .campo-data').length") == 2,
             "safra: Inicio e Fim sao campos dd/mm/aaaa")
        digitar(page, "#f-dataInicio", "01052026")
        conf(page.evaluate(TELA, "#f-dataInicio") == "01/05/2026" and page.evaluate(VALOR, "#f-dataInicio") == "2026-05-01",
             "digitar 01052026: 01/05/2026 (2026-05-01)")
        conf(not erros, f"{rotulo}: nenhum erro de JavaScript", str(erros[:3]))
        page.context.close()

    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
sys.exit(1 if falhas else 0)
