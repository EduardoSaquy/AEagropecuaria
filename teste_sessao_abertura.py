"""
Abertura do app, login e sessao, iguais nos cinco apps (core.js, 07/11/2026).

Cada app tinha a propria versao de initAuth/loadPerfil/fazerLogout/LoginPage/AguardandoLiberacao, e as copias tinham se afastado:
  - so o Matriz ignorava o evento TOKEN_REFRESHED da sessao. Nos outros quatro, a cada hora (quando o supabase-js renova o token) o
    app recarregava o perfil, redesenhava a tela e baixava os dados de novo: um formulario aberto com texto digitado e ainda nao
    salvo perdia o que estava escrito;
  - so o Matriz e a Pecuaria sabiam dizer "sem conexao" quando o aparelho abre pela primeira vez sem sinal; o Cana, o Cereais e o
    Combustivel diziam "ainda nao ha acesso liberado para esta conta" (mentira, e sem botao de tentar de novo);
  - o texto digitado no login e a mensagem de erro so eram escapados na Pecuaria.
Prova, nos cinco apps:
  - sem sessao, aparece a tela de login com o nome do app (e a frase do Matriz), e o que se digita volta inteiro, sem abrir atributo;
  - aparelho sem sinal, com login guardado mas sem perfil guardado: "sem conexao" com "Tentar novamente", que carrega o perfil e abre o app
    quando o sinal volta; com o sinal de volta e sem perfil no banco: "ainda nao ha perfil liberado";
  - renovacao do token (TOKEN_REFRESHED) nao redesenha a tela nem recarrega os dados: o texto digitado num formulario aberto fica;
  - sair volta para o login; o evento de sessao encerrada tambem;
  - pareceErroDeRede reconhece falta de sinal nos tres navegadores e nao confunde com erro de permissao.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
CHAVE = "sb-kmkystqgpvmzrccxvyaz-auth-token"
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}, "frentes": []}
APPS = [  # arquivo, nome na marca, tem a frase do Matriz
    ("AEMatriz.html", "AE Matriz", True),
    ("AEpecuaria.html", "AE Pecuária", False),
    ("AECana.html", "AE Cana", False),
    ("AECereais.html", "AE Cereais", False),
    ("AECombustivel.html", "AE Combustível", False),
]
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, arquivo, db, sessao=True, guardada=False, sem_rede=False):
    ctx = browser.new_context(viewport={"width": 1280, "height": 900})
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    ini = f"window.__DB__ = {json.dumps(db)};"
    ini += "window.__SESSAO__ = {user:{id:'u1'}, access_token:'a1'};" if sessao else "window.__SESSAO__ = null;"
    if guardada:   # login guardado no aparelho (formato do supabase-js)
        ini += f"localStorage.setItem({json.dumps(CHAVE)}, JSON.stringify({{access_token:'a1', refresh_token:'r', expires_at: 9999999999, user:{{id:'u1'}}}}));"
    if sem_rede:
        ini += "window.__SEM_REDE__ = true;"
    page.add_init_script(ini)
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.authChecked === true", timeout=30000)
    page.wait_for_timeout(500)
    return ctx, page


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arquivo, nome, slogan in APPS:
        print(f"\n== {arquivo}")

        # ---- sem sessao: tela de login
        ctx, page = abre(browser, arquivo, {"profiles": [ADMIN]}, sessao=False)
        t = page.inner_text("body")
        conf(nome in t and "Entrar" in t, f"sem sessao: tela de login com '{nome}'", t[:80].replace("\n", " "))
        conf(("Painel único" in t) == slogan, "a frase embaixo da marca so aparece no Matriz")
        sujo = 'x" data-invadiu="1" y="'
        page.evaluate("(s) => { state.loginDraft = {usuario: s, senha: s}; state.loginError = '<img data-invadiu=\"1\" src=x>'; render(); }", sujo)
        r = page.evaluate("(s) => ({u: document.querySelector('[data-login-usuario]').value, p: document.querySelector('[data-login-senha]').value, inv: document.querySelectorAll('[data-invadiu]').length})", sujo)
        conf(r["u"] == sujo and r["p"] == sujo and r["inv"] == 0, "login digitado e mensagem de erro entram como texto, sem abrir atributo", str(r))
        ctx.close()

        # ---- aparelho sem sinal na primeira abertura: "sem conexao" e "Tentar novamente"
        ctx, page = abre(browser, arquivo, {"profiles": [ADMIN]}, sessao=True, guardada=True, sem_rede=True)
        t = page.inner_text("body")
        conf("sem conexão com a internet" in t and "ainda não há um perfil" not in t, "sem sinal e sem perfil guardado: diz 'sem conexão' (e não 'sem acesso liberado')", t[:160].replace("\n", " "))
        conf(page.locator("[data-retry-perfil]").count() == 1, "tem o botão 'Tentar novamente'")
        page.evaluate("() => { window.__SEM_REDE__ = false; }")
        page.locator("[data-retry-perfil]").click()
        page.wait_for_function("() => state.perfil && state.perfil.papel === 'admin'", timeout=8000)
        page.wait_for_timeout(500)
        conf(page.locator("[data-retry-perfil]").count() == 0 and "sem conexão com a internet" not in page.inner_text("body"),
             "com o sinal de volta, 'Tentar novamente' carrega o perfil e abre o app")
        ctx.close()

        # ---- com sinal, mas a conta nao tem perfil
        ctx, page = abre(browser, arquivo, {"profiles": []}, sessao=True, guardada=True)
        t = page.inner_text("body")
        conf("ainda não há um perfil" in t and page.locator("[data-retry-perfil]").count() == 0, "com sinal e sem perfil no banco: 'ainda não há um perfil liberado', sem botão de tentar", t[:140].replace("\n", " "))
        ctx.close()

        # ---- renovacao do token nao mexe na tela
        ctx, page = abre(browser, arquivo, {"profiles": [ADMIN]})
        page.evaluate("""() => { window.__cargas = 0; const orig = window.loadAll; window.loadAll = function(...a){ window.__cargas++; return orig.apply(this, a); };
                                 state.editDraft = null; state.modal = {type: 'usuario'}; editDraft = {nome: '', usuario: '', senha: ''}; render(); }""")
        page.wait_for_selector("#f-usuario", timeout=5000)
        page.fill("#f-usuario", "digitado.e.nao.salvo")
        page.evaluate("""() => { const cbs = window.__authCallbacks || []; const cb = cbs[cbs.length - 1];
                                 cb('INITIAL_SESSION', window.__SESSAO__);
                                 cb('TOKEN_REFRESHED', {user: {id: 'u1'}, access_token: 'novo'}); }""")
        page.wait_for_timeout(600)
        r = page.evaluate("() => ({valor: (document.getElementById('f-usuario') || {}).value, token: state.session && state.session.access_token, cargas: window.__cargas})")
        conf(r["valor"] == "digitado.e.nao.salvo", "TOKEN_REFRESHED: o texto digitado no formulario aberto continua la", str(r))
        conf(r["token"] == "novo" and r["cargas"] == 0, "TOKEN_REFRESHED: guarda a sessao nova e nao recarrega os dados", str(r))

        # ---- sair
        page.evaluate("() => { state.modal = null; render(); }")
        page.locator("[data-logout]").first.click()
        page.wait_for_function("() => state.session === null && state.perfil === null", timeout=5000)
        conf(nome in page.inner_text("body") and "Entrar" in page.inner_text("body"), "sair: volta para a tela de login")
        ctx.close()

        ctx, page = abre(browser, arquivo, {"profiles": [ADMIN]})
        page.evaluate("""() => { const cbs = window.__authCallbacks; const cb = cbs[cbs.length - 1]; cb('INITIAL_SESSION', window.__SESSAO__); cb('SIGNED_OUT', null); }""")
        page.wait_for_timeout(500)
        conf("Entrar" in page.inner_text("body") and page.evaluate("() => state.perfil") is None, "sessão encerrada pelo servidor: volta para o login")

        # ---- falta de sinal x outros erros
        casos = page.evaluate("""() => ({
            chrome: pareceErroDeRede({name: 'TypeError', message: 'Failed to fetch'}), safari: pareceErroDeRede({message: 'Load failed'}),
            firefox: pareceErroDeRede({message: 'NetworkError when attempting to fetch resource.'}), texto: pareceErroDeRede('Network request failed'),
            permissao: pareceErroDeRede({message: 'permission denied for table lancamentos', code: '42501'}), vazio: pareceErroDeRede(null)})""")
        conf(casos["chrome"] and casos["safari"] and casos["firefox"] and casos["texto"], "pareceErroDeRede reconhece Chrome, Safari e Firefox", str(casos))
        conf(not casos["permissao"] and not casos["vazio"], "e não confunde com erro de permissão nem com nada", str(casos))
        ctx.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
