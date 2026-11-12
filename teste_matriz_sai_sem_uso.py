"""
AE Matriz sai sozinho depois de 20 minutos sem uso (12/11/2026, decisao do Eduardo: o financeiro nao pode ficar a mostra
num computador do escritorio esquecido aberto).
  - ao abrir: ultimo uso ha mais de 20 min e login guardado -> sai (so deste aparelho: signOut scope 'local'), apaga o
    login guardado e mostra o aviso na tela de login; ultimo uso recente ou desconhecido -> abre normal;
  - aberto: ao voltar para a aba (e a cada 30 s) confere; parado mais de 20 min -> volta para o login com o aviso;
    usando (toque, tecla, rolagem), nao sai;
  - a hora do ultimo uso e do APARELHO (core.js, os 5 apps marcam): usar a Pecuaria no mesmo navegador conta como uso,
    e a Pecuaria nunca sai sozinha;
  - entrar de novo depois de sair funciona e o aviso some.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {"profiles": [ADMIN]}
CHAVE_SESSAO = "sb-kmkystqgpvmzrccxvyaz-auth-token"
AVISO = "20 minutos sem uso"

# signOut do stub nao apaga nada: aqui ele anota com que opcoes foi chamado e tira a sessao, como a biblioteca de verdade
ANOTA_SAIDA = """
(function(){
  const s = window.supabase, orig = s.createClient;
  s.createClient = function(){
    const c = orig.apply(this, arguments);
    c.auth.signOut = function(o){ (window.__SAIDAS__ = window.__SAIDAS__ || []).push(o || null); window.__SESSAO__ = null; return Promise.resolve({error: null}); };
    return c;
  };
})();
"""

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, app, minutos_atras, sessao_guardada=True):
    ctx = browser.new_context()
    page = ctx.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/fonts.g*/**", lambda r: r.abort())
    page.add_init_script(STUB)
    page.add_init_script(ANOTA_SAIDA)
    prep = ""
    if minutos_atras is not None:
        prep += f"localStorage.setItem('ae_ultimo_uso_v1', String(Date.now() - {minutos_atras} * 60000));"
    if sessao_guardada:
        prep += f"localStorage.setItem('{CHAVE_SESSAO}', JSON.stringify({{user:{{id:'u1'}}, access_token:'x'}}));"
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};"
        f"if(!sessionStorage.getItem('__prep')){{ sessionStorage.setItem('__prep','1'); localStorage.clear(); {prep} }}"
    )
    page.goto("file://" + str(REPO / app))
    page.wait_for_timeout(1300)
    return ctx, page, erros


def na_tela_de_login(page):
    return page.locator("[data-login-form]").count() == 1


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    print("\n  AO ABRIR")
    ctx, page, erros = abre(browser, "AEMatriz.html", 21)
    conf(na_tela_de_login(page), "parado ha 21 min, login guardado: abre na tela de login")
    conf(AVISO in page.locator(".login-error").inner_text() if page.locator(".login-error").count() else False,
         "mostra o aviso de que saiu por falta de uso")
    conf(page.evaluate("JSON.stringify(window.__SAIDAS__ || [])") == '[{"scope":"local"}]', "encerra so a sessao deste aparelho (scope local)",
         page.evaluate("JSON.stringify(window.__SAIDAS__ || [])"))
    conf(page.evaluate(f"localStorage.getItem('{CHAVE_SESSAO}')") is None, "apaga o login guardado no aparelho")

    print("\n  ENTRAR DE NOVO")
    page.evaluate("window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'}")
    page.locator("[data-login-usuario]").fill("chefe")
    page.locator("[data-login-form] input[type=password]").fill("senha-de-teste")
    page.locator("[data-login-form] input[type=password]").press("Enter")
    page.wait_for_timeout(1200)
    conf(not na_tela_de_login(page) and page.evaluate("!!(state.session && state.perfil)"), "entra de novo normalmente")
    conf(page.locator(".login-error").count() == 0, "o aviso some depois de entrar")
    page.evaluate("conferirTempoSemUso()")
    page.wait_for_timeout(300)
    conf(not na_tela_de_login(page), "digitar a senha conta como uso: nao sai logo depois de entrar")
    conf(not erros, "sem erro de JavaScript", "; ".join(erros[:2]))
    ctx.close()

    ctx, page, erros = abre(browser, "AEMatriz.html", 5)
    conf(not na_tela_de_login(page) and page.evaluate("!!state.perfil"), "parado ha 5 min: abre normal, logado")
    conf(page.evaluate("(window.__SAIDAS__ || []).length") == 0, "e nao encerra a sessao")

    print("\n  ABERTO")
    page.evaluate("localStorage.setItem('ae_ultimo_uso_v1', String(Date.now() - 21 * 60000))")
    page.mouse.click(5, 300)
    page.evaluate("document.dispatchEvent(new Event('visibilitychange'))")
    page.wait_for_timeout(400)
    conf(not na_tela_de_login(page), "usando (um toque) depois de muito tempo: nao sai")
    uso = page.evaluate("Number(localStorage.getItem('ae_ultimo_uso_v1'))")
    conf(page.evaluate("Date.now()") - uso < 5000, "o toque marca a hora do ultimo uso")

    page.evaluate("localStorage.setItem('ae_ultimo_uso_v1', String(Date.now() - 21 * 60000))")
    page.evaluate("document.dispatchEvent(new Event('visibilitychange'))")
    page.wait_for_timeout(600)
    conf(na_tela_de_login(page), "parado ha 21 min com o app aberto: ao voltar para a aba, pede o login de novo")
    conf(AVISO in (page.locator(".login-error").inner_text() if page.locator(".login-error").count() else ""), "com o aviso")
    conf(page.evaluate("JSON.stringify(window.__SAIDAS__ || [])") == '[{"scope":"local"}]', "e encerra so a sessao deste aparelho")
    conf(not erros, "sem erro de JavaScript", "; ".join(erros[:2]))
    ctx.close()

    ctx, page, erros = abre(browser, "AEMatriz.html", None)
    conf(not na_tela_de_login(page), "sem hora de uso guardada (primeira vez): abre normal")
    ctx.close()

    ctx, page, erros = abre(browser, "AEMatriz.html", 30, sessao_guardada=False)
    conf(page.evaluate("(window.__SAIDAS__ || []).length") == 0, "sem login guardado: nao ha o que encerrar")
    ctx.close()

    print("\n  OUTROS APPS")
    for app in ("AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"):
        ctx, page, erros = abre(browser, app, 120)
        conf(not na_tela_de_login(page) and page.evaluate("(window.__SAIDAS__ || []).length") == 0,
             f"{app}: parado ha 2 h, nao sai sozinho (so o Matriz sai)")
        page.mouse.click(5, 300)
        page.wait_for_timeout(200)
        uso = page.evaluate("Number(localStorage.getItem('ae_ultimo_uso_v1'))")
        conf(page.evaluate("Date.now()") - uso < 5000, f"{app}: um toque marca a hora do ultimo uso do aparelho")
        conf(not erros, f"{app}: sem erro de JavaScript", "; ".join(erros[:2]))
        ctx.close()

    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
