"""
Coluna do menu do AE Combustivel cabe na altura da tela (pedido do Eduardo, 09/11/2026, vendo os prints do iPad: com um
item aberto, Rateio, Alertas e Administracao so apareciam rolando a coluna; a pior faltava ~300 px). Prova, em 1180x820 e
1194x834 (iPad deitado), 1280x800 (tablet), 1366x768 (notebook) e 1440x900, com toque e com mouse:
  - com CADA item do menu aberto (as sub-abas dele a mostra), todos os itens e sub-abas aparecem sem rolar a coluna;
  - "← Painel", "Trocar senha" e "Sair" aparecem inteiros, dentro da tela e da coluna, com o texto numa linha;
  - no toque, item do menu com pelo menos 44 px de altura.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
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
  const n = document.querySelector('.sidebar nav'), s = document.querySelector('.sidebar').getBoundingClientRect();
  const bot = [...document.querySelectorAll('.sidebar-user-actions .btn-sair')].map(e => { const b = e.getBoundingClientRect();
    const r = document.createRange(); r.selectNodeContents(e);
    return {txt: e.textContent.trim(), ok: b.left >= s.left - 0.5 && b.right <= s.right + 0.5 && b.bottom <= innerHeight + 0.5,
            linhas: r.getClientRects().length}; });
  return {falta: n.scrollHeight - n.clientHeight, bot, alturaItem: Math.round(document.querySelector('.sidebar nav .nav-item').getBoundingClientRect().height)};
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for w, h in ((1180, 820), (1194, 834), (1280, 800), (1366, 768), (1440, 900)):
        for toque in (True, False):
            rotulo = f"{w}x{h} {'toque' if toque else 'mouse'}"
            print(f"== {rotulo}")
            ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=False)
            page = ctx.new_page()
            page.on("dialog", lambda d: d.dismiss())
            page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
            page.add_init_script(STUB)
            page.add_init_script(f"window.__DB__ = {json.dumps({'profiles': [ADMIN]})}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
            page.goto("file://" + str(REPO / "AECombustivel.html"))
            page.wait_for_function("() => document.querySelector('.nav-item') !== null", timeout=30000)
            page.wait_for_timeout(400)
            grupos = page.evaluate("() => gruposVisiveis().map(([k, g]) => [k, g.pages[0].key, g.pages.length])")
            conf(len(grupos) == 10, "os 10 itens do menu", str(grupos))
            piores = []
            for chave, pagina, n in grupos:
                page.evaluate("v => { state.page = v; guardarMenuAberto(currentGroupKey()); render(); }", pagina)
                page.wait_for_timeout(60)
                m = page.evaluate(MEDE)
                aberto = page.evaluate("() => document.querySelectorAll('.sidebar nav .nav-grupo.aberto').length")
                if n >= 2 and aberto != 1:
                    piores.append((chave, "nao abriu"))
                if m["falta"] > 0:
                    piores.append((chave, m["falta"]))
            conf(not piores, "com cada item aberto, o menu inteiro cabe sem rolar", str(piores))
            conf(all(b["ok"] and b["linhas"] == 1 for b in m["bot"]) and len(m["bot"]) == 3, "← Painel, Trocar senha e Sair inteiros, numa linha", str(m["bot"]))
            if toque:
                conf(m["alturaItem"] >= 44, "item do menu com 44 px no toque", str(m["alturaItem"]))
            ctx.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
