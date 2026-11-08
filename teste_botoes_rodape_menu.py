"""
Botoes do rodape do menu lateral (pedido do Eduardo, 08/11/2026, print do iPad: "o trocar a senha esta fora").
Na coluna de 196 px (iPad deitado) "Trocar senha" e "Sair" ficavam lado a lado, 80 px cada; o texto (72 px no Chromium)
ja passava do espaco interno do botao e, no Safari do iPad, com a letra um pouco mais larga, saia pela borda.
Agora, nos apps de grade (Matriz, Pecuaria, Cana, Cereais), cada botao ocupa uma linha. Prova, nos 5 apps, em
1180, 1194, 1280 e 1440 px, com toque e com mouse:
  - cada botao do rodape (← Painel, Trocar senha, Sair) cabe dentro da coluna do menu;
  - o texto cabe no botao com folga de pelo menos 16 px (margem para a letra mais larga do Safari);
  - o texto fica numa linha so.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}
FOLGA = 16
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
  const col = document.querySelector('.sidebar') || document.querySelector('.tabsrow');
  const c = col.getBoundingClientRect();
  return [...document.querySelectorAll('[data-trocar-senha-abrir], [data-logout], a.btn-sair')].filter(e => e.offsetParent).map(e => {
    const b = e.getBoundingClientRect(); const r = document.createRange(); r.selectNodeContents(e);
    const linhas = r.getClientRects().length; const t = r.getBoundingClientRect();
    return {txt: e.textContent.trim(), bw: Math.round(b.width), tw: Math.round(t.width), linhas,
            dentro: b.left >= c.left - 0.5 && b.right <= c.right + 0.5};
  });
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arq in ("AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"):
        for w, h in ((1180, 820), (1194, 834), (1280, 800), (1440, 900)):
            for toque in (True, False):
                rotulo = f"{arq} {w}x{h} {'toque' if toque else 'mouse'}"
                ctx = browser.new_context(viewport={"width": w, "height": h}, has_touch=toque, is_mobile=toque)
                page = ctx.new_page()
                page.on("dialog", lambda d: d.dismiss())
                page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
                page.add_init_script(STUB)
                page.add_init_script(f"window.__DB__ = {json.dumps({'profiles': [ADMIN]})}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
                page.goto("file://" + str(REPO / arq))
                page.wait_for_function("() => document.querySelector('.nav-item') !== null", timeout=30000)
                page.wait_for_timeout(400)
                m = page.evaluate(MEDE)
                nomes = {b["txt"] for b in m}
                conf("Trocar senha" in nomes and "Sair" in nomes, f"{rotulo}: Trocar senha e Sair no rodape", str(m))
                conf(all(b["dentro"] for b in m), f"{rotulo}: os botoes cabem na coluna do menu", str(m))
                conf(all(b["tw"] + FOLGA <= b["bw"] for b in m), f"{rotulo}: o texto cabe no botao com {FOLGA} px de folga", str(m))
                conf(all(b["linhas"] == 1 for b in m), f"{rotulo}: o texto fica numa linha so", str(m))
                ctx.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
