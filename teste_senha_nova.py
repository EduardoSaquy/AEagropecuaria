"""
Senha de 10+ caracteres e troca obrigatoria (12/11/2026, decisao do Eduardo: todos trocam na proxima entrada).
  - perfil com precisa_trocar_senha: tela cheia "crie uma senha nova" antes de o app abrir (os 5 apps, pelo core.js);
    menos de 10 caracteres ou as duas diferentes nao passam; "Sair" volta para o login; erro do servidor em portugues;
  - perfil sem a marca, ou banco ainda sem a coluna: nada muda; sem internet (perfil guardado) nao trava o app;
  - Trocar senha: minimo 10 e a senha atual e conferida num cliente A PARTE (antes entrava de novo no proprio
    cliente e, com o codigo do celular ativado, a sessao confirmada virava so de senha);
  - criar usuario: senha provisoria tambem com 10+.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ESPIA = """
(function(){
  const s = window.supabase, orig = s.createClient;
  s.createClient = function(){
    const c = orig.apply(this, arguments), opts = arguments[2];
    const avulso = !!(opts && opts.auth && opts.auth.storageKey === 'ae-confere-senha');
    const si = c.auth.signInWithPassword;
    c.auth.signInWithPassword = function(o){
      (window.__LOGINS__ = window.__LOGINS__ || []).push({avulso});
      if(avulso && window.__SENHA_ERRADA__) return Promise.resolve({data:{session:null}, error:{message:'Invalid login credentials', status:400}});
      return si.apply(this, arguments);
    };
    c.functions = { invoke: function(nome, o){ (window.__FUNCOES__ = window.__FUNCOES__ || []).push({nome, body: o && o.body}); return Promise.resolve({data:{ok:true}, error:null}); } };
    c.auth.updateUser = function(o){
      (window.__SENHAS__ = window.__SENHAS__ || []).push(o && o.password);
      const e = window.__ERRO_UPDATE__ || null; window.__ERRO_UPDATE__ = null;
      return Promise.resolve({data:{user:{id:'u1'}}, error: e});
    };
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


def perfil(marca):
    p = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
    if marca is not None:
        p["precisa_trocar_senha"] = marca
    return p


def abre(browser, app, marca, ctx=None):
    ctx = ctx or browser.new_context()
    page = ctx.new_page()
    erros, avisos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("console", lambda m: avisos.append(m.text) if m.text.startswith("[aviso]") else None)
    page.on("dialog", lambda d: d.accept())
    page.route("**/fonts.g*/**", lambda r: r.abort())
    page.add_init_script(STUB)
    page.add_init_script(ESPIA)
    page.add_init_script(f"window.__DB__ = {json.dumps({'profiles': [perfil(marca)]})};"
                         "window.__SESSAO__ = {user:{id:'u1'}, access_token:'x'};")
    page.goto("file://" + str(REPO / app))
    page.wait_for_timeout(1300)
    return ctx, page, erros, avisos


def tela_senha(page):
    return page.locator("#senha-nova").count() == 1


def preenche(page, a, b):
    page.locator("#senha-nova-1").fill(a)
    page.locator("#senha-nova-2").fill(b)
    page.locator("#senha-nova-ok").click()
    page.wait_for_timeout(400)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    print("\n  TROCA OBRIGATORIA (AE Matriz)")
    ctx, page, erros, avisos = abre(browser, "AEMatriz.html", True)
    conf(tela_senha(page), "marcado: abre a tela 'crie uma senha nova'")
    conf(not page.evaluate("!!state.authChecked"), "e o app nao abre por baixo antes da troca")
    preenche(page, "curta123", "curta123")
    conf("pelo menos 10" in page.locator("#senha-nova-erro").inner_text(), "menos de 10 caracteres: nao passa",
         page.locator("#senha-nova-erro").inner_text())
    preenche(page, "senha-boa-2026", "senha-boa-2027")
    conf("não são iguais" in page.locator("#senha-nova-erro").inner_text(), "as duas diferentes: nao passa")
    conf(page.evaluate("(window.__SENHAS__ || []).length") == 0, "nada foi mandado ao servidor ate aqui")
    page.evaluate("window.__ERRO_UPDATE__ = {code:'same_password', message:'New password should be different from the old password.'}")
    preenche(page, "senha-boa-2026", "senha-boa-2026")
    conf("diferente da atual" in page.locator("#senha-nova-erro").inner_text(), "erro do servidor aparece em portugues",
         page.locator("#senha-nova-erro").inner_text())
    preenche(page, "outra-senha-2026", "outra-senha-2026")
    page.wait_for_timeout(800)
    conf(page.evaluate("(window.__SENHAS__ || []).slice(-1)[0]") == "outra-senha-2026", "manda a senha nova ao servidor")
    conf(not tela_senha(page) and page.evaluate("!!(state.authChecked && state.perfil && state.perfil.ativo)"),
         "depois da troca a tela some e o app abre")
    conf(page.evaluate("state.perfil.precisaTrocarSenha") is False, "e o perfil fica desmarcado")
    conf(not erros, "sem erro de JavaScript", "; ".join(erros[:2]))
    ctx.close()

    ctx, page, erros, avisos = abre(browser, "AEMatriz.html", True)
    page.locator("#senha-nova-sair").click()
    page.wait_for_timeout(800)
    conf(not tela_senha(page) and page.locator("[data-login-form]").count() == 1, "'Sair' volta para a tela de login")
    ctx.close()

    print("\n  QUEM NAO PRECISA")
    for marca, desc in ((False, "ja trocou"), (None, "banco ainda sem a coluna")):
        ctx, page, erros, avisos = abre(browser, "AEMatriz.html", marca)
        conf(not tela_senha(page) and page.evaluate("!!state.perfil"), f"{desc}: abre normal, sem pedir senha nova")
        ctx.close()

    print("\n  SEM INTERNET")
    ctx = browser.new_context()
    ctx, page, erros, avisos = abre(browser, "AEpecuaria.html", False, ctx)
    page.evaluate("localStorage.setItem('__sem_rede', '1')")
    page.close()
    ctx, page, erros, avisos = abre(browser, "AEpecuaria.html", True, ctx)
    conf(not tela_senha(page) and page.evaluate("!!state.perfil"), "sem sinal (perfil guardado no aparelho): o app abre, sem travar no campo")
    page.evaluate("localStorage.removeItem('__sem_rede')")
    ctx.close()

    print("\n  OUTROS APPS")
    for app in ("AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"):
        ctx, page, erros, avisos = abre(browser, app, True)
        conf(tela_senha(page), f"{app}: marcado, pede a senha nova")
        preenche(page, "senha-boa-2026", "senha-boa-2026")
        page.wait_for_timeout(600)
        conf(not tela_senha(page) and page.evaluate("!!state.perfil"), f"{app}: depois da troca abre")
        conf(not erros, f"{app}: sem erro de JavaScript", "; ".join(erros[:2]))
        ctx.close()

    print("\n  TROCAR SENHA (tela do menu)")
    for app in ("AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"):
        ctx, page, erros, avisos = abre(browser, app, False)
        def abre_modal():
            page.evaluate("() => { editDraft = {senhaAtual:'', novaSenha:'', confirmarSenha:''}; state.modal = {type:'trocarSenha'}; render(); }")
            page.wait_for_timeout(200)
        abre_modal()
        conf("10 caracteres" in page.locator(".modal").inner_text(), f"{app}: a tela diz o minimo de 10")
        page.locator("#f-senhaatual").fill("senha-antiga")
        page.locator("#f-novasenha").fill("curta12")
        page.locator("#f-confirmarsenha").fill("curta12")
        page.locator("[data-save='trocarSenha']").click()
        page.wait_for_timeout(400)
        conf(any("pelo menos 10" in a for a in avisos) and page.evaluate("(window.__SENHAS__||[]).length") == 0,
             f"{app}: nova com menos de 10 nao passa")
        page.evaluate("window.__LOGINS__ = []; window.__SENHA_ERRADA__ = true")
        abre_modal()
        page.locator("#f-senhaatual").fill("errada")
        page.locator("#f-novasenha").fill("senha-nova-2026")
        page.locator("#f-confirmarsenha").fill("senha-nova-2026")
        page.locator("[data-save='trocarSenha']").click()
        page.wait_for_timeout(500)
        conf(any("Senha atual incorreta" in a for a in avisos) and page.evaluate("(window.__SENHAS__||[]).length") == 0,
             f"{app}: senha atual errada nao troca")
        page.evaluate("window.__LOGINS__ = []; window.__SENHA_ERRADA__ = false")
        abre_modal()
        page.locator("#f-senhaatual").fill("senha-antiga")
        page.locator("#f-novasenha").fill("senha-nova-2026")
        page.locator("#f-confirmarsenha").fill("senha-nova-2026")
        page.locator("[data-save='trocarSenha']").click()
        page.wait_for_timeout(600)
        logins = page.evaluate("window.__LOGINS__")
        conf(logins == [{"avulso": True}], f"{app}: a senha atual e conferida num cliente a parte (a sessao do app nao muda)", str(logins))
        conf(page.evaluate("(window.__SENHAS__||[]).slice(-1)[0]") == "senha-nova-2026", f"{app}: troca a senha")
        conf(not erros, f"{app}: sem erro de JavaScript", "; ".join(erros[:2]))
        ctx.close()

    print("\n  SENHA PROVISORIA PARA QUEM ESQUECEU (administrador)")
    for app, pagina in (("AEMatriz.html", "usuarios"), ("AEpecuaria.html", "adminUsuarios"), ("AECana.html", "adminUsuarios"),
                        ("AECereais.html", "adminUsuarios"), ("AECombustivel.html", "adminUsuarios")):
        ctx, page, erros, avisos = abre(browser, app, False)
        page.evaluate("(p) => { state.perfis = [{id:'u2', nome:'Fulano', usuario:'fulano', papel:'operador', ativo:true, permissoes:{}}]; state.page = p; render(); }", pagina)
        page.wait_for_timeout(300)
        botao = page.locator("[data-redefinir-senha='u2']")
        conf(botao.count() >= 1, f"{app}: botao 'Nova senha' na lista de usuarios")
        if botao.count() == 0:
            ctx.close(); continue
        botao.first.click()
        page.wait_for_timeout(200)
        conf(page.locator("#redefinir-senha").count() == 1, f"{app}: abre a janela da senha provisoria")
        page.locator("#rs-senha-1").fill("curta"); page.locator("#rs-senha-2").fill("curta"); page.locator("#rs-ok").click()
        page.wait_for_timeout(200)
        conf("pelo menos 10" in page.locator("#rs-erro").inner_text() and not page.evaluate("(window.__FUNCOES__||[]).length"),
             f"{app}: menos de 10 caracteres nao passa")
        page.locator("#rs-senha-1").fill("provisoria-123"); page.locator("#rs-senha-2").fill("provisoria-123"); page.locator("#rs-ok").click()
        page.wait_for_timeout(500)
        chamadas = page.evaluate("window.__FUNCOES__ || []")
        conf(chamadas == [{"nome": "criar-usuario-cana", "body": {"acao": "redefinir_senha", "usuario_id": "u2", "senha": "provisoria-123"}}],
             f"{app}: chama a funcao com a acao redefinir_senha", str(chamadas))
        conf(page.locator("#redefinir-senha").count() == 0 and any("Senha provisória salva" in a for a in avisos), f"{app}: fecha e avisa")
        conf(not erros, f"{app}: sem erro de JavaScript", "; ".join(erros[:2]))
        ctx.close()

    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
