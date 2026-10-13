"""
Offline dos apps (sw.js) e botao de voltar ao Painel.

Sobe um servidor local (service worker exige http://localhost, nao
file://), abre cada app com internet, corta a internet e recarrega: o app
tem que abrir do cache. O CDN do Supabase e servido pelo proprio teste
(com o stub no lugar da biblioteca) enquanto ha "internet" e bloqueado
depois - e o caso real: offline, o script do CDN so existe se o service
worker tiver guardado.

Antes da v5 do sw.js o CDN nunca era guardado e este teste falhava.

Na recarga offline o getSession() da biblioteca fica pendurado de
proposito: e o que o supabase-js real faz com o token vencido (>1 h) e
sem rede -- tenta renovar por ~25 s (medido: 25,5 s) e depois devolve
"sem sessao". O app tem que abrir mesmo assim, rapido, com a sessao e o
perfil guardados no aparelho.
"""
import time
import functools, http.server, json, os, socketserver, sys, threading
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


class Quieto(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


srv = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(Quieto, directory=str(REPO)))
porta = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://localhost:{porta}"

APPS = [
    ("AEpecuaria.html", "AE Pecuária"),
    ("AECana.html", "AE Cana"),
    ("AECereais.html", "AE Cereais"),
    ("AECombustivel.html", "AE Combustível"),
    ("AEMatriz.html", None),
]

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arquivo, nome in APPS:
        print(f"\n  {arquivo}")
        ctx = browser.new_context()
        online = {"v": True}

        def cdn(route):
            if online["v"]:
                route.fulfill(status=200, body=STUB, headers={
                    "content-type": "application/javascript", "access-control-allow-origin": "*"})
            else:
                route.abort("internetdisconnected")
        ctx.route("**/cdn.jsdelivr.net/**", cdn)
        ctx.route("**/fonts.googleapis.com/**", lambda r: r.abort() if not online["v"] else r.fulfill(status=200, body="", headers={"content-type": "text/css"}))
        ctx.route("**/fonts.gstatic.com/**", lambda r: r.abort())
        # stub so define window.supabase se o CDN nao tiver definido (no
        # teste o "CDN" ja entrega o stub; isto so injeta os dados).
        ctx.add_init_script(
            f"window.__DB__ = {json.dumps(DB)};"
            f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};"
        )
        page = ctx.new_page()
        erros = []
        page.on("pageerror", lambda e: erros.append(str(e)))

        page.goto(f"{BASE}/{arquivo}")
        page.wait_for_function("navigator.serviceWorker && navigator.serviceWorker.ready.then(()=>true)", timeout=10000)
        page.evaluate("navigator.serviceWorker.ready")
        # segunda carga: agora a pagina e controlada pelo service worker
        page.reload()
        page.wait_for_timeout(1500)
        controlada = page.evaluate("!!navigator.serviceWorker.controller")
        conf(controlada, "service worker controla a pagina")

        online["v"] = False
        ctx.set_offline(True)
        # sessao guardada no aparelho (formato do supabase-js) e getSession
        # pendurado, como o supabase-js real com o token vencido e sem rede
        ctx.add_init_script("""
          localStorage.setItem('sb-kmkystqgpvmzrccxvyaz-auth-token',
            JSON.stringify({access_token:'x', refresh_token:'rt', expires_at:1, user:{id:'u1'}}));
          Object.defineProperty(window, 'supabase', {configurable:true,
            get(){ return this.__sb; },
            set(v){ const orig = v.createClient; v.createClient = (...a)=>{ const c = orig(...a);
              c.auth.getSession = ()=>new Promise(()=>{}); return c; }; this.__sb = v; }});
        """)
        erros.clear()
        try:
            t0 = time.time()
            page.reload(timeout=15000)
            seletor = 'a[href="./AEMatriz.html"]' if nome else '.app-card'
            page.wait_for_selector(seletor, timeout=5000)
            demorou = time.time() - t0
            abriu = True
        except Exception as e:
            abriu = False
            erros.append(str(e))
        tem_supabase = abriu and page.evaluate("typeof window.supabase === 'object' && !!window.supabase")
        conf(abriu and tem_supabase, "offline: abre do cache, com a biblioteca do Supabase", " | ".join(erros[:2]))
        conf(abriu and demorou < 3, "offline com login vencido: abre em menos de 3 s (sem esperar a renovação)",
             f"{demorou:.1f} s" if abriu else "não abriu")
        if nome:
            texto = page.inner_text("body") if abriu else ""
            conf(nome in texto, f"offline: a tela do app aparece ({nome})", texto[:120].replace("\n", " "))
            botao = page.locator('a[href="./AEMatriz.html"]')
            conf(abriu and botao.count() == 1, "tem o botão ← Painel apontando pro AE Matriz")
        else:
            links = page.evaluate("APPS_REGISTRO.map(a=>a.url)") if abriu else []
            conf(links and all(u.startswith("./") for u in links),
                 "cards do Painel abrem o app na mesma janela (link relativo)", str(links))
        ctx.close()
    browser.close()
srv.shutdown()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
