"""
Topo dos apps no celular (pedido do Eduardo, 09/11/2026: "pode fazer o Combustivel igual aos outros"). No AE Combustivel a
marca, os botoes e os 10 itens do menu ficavam numa faixa so de ~1.860 px: o menu comecava fora da tela (so arrastando a
faixa azul) e o Sair saia cortado. Agora os quatro apps (Pecuaria, Cana, Cereais, Combustivel) tem o mesmo desenho no
celular. Depois ele pediu (09/11/2026) o menu dos "3 risquinhos" (☰), como o do AE Matriz, nos quatro. Prova, em 320, 360 e
390 px:
  - "← Painel", "Trocar senha" e "Sair" aparecem inteiros na tela;
  - a faixa de cima (marca e botoes) nao rola de lado;
  - abaixo dos botoes, o botao ☰ na largura toda, com o nome da tela atual; o menu comeca fechado (nenhum item na tela);
  - tocar no ☰ abre o menu numa coluna, todos os itens inteiros na largura da tela, e o botao diz que esta aberto;
  - a setinha de um item abre as sub-abas sem fechar o menu nem trocar de tela;
  - tocar num item troca de tela e fecha o menu; tocar no ☰ de novo fecha;
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
            botao = page.evaluate("""() => { const b = document.querySelector('[data-menu-celular]'); if(!b || !b.offsetParent) return null;
              const r = b.getBoundingClientRect(); return {x: r.x, right: r.right, y: r.y, w: r.width, h: r.height, texto: b.textContent.trim(),
              aberto: b.getAttribute('aria-expanded')}; }""")
            conf(botao and botao["w"] >= m["largura"] - 2 and botao["h"] >= 44 and botao["y"] >= m["sair"]["bottom"] - 1,
                 "botao ☰ na largura toda, abaixo dos botoes", str(botao))
            conf(botao and botao["texto"] and botao["texto"] != "Menu", "o botao ☰ diz a tela atual", str(botao))
            visiveis = lambda: page.evaluate("() => [...document.querySelectorAll('.nav-item')].filter(e => e.offsetParent).length")
            conf(botao and botao["aberto"] == "false" and visiveis() == 0, "o menu comeca fechado")
            page.tap("[data-menu-celular]")
            page.wait_for_timeout(200)
            itens = page.evaluate("""() => [...document.querySelectorAll('.nav-item')].filter(e => e.offsetParent).map(e => { const r = e.getBoundingClientRect();
              return {x: r.x, right: r.right, y: Math.round(r.y)}; })""")
            conf(len(itens) == m["nItens"] and all(inteiro(i) for i in itens) and len({i["y"] for i in itens}) == len(itens),
                 "tocar no ☰ abre o menu numa coluna, todos os itens inteiros", str(itens))
            conf(page.get_attribute("[data-menu-celular]", "aria-expanded") == "true", "o botao diz que o menu esta aberto")
            antes = page.evaluate("() => state.page")
            setas = page.locator("[data-nav-seta]")
            if setas.count():
                fechada = page.locator('[data-nav-seta][aria-expanded="false"]')
                if fechada.count():
                    fechada.first.tap()
                    page.wait_for_timeout(200)
                    conf(page.evaluate("() => document.documentElement.classList.contains('menu-celular-aberto')") and page.evaluate("() => state.page") == antes,
                         "a setinha abre as sub-abas sem fechar o menu nem trocar de tela")
            alvo = page.locator(".nav-item:not(.active)").filter(has=page.locator("svg")).first
            alvo.tap()
            page.wait_for_timeout(300)
            conf(page.evaluate("() => state.page") != antes, "tocar num item troca de tela")
            conf(visiveis() == 0 and page.get_attribute("[data-menu-celular]", "aria-expanded") == "false", "e fecha o menu")
            page.tap("[data-menu-celular]"); page.wait_for_timeout(150); page.tap("[data-menu-celular]"); page.wait_for_timeout(150)
            conf(visiveis() == 0, "tocar no ☰ de novo fecha o menu")
            conf(not page.evaluate("() => document.documentElement.scrollWidth > document.documentElement.clientWidth"), "a pagina nao rola de lado")
            conf(not erros, "sem erro de JavaScript", str(erros))
            ctx.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
