"""
Nucleo comum (core.js) e o cache offline do sw.js: o app aberto SEM internet tem que juntar o HTML com o nucleo da MESMA versao.

O HTML chama core.js?v=<impressao digital>. O service worker guarda cada versao com o ?v= no endereco; sem cuidado, a busca no
cache que ignora o ?v= devolve a copia mais ANTIGA (a primeira que foi guardada), e depois de uma atualizacao o app offline
rodaria o HTML novo com o nucleo velho. Prova, com um servidor local e service worker de verdade:
  - versao A publicada: o app abre com o nucleo A;
  - versao B publicada (HTML com outro ?v=, core.js com outro conteudo): com internet o app abre com o nucleo B;
  - o cache nao fica com a copia velha do core.js (so a do ?v= atual);
  - SEM internet o app abre com o nucleo B (nao com o A), e o nucleo da lavoura tambem carrega.
"""
import functools
import http.server
import json
import os
import re
import shutil
import socketserver
import sys
import tempfile
import threading
from pathlib import Path

os.environ.setdefault("PW_EXPERIMENTAL_SERVICE_WORKER_NETWORK_EVENTS", "1")
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {"profiles": [ADMIN]}
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


# o "site": uma copia do necessario, para poder publicar versoes diferentes do core.js
SITE = Path(tempfile.mkdtemp())
for nome in ["AECana.html", "core.js", "core_lavoura.js", "sw.js", "manifest_cana.json"] + [p.name for p in REPO.glob("icon-cana-*.png")]:
    shutil.copy(REPO / nome, SITE / nome)
CORE_ORIGINAL = (REPO / "core.js").read_text(encoding="utf-8")
HTML_ORIGINAL = (REPO / "AECana.html").read_text(encoding="utf-8")


def publica(marca, versao):
    (SITE / "core.js").write_text(CORE_ORIGINAL + f"\nwindow.__NUCLEO_MARCA__ = '{marca}';\n", encoding="utf-8")
    (SITE / "AECana.html").write_text(re.sub(r"core\.js\?v=[0-9a-f]+", f"core.js?v={versao}", HTML_ORIGINAL), encoding="utf-8")


class Quieto(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


srv = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(Quieto, directory=str(SITE)))
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://localhost:{srv.server_address[1]}"

publica("A", "aaaaaaaaaa")
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    ctx = browser.new_context()
    online = {"v": True}
    ctx.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=STUB, headers={
        "content-type": "application/javascript", "access-control-allow-origin": "*"}) if online["v"] else r.abort("internetdisconnected"))
    ctx.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body="", headers={"content-type": "text/css"}) if online["v"] else r.abort())
    ctx.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())

    page.goto(f"{BASE}/AECana.html")
    page.evaluate("navigator.serviceWorker.ready")
    page.reload()
    page.wait_for_timeout(1500)
    conf(page.evaluate("!!navigator.serviceWorker.controller"), "service worker controla a pagina")
    conf(page.evaluate("window.__NUCLEO_MARCA__") == "A", "com internet, versao A: o app abre com o nucleo A", str(page.evaluate("window.__NUCLEO_MARCA__")))

    publica("B", "bbbbbbbbbb")
    page.reload()
    page.wait_for_timeout(1500)
    conf(page.evaluate("window.__NUCLEO_MARCA__") == "B", "com internet, versao B publicada: o app abre com o nucleo B", str(page.evaluate("window.__NUCLEO_MARCA__")))
    guardados = page.evaluate("caches.open('ae-v5').then(c => c.keys()).then(ks => ks.map(k => k.url).filter(u => /\\/core\\.js/.test(u)))")
    conf(len(guardados) == 1 and guardados[0].endswith("core.js?v=bbbbbbbbbb"),
         "o cache guarda so a copia do core.js do ?v= atual (a velha saiu)", str(guardados))

    online["v"] = False
    ctx.set_offline(True)
    erro = ""
    try:
        page.reload(timeout=15000)
        page.wait_for_timeout(1200)
    except Exception as e:
        erro = str(e)[:150]
    marca = page.evaluate("window.__NUCLEO_MARCA__") if not erro else None
    conf(marca == "B", "SEM internet: o app abre com o nucleo B (nao com o velho)", f"marca={marca} {erro}")
    conf(not erro and page.evaluate("typeof PageEstoqueInsumos") == "function", "SEM internet: o nucleo da lavoura tambem carrega")
    browser.close()
srv.shutdown()
shutil.rmtree(SITE, ignore_errors=True)

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
