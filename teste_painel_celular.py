"""
Painel do AE Matriz no celular (pedido do Eduardo, 09/11/2026: "no celular os apps poderiam aparecer em icones pequenos,
nao tem necessidade de ter alertas no celular"; escolheu: some o aviso da copia de seguranca e os numeros; depois: icones maiores, um embaixo do outro).
Prova, em 320, 360, 390 e 760 px (celular):
  - as janelinhas (com descricao e numeros) e o aviso da copia de seguranca nao aparecem;
  - os 4 apps aparecem como icones grandes, um embaixo do outro, com o nome curto (sem "AE"), dentro da tela, alvo de toque >= 44 px;
  - cada icone e um link para o app certo, e tocar abre o app;
  - app "em breve" aparece apagado, sem link;
  - so os apps que a pessoa pode ver;
  - a pagina nao rola de lado.
E em 761, 1180 e 1440 px nada muda: janelinhas com numeros, aviso da copia, icones escondidos.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
ESPERADO = {"pecuaria": ("Pecuária", "./AEpecuaria.html"), "cana": ("Cana", "./AECana.html"),
            "cereais": ("Cereais", "./AECereais.html"), "combustivel": ("Combustível", "./AECombustivel.html")}
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, w, h, perfil=ADMIN, toque=True):
    ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
    page = ctx.new_page()
    erros = []
    page.on("pageerror", lambda e: None if "ServiceWorker" in str(e) else erros.append(str(e)))
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps({'profiles': [perfil]})}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => document.querySelector('.app-icones') !== null", timeout=30000)
    page.wait_for_timeout(400)
    return page, erros


MEDE = """() => {
  const vis = e => e && getComputedStyle(e).display !== 'none' && e.getBoundingClientRect().height > 0;
  const icones = [...document.querySelectorAll('.app-icone')].map(e => { const b = e.getBoundingClientRect();
    return {slug: e.dataset.appIcone, href: e.getAttribute('href'), nome: e.querySelector('.app-icone-nome').textContent.trim(),
            x: b.x, y: Math.round(b.y), w: b.width, img: e.querySelector('.app-icone-img').getBoundingClientRect().width, h: b.height, right: b.right, inativo: e.classList.contains('inativo')}; });
  return {cartoes: vis(document.querySelector('.painel-cartoes')), aviso: vis(document.querySelector('.aviso-copia')),
          temAviso: !!document.querySelector('.aviso-copia'), icones, iconesVis: vis(document.querySelector('.app-icones')),
          largura: document.documentElement.clientWidth,
          rola: document.documentElement.scrollWidth > document.documentElement.clientWidth};
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for w in (320, 360, 390, 760):
        print(f"== celular {w} px")
        page, erros = abre(browser, w, 800)
        m = page.evaluate(MEDE)
        conf(not m["cartoes"], "as janelinhas com descricao e numeros nao aparecem")
        conf(m["temAviso"] and not m["aviso"], "o aviso da copia de seguranca existe mas nao aparece no celular")
        conf(m["iconesVis"] and len(m["icones"]) == 4, "os 4 apps aparecem como icones", str(m["icones"]))
        ys = [i["y"] for i in m["icones"]]
        conf(len({round(i["x"]) for i in m["icones"]}) == 1 and ys == sorted(ys) and len(set(ys)) == 4, "um embaixo do outro", str(ys))
        conf(all(i["img"] >= 70 for i in m["icones"]), "icone grande (70 px ou mais)", str([i["img"] for i in m["icones"]]))
        conf(all(i["x"] >= 0 and i["right"] <= m["largura"] + 0.5 for i in m["icones"]), "todos dentro da tela", str(m["icones"]))
        conf(all(i["w"] >= 44 and i["h"] >= 44 for i in m["icones"]), "alvo de toque de pelo menos 44 px", str([(i["w"], i["h"]) for i in m["icones"]]))
        conf(all(ESPERADO[i["slug"]] == (i["nome"], i["href"]) for i in m["icones"]), "nome curto e link certo de cada app", str(m["icones"]))
        conf(not m["rola"], "a pagina nao rola de lado")
        conf(not erros, "sem erro de JavaScript", str(erros))
        page.context.close()

    print("== tocar no icone abre o app")
    page, erros = abre(browser, 390, 800)
    page.route("**/AECana.html", lambda r: r.fulfill(status=200, content_type="text/html", body="<title>cana</title>"))
    page.tap('[data-app-icone="cana"]')
    page.wait_for_url("**/AECana.html", timeout=10000)
    conf(page.url.endswith("AECana.html"), "tocar em Cana abre o AE Cana", page.url)
    page.context.close()

    print("== app em breve e permissao")
    page, erros = abre(browser, 390, 800)
    page.evaluate("() => { state.apps = state.apps.map(a => a.slug === 'combustivel' ? {...a, status: 'em_breve'} : a); render(); }")
    m = page.evaluate(MEDE)
    comb = [i for i in m["icones"] if i["slug"] == "combustivel"]
    conf(comb and comb[0]["inativo"] and comb[0]["href"] is None, "app em breve aparece apagado e sem link", str(comb))
    page.context.close()
    so_cana = {**ADMIN, "papel": "colaborador", "permissoes": {"matriz_painel_cana": "visualizar"}}
    page, erros = abre(browser, 390, 800, so_cana)
    m = page.evaluate(MEDE)
    conf([i["slug"] for i in m["icones"]] == ["cana"], "so aparecem os apps que a pessoa pode ver", str(m["icones"]))
    page.context.close()

    for w, toque in ((761, True), (1180, True), (1440, False)):
        print(f"== {w} px (nao muda)")
        page, erros = abre(browser, w, 820, toque=toque)
        m = page.evaluate(MEDE)
        conf(m["cartoes"] and not m["iconesVis"], "janelinhas aparecem, icones escondidos")
        conf(m["aviso"], "o aviso da copia de seguranca continua")
        conf(page.locator(".painel-cartoes .app-card-stats").count() == 4 or page.locator(".painel-cartoes .app-card-stat").count() > 0,
             "os numeros dos apps continuam")
        page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
