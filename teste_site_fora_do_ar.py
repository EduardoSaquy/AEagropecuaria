"""
Site fora do ar (sw.js): quem ja usa o app continua abrindo.

Quando o GitHub Pages sai do ar (troca de repositorio, queda do GitHub) o
site responde 404 ou 503 NA HORA. O sw.js so caia para a copia guardada se a
rede FALHASSE ou demorasse mais de 4 s; uma resposta de erro rapida era
entregue como pagina, e todo mundo via "404" ate com o app instalado.

Sobe um servidor local que alterna entre "normal", "404", "503" e "novo" (a
mesma pagina com uma marca, para provar que online a versao nova continua
entrando na hora). O CDN do Supabase e servido pelo proprio teste, como em
teste_offline.py.
"""
import functools
import http.server
import json
import os
import socketserver
import sys
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
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

modo = {"v": "normal"}
PAGINA_404 = b"<html><body><h1>404</h1><p>There isn't a GitHub Pages site here.</p></body></html>"

class Site(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def _erro(self, codigo, corpo):
        self.send_response(codigo)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)
    def do_GET(self):
        if modo["v"] == "404": return self._erro(404, PAGINA_404)
        if modo["v"] == "503": return self._erro(503, b"<html><body>Service Unavailable</body></html>")
        if modo["v"] == "novo" and self.path.split("?")[0].endswith(".html"):
            arq = Path(REPO) / self.path.split("?")[0].lstrip("/")
            if arq.exists():
                corpo = arq.read_bytes().replace(b"</body>", b"<script>window.__VERSAO_NOVA = true;</script></body>", 1)
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(corpo)))
                self.end_headers()
                self.wfile.write(corpo)
                return
        return super().do_GET()

srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), functools.partial(Site, directory=str(REPO)))
BASE = f"http://localhost:{srv.server_address[1]}"
threading.Thread(target=srv.serve_forever, daemon=True).start()

exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    for arquivo, seletor in (("AEMatriz.html", ".app-card"), ("AEpecuaria.html", "body")):
        print(f"\n  {arquivo}")
        modo["v"] = "normal"
        ctx = browser.new_context()
        ctx.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=STUB, headers={
            "content-type": "application/javascript", "access-control-allow-origin": "*"}))
        ctx.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body="", headers={"content-type": "text/css"}))
        ctx.route("**/fonts.gstatic.com/**", lambda r: r.abort())
        ctx.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        page = ctx.new_page()
        page.goto(f"{BASE}/{arquivo}")
        page.wait_for_function("navigator.serviceWorker && navigator.serviceWorker.ready.then(()=>true)", timeout=10000)
        page.evaluate("navigator.serviceWorker.ready")
        page.reload()                      # agora a pagina e controlada pelo service worker
        page.wait_for_selector(seletor, timeout=8000)
        conf(page.evaluate("!!navigator.serviceWorker.controller"), "o service worker controla a pagina (copia guardada)")
        titulo_ok = page.title()

        for rotulo, m in (("404 (site fora do ar)", "404"), ("503 (GitHub com problema)", "503")):
            modo["v"] = m
            resp = page.reload(wait_until="domcontentloaded")
            try:
                page.wait_for_selector(seletor, timeout=6000)
                abriu = True
            except Exception:
                abriu = False
            texto = page.inner_text("body")[:80].replace("\n", " ")
            conf(abriu and "GitHub Pages site" not in texto and "Service Unavailable" not in texto and page.title() == titulo_ok,
                 f"site respondendo {rotulo}: o app abre da copia guardada, nao a pagina de erro", f"status={resp.status if resp else None} texto='{texto}'")

        # a pagina de erro nao pode ter sobrescrito a copia guardada
        modo["v"] = "normal"
        page.reload()
        page.wait_for_selector(seletor, timeout=8000)
        guardada = page.evaluate("""async () => { const r = await caches.match('/%s', {ignoreSearch:true}); return r ? [r.status, (await r.text()).length] : null; }""" % arquivo)
        conf(guardada and guardada[0] == 200 and guardada[1] > 20000, "a copia guardada continua o app (a pagina de erro nao a sobrescreveu)", str(guardada))

        # endereco que nao esta guardado continua dando 404 de verdade
        modo["v"] = "404"
        status = page.evaluate("fetch('/pagina-que-nunca-existiu.html').then(r => r.status)")
        conf(status == 404, "endereco que nunca foi guardado continua respondendo 404 (sem copia, entrega o erro)", str(status))

        # online, a versao nova continua entrando na hora (rede primeiro)
        modo["v"] = "novo"
        page.reload()
        page.wait_for_selector(seletor, timeout=8000)
        conf(page.evaluate("window.__VERSAO_NOVA === true"), "com o site no ar, a versao nova entra na hora (rede primeiro, como antes)")
        ctx.close()
    browser.close()
srv.shutdown()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
