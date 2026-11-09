"""
Menu lateral do AE Matriz (pedido do Eduardo, 06/11/2026; tablet deitado e janelinhas dos apps em 08/11/2026): o menu principal
(Painel, Resultados, Financeiro...) grande, em coluna a esquerda, e os 4 apps (Pecuaria, Cana, Cereais, Combustivel) como
janelinhas no Painel, duas por linha, ao lado do menu. A lista pequena de apps que ficava na barra saiu a pedido dele. Da largura
de 1160 px para cima a barra e uma coluna (232 px de 1280 para cima, 196 px de 1160 a 1279: o iPad deitado, 1180 e 1194);
de 760 a 1159 px (tablet em pe) segue a barra de cima, com o menu maior; abaixo de 760 px e o menu de celular. Prova:
  - de 1160 px para cima (iPad 1180x820 e 1194x834 com toque, tablet 1280x800 e desktop com mouse) a barra fica a esquerda, o
    conteudo ao lado, o menu principal com letra e botoes grandes, e nao ha mais a lista pequena de apps na barra;
  - o Painel mostra os 4 apps como janelinhas, 2 por linha, com o link certo de cada um e dentro da tela do tablet;
  - o usuario, "Trocar senha" e "Sair" cabem na altura da tela e a navegacao continua funcionando;
  - quem so tem permissao do painel de um app ve so aquele app;
  - em 1100 px e em tablet em pe (820) a barra de cima fica, e no celular (390) o menu de celular segue como era;
  - cada item do menu tem seu icone (antes varios usavam o mesmo desenho de pessoa).
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [], "lancamentos_financeiros": [], "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
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


def abre(browser, w, h, toque):
    ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.apps.length > 0", timeout=30000)
    page.wait_for_timeout(700)
    return page


MEDE = """() => {
  const r = s => { const e = document.querySelector(s); if(!e) return null; const b = e.getBoundingClientRect(); const cs = getComputedStyle(e);
    return {x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height), fonte: parseFloat(cs.fontSize), display: cs.display}; };
  const cards = [...document.querySelectorAll('.app-card')].map(e => { const b = e.getBoundingClientRect(); return {x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height), right: Math.round(b.right), bottom: Math.round(b.bottom)}; });
  const sair = document.querySelector('[data-logout]');
  return {tabs: r('.tabsrow'), main: r('.main'), nav: r('.nav-item'), user: r('.topbar-user'), sair: r('[data-logout]'), cards,
          semListaDeApps: document.querySelectorAll('.side-app, .side-apps').length === 0,
          sairBottom: sair ? Math.round(sair.getBoundingClientRect().bottom) : null, alturaJanela: window.innerHeight,
          larguraJanela: document.documentElement.clientWidth, rolaDeLado: document.documentElement.scrollWidth > document.documentElement.clientWidth};
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for rotulo, w, h, toque, larg_barra in (("iPad 1180x820 (toque)", 1180, 820, True, (190, 206)), ("iPad Pro 1194x834 (toque)", 1194, 834, True, (190, 206)),
                                            ("tablet 1280x800 (toque)", 1280, 800, True, (225, 240)), ("desktop 1440x860 (mouse)", 1440, 860, False, (225, 240))):
        print(f"== {rotulo}")
        page = abre(browser, w, h, toque)
        m = page.evaluate(MEDE)
        conf(m["tabs"] and m["tabs"]["x"] == 0 and larg_barra[0] <= m["tabs"]["w"] <= larg_barra[1], "a barra do menu e uma coluna a esquerda", str(m["tabs"]))
        conf(m["main"] and m["main"]["x"] >= m["tabs"]["w"] - 2 and m["main"]["y"] == 0, "o conteudo fica ao lado, desde o topo", str(m["main"]))
        conf(m["nav"]["fonte"] >= 15 and m["nav"]["h"] >= 46, "o menu principal e grande (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
        conf(m["semListaDeApps"], "a lista pequena de apps saiu da barra (os apps estao no Painel)")
        conf(m["sairBottom"] <= m["alturaJanela"], "o botao Sair cabe na altura da tela (%s de %s px)" % (m["sairBottom"], m["alturaJanela"]))
        conf(not m["rolaDeLado"], "a pagina nao rola de lado")
        # Painel: os 4 apps como janelinhas, duas por linha
        c = m["cards"]
        conf(len(c) == 4, "o Painel mostra os 4 apps como janelinhas", str(len(c)))
        if len(c) == 4:
            conf(c[0]["y"] == c[1]["y"] and c[2]["y"] == c[3]["y"] and c[2]["y"] > c[0]["y"] and c[0]["x"] < c[1]["x"] and c[0]["x"] == c[2]["x"] and c[1]["x"] == c[3]["x"],
                 "duas por linha: Pecuaria e Cana em cima, Cereais e Combustivel embaixo", str(c))
            conf(abs(c[0]["w"] - c[1]["w"]) <= 1 and c[0]["w"] >= 330, "as janelinhas tem a mesma largura (%d px)" % c[0]["w"], str(c))
            conf(max(x["right"] for x in c) <= m["larguraJanela"] and c[3]["bottom"] <= m["alturaJanela"] + 40,
                 "as 4 cabem na largura da tela e (quase) na altura, sem precisar rolar muito", str(c))
        links = page.evaluate("() => [...document.querySelectorAll('.app-card a[href]')].map(a => a.getAttribute('href'))")
        conf(links == ["./AEpecuaria.html", "./AECana.html", "./AECereais.html", "./AECombustivel.html"], "cada app aponta para o arquivo certo", str(links))
        conf(m["user"] is not None and page.locator("[data-trocar-senha-abrir]").count() == 1 and page.locator("[data-logout]").count() == 1,
             "usuario, Trocar senha e Sair continuam na barra")
        icones = page.evaluate("() => [...document.querySelectorAll('.nav-item')].map(b => b.querySelector('svg').innerHTML)")
        conf(len(icones) >= 8 and len(set(icones)) == len(icones), "cada item do menu tem um icone proprio (%d itens)" % len(icones))
        for chave in ("financeiro", "resultados", "contas", "painel"):
            page.click(f"[data-nav='{chave}']")
            page.wait_for_timeout(150)
            conf(page.evaluate("() => state.page") == chave, f"clicar em {chave} troca de tela")
        # permissao: so o painel da Pecuaria
        page.evaluate("""() => { state.perfil = {...state.perfil, papel: 'funcionario', permissoes: {matriz_painel_pecuaria: 'visualizar'}}; render(); }""")
        page.wait_for_timeout(200)
        nomes = page.evaluate("() => [...document.querySelectorAll('.app-card .app-card-nome')].map(a => a.textContent.trim())")
        conf(nomes == ["AE Pecuária"], "sem permissao dos outros paineis, so o app liberado aparece", str(nomes))
        page.context.close()

    for rotulo, w, h in (("tablet pequeno 1100x800", 1100, 800), ("tablet em pe 820x1180", 820, 1180)):
        print(f"== {rotulo} (toque): a barra de cima fica, com o menu maior")
        page = abre(browser, w, h, True)
        m = page.evaluate(MEDE)
        top = page.evaluate("() => { const t = document.querySelector('.topbar'); const b = t.getBoundingClientRect(); return {x: b.x, y: b.y, w: Math.round(b.width), h: Math.round(b.height)}; }")
        conf(m["tabs"]["y"] >= 55 and m["tabs"]["w"] >= w - 60, "a barra do menu continua em cima, na largura toda", str(m["tabs"]))
        conf(m["nav"]["fonte"] >= 14.5 and m["nav"]["h"] >= 44, "o menu principal esta maior que antes (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
        conf(m["semListaDeApps"] and len(m["cards"]) == 4, "sem lista pequena de apps na barra; os 4 apps seguem no Painel")
        conf(top["y"] == 0 and top["w"] >= w - 2 and top["h"] < 120, "a barra de cima fica em cima, na largura toda", str(top))
        conf(not m["rolaDeLado"], "a pagina nao rola de lado")
        page.context.close()

    print("== celular 390x800")
    page = abre(browser, 390, 800, True)
    m = page.evaluate(MEDE)
    top = page.evaluate("() => { const t = document.querySelector('.topbar'); const b = t.getBoundingClientRect(); return {y: b.y, w: Math.round(b.width)}; }")
    conf(top["y"] == 0 and top["w"] >= 388, "a barra de cima segue em cima, na largura toda", str(top))
    # celular (09/11/2026): no lugar das janelinhas, icones grandes, um embaixo do outro (teste_painel_celular.py cobre o resto)
    icones = page.evaluate("() => [...document.querySelectorAll('.app-icone')].map(e => e.getBoundingClientRect().y)")
    conf(page.evaluate("() => getComputedStyle(document.querySelector('.painel-cartoes')).display") == "none" and len(icones) == 4 and len(set(round(y) for y in icones)) == 4,
         "no celular os 4 apps viram icones um embaixo do outro (sem as janelinhas)", str(icones))
    conf(not m["rolaDeLado"], "a pagina nao rola de lado")
    page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
