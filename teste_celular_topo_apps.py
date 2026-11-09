"""
Topo dos apps no celular (pedido do Eduardo, 09/11/2026: "pode fazer o Combustivel igual aos outros"). No AE Combustivel a
marca, os botoes e os 10 itens do menu ficavam numa faixa so de ~1.860 px: o menu comecava fora da tela (so arrastando a
faixa azul) e o Sair saia cortado. Agora os quatro apps (Pecuaria, Cana, Cereais, Combustivel) tem o mesmo desenho no
celular. Prova, em 320, 360 e 390 px:
  - "← Painel", "Trocar senha" e "Sair" aparecem inteiros na tela;
  - a faixa de cima (marca e botoes) nao rola de lado;
  - o primeiro item do menu aparece inteiro na tela, logo abaixo dos botoes;
  - o menu fica numa faixa propria que se arrasta para o lado quando nao cabe;
  - tocar num item do menu troca de tela;
  - a pagina nao rola de lado.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
APPS = ("AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html")
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


MEDE = """() => {
  const caixa = s => { const e = document.querySelector(s); if(!e) return null; const b = e.getBoundingClientRect();
    return {x: b.x, right: b.right, y: b.y, bottom: b.bottom}; };
  const topo = document.querySelector('.topbar') || document.querySelector('.sidebar');
  const menu = document.querySelector('.tabsrow') || document.querySelector('.sidebar nav');
  const itens = [...menu.querySelectorAll('.nav-item')];
  return {largura: document.documentElement.clientWidth, painel: caixa('a.btn-sair'), senha: caixa('[data-trocar-senha-abrir]'),
          sair: caixa('[data-logout]'), primeiro: itens[0] ? (b => ({x: b.x, right: b.right, y: b.y}))(itens[0].getBoundingClientRect()) : null,
          nItens: itens.length, topoRola: topo.scrollWidth > topo.clientWidth + 1 && getComputedStyle(topo).overflowX !== 'visible',
          menuRolavel: ['auto', 'scroll'].includes(getComputedStyle(menu).overflowX),
          menuCabe: menu.scrollWidth <= menu.clientWidth + 1,
          paginaRola: document.documentElement.scrollWidth > document.documentElement.clientWidth};
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arq in APPS:
        for w in (320, 360, 390):
            print(f"== {arq} {w} px")
            ctx = browser.new_context(viewport={"width": w, "height": 800}, has_touch=True, is_mobile=True)
            page = ctx.new_page()
            erros = []
            page.on("pageerror", lambda e: None if "ServiceWorker" in str(e) else erros.append(str(e)))
            page.on("dialog", lambda d: d.dismiss())
            page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
            page.add_init_script(STUB)
            page.add_init_script(f"window.__DB__ = {json.dumps({'profiles': [ADMIN]})}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
            page.goto("file://" + str(REPO / arq))
            page.wait_for_function("() => document.querySelector('.nav-item') !== null", timeout=30000)
            page.wait_for_timeout(500)
            m = page.evaluate(MEDE)
            inteiro = lambda b: b is not None and b["x"] >= -0.5 and b["right"] <= m["largura"] + 0.5
            conf(all(inteiro(m[k]) for k in ("painel", "senha", "sair")), "← Painel, Trocar senha e Sair inteiros na tela",
                 str({k: m[k] for k in ("painel", "senha", "sair")}))
            conf(not m["topoRola"], "a faixa de cima nao rola de lado")
            conf(inteiro(m["primeiro"]) and m["primeiro"]["y"] >= m["sair"]["bottom"] - 1, "o primeiro item do menu aparece inteiro, abaixo dos botoes", str(m["primeiro"]))
            conf(m["menuCabe"] or m["menuRolavel"], "o menu cabe ou se arrasta para o lado na faixa propria")
            conf(not m["paginaRola"], "a pagina nao rola de lado")
            if m["nItens"] >= 2:
                antes = page.evaluate("() => state.page")
                menu = ".tabsrow .nav-item" if page.locator(".tabsrow").count() else ".sidebar nav .nav-item"
                alvo = page.locator(menu).nth(1)
                alvo.scroll_into_view_if_needed()
                alvo.tap()
                page.wait_for_timeout(300)
                conf(page.evaluate("() => state.page") != antes, "tocar no 2o item do menu troca de tela")
            conf(not erros, "sem erro de JavaScript", str(erros))
            ctx.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
