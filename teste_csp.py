"""
Politica de seguranca de conteudo (CSP) nos cinco apps (revisao geral de 05/11/2026, seguranca: um script
injetado na pagina podia mandar os dados para qualquer endereco). Cada app so pode falar com:
  . o proprio Supabase do projeto (dados e login); a biblioteca do Supabase vem do proprio site (vendor/, 12/11/2026),
    entao nenhum script de fora e liberado;
  . as fontes do Google (css e arquivos de fonte).
Prova (servindo os arquivos por HTTP, como no site, porque em file:// o 'self' nao vale):
  - a politica esta no <head> dos cinco apps, sem 'unsafe-eval' e sem curinga em connect-src;
  - os apps abrem e percorrem as telas SEM nenhuma violacao da propria politica;
  - a politica de fato barra: um fetch para outro endereco, uma imagem de fora e um script de fora falham.
"""
import functools
import http.server
import json
import re
import sys
import threading
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
APPS = ("AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html")
SUPABASE = "https://kmkystqgpvmzrccxvyaz.supabase.co"
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}

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


class ComCors(Quieto):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()


import base64
import tempfile
FORA = Path(tempfile.mkdtemp())
(FORA / "x.js").write_text("window.__scriptDeFora = 'rodou';")
(FORA / "x.json").write_text('{"ok":1}')
(FORA / "x.png").write_bytes(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
(FORA / "controle.html").write_text("<!doctype html><html><head><meta charset=utf-8></head><body>controle sem politica</body></html>")
servidor_fora = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(ComCors, directory=str(FORA)))
threading.Thread(target=servidor_fora.serve_forever, daemon=True).start()
URL_FORA = f"http://127.0.0.1:{servidor_fora.server_address[1]}"
servidor = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quieto, directory=str(REPO)))
porta = servidor.server_address[1]
threading.Thread(target=servidor.serve_forever, daemon=True).start()

print("== a politica esta nos cinco apps")
for app in APPS:
    html = (REPO / app).read_text(encoding="utf-8")
    m = re.search(r'<meta http-equiv="Content-Security-Policy" content="([^"]+)"', html)
    conf(bool(m), f"{app}: tem a politica no head")
    if not m:
        continue
    pol = {p.strip().split(" ")[0]: p.strip().split(" ")[1:] for p in m.group(1).split(";") if p.strip()}
    conf("'unsafe-eval'" not in pol.get("script-src", []), f"{app}: sem 'unsafe-eval'")
    conn = pol.get("connect-src", [])
    conf(SUPABASE in conn and not any(c in ("*", "https:", "http:", "data:") for c in conn), f"{app}: connect-src so o Supabase do projeto", str(conn))
    conf(pol.get("default-src") == ["'none'"] and pol.get("object-src") == ["'none'"], f"{app}: default-src e object-src 'none'")
    conf(pol.get("script-src") == ["'self'", "'unsafe-inline'"] and "https://fonts.googleapis.com" in pol.get("style-src", []),
         f"{app}: nenhum script de fora (nem CDN); so as fontes do Google", str(pol.get("script-src")))
    conf('<script src="vendor/supabase-js-2.118.0.js"></script>' in html and "cdn.jsdelivr" not in html,
         f"{app}: a biblioteca do Supabase vem do proprio site")

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for app in APPS:
        print(f"== {app} abre e percorre as telas sem violar a politica")
        page = browser.new_context(service_workers="block").new_page()
        violacoes = []
        erros = []
        page.on("console", lambda m: violacoes.append(m.text) if ("Content Security Policy" in m.text or "Refused to" in m.text) else None)
        page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
        page.on("dialog", lambda d: d.dismiss())
        page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, content_type="text/css", body=""))
        page.route("**/fonts.gstatic.com/**", lambda r: r.fulfill(status=200, body=""))
        page.add_init_script(STUB)
        page.add_init_script(f"window.__DB__ = {json.dumps({'profiles': [ADMIN]})}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        page.goto(f"http://127.0.0.1:{porta}/{app}")
        page.wait_for_timeout(1500)
        if app == "AEMatriz.html":
            for pg in ("painel", "resultados", "financeiro", "contas", "financiamentos", "fazendas"):
                page.evaluate("(p) => { state.modal = null; state.page = p; render(); }", pg)
                page.wait_for_timeout(150)
            page.evaluate("() => { state.page = 'financeiro'; state.modal = {type:'lancamento'}; editDraft = {tipo:'despesa'}; render(); }")
            page.wait_for_timeout(250)
        conf(not violacoes, f"{app}: nenhuma violacao da propria politica", "; ".join(violacoes[:2])[:300])
        conf(not erros, f"{app}: sem erro de JS", "; ".join(erros[:2]))
        conf(page.locator("#root").count() == 1 and page.evaluate("() => document.getElementById('root').innerText.length") > 20, f"{app}: a tela desenha")

        if app == "AEMatriz.html":
            print("== a politica barra de verdade (endereco de fora = outra origem local, que responde)")
            SONDA = """async (fora) => {
              const r = {};
              try { const x = await fetch(fora + '/x.json'); r.fetch = 'passou'; } catch(e) { r.fetch = 'barrou'; }
              r.img = await new Promise(res => { const i = new Image(); i.onload = () => res('passou'); i.onerror = () => res('barrou'); i.src = fora + '/x.png'; });
              r.script = await new Promise(res => { const s = document.createElement('script'); s.src = fora + '/x.js'; s.onload = () => res('passou'); s.onerror = () => res('barrou'); document.head.appendChild(s); });
              const inline = document.createElement('script');
              inline.textContent = "try { new Function('return 1')(); window.__ev = 'passou'; } catch(e) { window.__ev = 'barrou'; }";
              document.head.appendChild(inline);
              r.eval = window.__ev;
              return r;
            }"""
            ctrl = browser.new_context(service_workers="block").new_page()
            ctrl.goto(f"{URL_FORA}/controle.html")
            rc = ctrl.evaluate(SONDA, URL_FORA)
            ctrl.close()
            conf(rc == {"fetch": "passou", "img": "passou", "script": "passou", "eval": "passou"},
                 "CONTROLE: numa pagina sem politica o endereco de fora responde e o eval roda", str(rc))
            violacoes.clear()
            rp = page.evaluate(SONDA, URL_FORA)
            conf(rp == {"fetch": "barrou", "img": "barrou", "script": "barrou", "eval": "barrou"},
                 "no app, fetch, imagem, script de fora e eval sao barrados", str(rp))
            conf(any("Content Security Policy" in v or "Refused" in v for v in violacoes),
                 "e o navegador registra a violacao da politica (foi ela que barrou, nao a rede)", str(violacoes[:2]))
        page.close()

    print("== a biblioteca DE VERDADE, servida pelo proprio site, carrega dentro da politica")
    for app in APPS:
        page = browser.new_context(service_workers="block").new_page()
        violacoes = []
        page.on("console", lambda m: violacoes.append(m.text) if ("Content Security Policy" in m.text or "Refused to" in m.text) else None)
        page.route("**/kmkystqgpvmzrccxvyaz.supabase.co/**", lambda r: r.abort())
        page.route("**/fonts.g*/**", lambda r: r.abort())
        page.goto(f"http://127.0.0.1:{porta}/{app}")
        page.wait_for_timeout(1200)
        r = page.evaluate("""async () => {
          const out = { tem: typeof supabase === 'object' && typeof supabase.createClient === 'function' };
          try {
            const c = supabase.createClient('https://kmkystqgpvmzrccxvyaz.supabase.co', 'chave-de-teste', { auth: { persistSession: false } });
            const s = await c.auth.getSession();
            out.sessao = !s.error && s.data && s.data.session === null;
            out.consulta = typeof c.from('x').select === 'function' && typeof c.rpc === 'function';
          } catch (e) { out.erro = String(e); }
          return out;
        }""")
        conf(r.get("tem") and r.get("sessao") and r.get("consulta"), f"{app}: supabase-js real carrega; createClient, getSession, from e rpc funcionam", str(r))
        conf(not violacoes, f"{app}: nenhuma violacao da politica com a biblioteca real", "; ".join(violacoes[:2])[:300])
        page.close()
    browser.close()
servidor.shutdown()
servidor_fora.shutdown()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
