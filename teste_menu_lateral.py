"""
Menu lateral do AE Matriz (pedido do Eduardo, 06/11/2026): o menu principal (Painel, Resultados, Financeiro...) grande e os
apps (Pecuaria, Cana, Cereais, Combustivel) pequenos na barra. Da largura de 1000 px para cima a barra e uma coluna a
esquerda; de 760 a 1279 px (tablet menor) segue a barra de cima, com o menu maior e os apps pequenos a direita, porque o
conteudo precisa de ~990 px para as tabelas largas nao rolarem de lado; abaixo de 760 px e o menu de celular. Prova:
  - de 1280 px para cima (tablet 1280x800 com toque e desktop com mouse) a barra fica a esquerda, o conteudo ao lado, e o
    menu principal tem letra maior e botoes mais altos do que os atalhos dos apps;
  - os 4 apps aparecem pequenos na barra, com o link certo de cada um, e cabem na tela do tablet (800 px de altura);
  - em 1180 px a barra de cima tem o menu maior e os 4 apps pequenos no canto direito;
  - o usuario, "Trocar senha" e "Sair" continuam na barra e a navegacao continua funcionando;
  - quem so tem permissao do painel de um app ve so aquele app na barra;
  - em tela estreita (tablet em pe, celular) a lista de apps da barra fica escondida e o layout antigo segue como estava;
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
  return {tabs: r('.tabsrow'), main: r('.main'), nav: r('.nav-item'), app: r('.side-app'), apps: r('.side-apps'), user: r('.topbar-user'),
          sair: r('[data-logout]'), nApps: [...document.querySelectorAll('.side-app')].filter(e => e.getBoundingClientRect().height > 0).length,
          ultimoApp: (() => { const l = [...document.querySelectorAll('.side-app')].pop(); return l ? Math.round(l.getBoundingClientRect().bottom) : null; })(),
          sairBottom: (() => { const e = document.querySelector('[data-logout]'); return e ? Math.round(e.getBoundingClientRect().bottom) : null; })(),
          alturaJanela: window.innerHeight};
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for rotulo, w, h, toque in (("tablet 1280x800 (toque)", 1280, 800, True), ("desktop 1440x860 (mouse)", 1440, 860, False)):
        print(f"== {rotulo}")
        page = abre(browser, w, h, toque)
        m = page.evaluate(MEDE)
        conf(m["tabs"] and m["tabs"]["x"] == 0 and 220 <= m["tabs"]["w"] <= 300, "a barra do menu e uma coluna a esquerda", str(m["tabs"]))
        conf(m["main"] and m["main"]["x"] >= m["tabs"]["w"] - 2 and m["main"]["y"] == 0, "o conteudo fica ao lado, desde o topo", str(m["main"]))
        conf(m["nav"]["fonte"] >= 15 and m["nav"]["h"] >= 46, "o menu principal e grande (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
        conf(m["app"]["fonte"] <= 13 and m["app"]["fonte"] < m["nav"]["fonte"], "os apps sao menores que o menu (letra %.1f px)" % m["app"]["fonte"])
        conf(m["nApps"] == 4, "os 4 apps aparecem na barra", str(m["nApps"]))
        if toque:
            conf(m["app"]["h"] >= 44, "o atalho de app tem pelo menos 44 px de altura no toque (%d)" % m["app"]["h"])
        conf(m["ultimoApp"] <= m["alturaJanela"] and m["sairBottom"] <= m["alturaJanela"],
             "apps e o botao Sair cabem na altura da tela (%s / %s de %s px)" % (m["ultimoApp"], m["sairBottom"], m["alturaJanela"]))
        links = page.evaluate("() => [...document.querySelectorAll('.side-app')].map(a => a.getAttribute('href') + '|' + a.textContent.trim())")
        conf(links == ["./AEpecuaria.html|Pecuária", "./AECana.html|Cana", "./AECereais.html|Cereais", "./AECombustivel.html|Combustível"],
             "cada app aponta para o arquivo certo", str(links))
        conf(m["user"] is not None and page.locator("[data-trocar-senha-abrir]").count() == 1 and page.locator("[data-logout]").count() == 1,
             "usuario, Trocar senha e Sair continuam na barra")
        icones = page.evaluate("() => [...document.querySelectorAll('.nav-item')].map(b => b.querySelector('svg').innerHTML)")
        conf(len(icones) >= 8 and len(set(icones)) == len(icones), "cada item do menu tem um icone proprio (%d itens)" % len(icones))
        # navegar pelo menu continua funcionando
        for chave in ("financeiro", "resultados", "contas", "painel"):
            page.click(f"[data-nav='{chave}']")
            page.wait_for_timeout(150)
            conf(page.evaluate("() => state.page") == chave, f"clicar em {chave} troca de tela")
        # permissao: so o painel da Pecuaria
        page.evaluate("""() => { state.perfil = {...state.perfil, papel: 'funcionario', permissoes: {matriz_painel_pecuaria: 'visualizar'}}; render(); }""")
        page.wait_for_timeout(200)
        nomes = page.evaluate("() => [...document.querySelectorAll('.side-app')].map(a => a.textContent.trim())")
        conf(nomes == ["Pecuária"], "sem permissao dos outros paineis, so o app liberado aparece na barra", str(nomes))
        page.context.close()

    print("== tablet menor 1180x820 (toque): barra de cima com menu maior e apps pequenos a direita")
    page = abre(browser, 1180, 820, True)
    m = page.evaluate(MEDE)
    conf(m["tabs"]["y"] >= 55 and m["tabs"]["w"] >= 1100, "a barra do menu continua em cima, na largura toda", str(m["tabs"]))
    conf(m["nav"]["fonte"] >= 14.5 and m["nav"]["h"] >= 44, "o menu principal esta maior que antes (letra %.1f px, botao %d px)" % (m["nav"]["fonte"], m["nav"]["h"]))
    conf(m["nApps"] == 4 and m["app"]["fonte"] <= 12.5 and m["app"]["x"] > 590, "os 4 apps aparecem pequenos no canto direito da barra (letra %.1f px)" % m["app"]["fonte"], str(m["app"]))
    conf(m["app"]["h"] >= 44, "o atalho de app tem pelo menos 44 px no toque (%d)" % m["app"]["h"])
    page.context.close()

    for rotulo, w, h, toque in (("tablet em pe 820x1180", 820, 1180, True), ("celular 390x800", 390, 800, True)):
        print(f"== {rotulo}")
        page = abre(browser, w, h, toque)
        m = page.evaluate(MEDE)
        if w >= 760:
            conf(m["nApps"] == 4, "os apps pequenos aparecem na barra de cima", str(m["nApps"]))
        else:
            conf(m["apps"] is None or m["apps"]["display"] == "none" or m["apps"]["h"] == 0, "no celular a lista de apps da barra fica escondida", str(m["apps"]))
        top = page.evaluate("() => { const t = document.querySelector('.topbar'); const b = t.getBoundingClientRect(); return {x: b.x, y: b.y, w: Math.round(b.width), h: Math.round(b.height)}; }")
        conf(top["y"] == 0 and top["w"] >= w - 2 and top["h"] < 120, "a barra de cima continua em cima, na largura toda", str(top))
        page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
