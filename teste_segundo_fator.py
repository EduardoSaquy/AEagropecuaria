"""
Verificacao em duas etapas (TOTP, app autenticador) nos cinco apps (core.js, 07/11/2026).

Quem tem um celular cadastrado digita um codigo de 6 numeros DEPOIS da senha; o login so de senha e aal1, com o codigo e aal2 (o
Supabase marca isso no token). As telas ficam por cima do app e valem para os cinco. Quem nao ativou entra como sempre. O que EXIGE o
codigo no banco e o SQL de RLS (seguranca_04), que nao se testa aqui. Prova, em cada app:
  - precisaDoSegundoFator: so e verdadeiro com login de senha (aal1) E fator confirmado; sem JWT, aal2, sem fator ou fator
    nao confirmado nao pedem o codigo;
  - conta sem celular cadastrado: abre direto; conta com celular: o app NAO carrega (nem perfil) ate o codigo passar; codigo errado
    mostra o erro e continua pedindo; codigo certo abre o app; cancelar volta para o login;
  - login com senha numa conta com celular: pede o codigo, e eventos de sessao no meio da conferencia nao carregam o app;
  - sessao ja confirmada neste aparelho (aal2) abre sem pedir de novo, ate sem internet; sem internet o codigo nao e conferido;
  - ativar: so quem tem acesso total ve o botao (na tela Trocar senha); QR code e chave aparecem; codigo errado nao ativa; o certo ativa;
    cadastrar outro celular; desistir no meio nao deixa fator pela metade; remover.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
APPS = ["AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"]
FATOR = {"id": "f_ok", "friendly_name": "Celular do chefe", "factor_type": "totp", "status": "verified"}
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def confere_qr(page, rotulo):
    """O QR aparece como SVG dentro da pagina e DESENHA os tres cantos de posicao nos lugares certos (lido de volta num canvas)."""
    info = page.evaluate("""() => { const q = document.querySelector('#mfa-qr'); const s = q && q.querySelector('svg');
        return {svg: !!s, img: !!(q && q.querySelector('img')), vb: s && s.getAttribute('viewBox'), d: s ? (s.querySelector('path').getAttribute('d') || '').length : 0}; }""")
    conf(info["svg"] and not info["img"] and info["vb"] == "0 0 111 111" and 100 < info["d"] < 30000,
         f"QR ({rotulo}): aparece como SVG pequeno dentro da pagina, com viewBox", str(info))
    amostra = page.evaluate("""async () => {
        const s = document.querySelector('#mfa-qr svg');
        const img = new Image(); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(s)); await img.decode();
        const L = 370, c = document.createElement('canvas'); c.width = L; c.height = L;
        const x = c.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, L, L); x.drawImage(img, 0, 0, L, L);
        const mod = (col, lin) => x.getImageData(Math.round((col + 4.5) * L / 37), Math.round((lin + 4.5) * L / 37), 1, 1).data[0] < 128 ? 1 : 0;
        return {zona: x.getImageData(3, 3, 1, 1).data[0], sup_esq: [mod(0, 0), mod(3, 3), mod(1, 1), mod(6, 6)], sup_dir: [mod(28, 0), mod(25, 3), mod(27, 1)], inf_esq: [mod(0, 28), mod(3, 25), mod(1, 27)]}; }""")
    ok = (amostra["zona"] > 200 and amostra["sup_esq"] == [1, 1, 0, 1] and amostra["sup_dir"] == [1, 1, 0] and amostra["inf_esq"] == [1, 1, 0])
    conf(ok, f"QR ({rotulo}): os tres cantos de posicao estao inteiros, nos lugares certos", str(amostra))



def perfil(papel="admin"):
    return {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": papel, "ativo": True, "permissoes": {}, "frentes": []}


def abre(browser, arquivo, aal="aal1", fatores=(), papel="admin", com_sessao=True, esperar="boot"):
    """aal: nivel do login guardado. fatores: celulares ja cadastrados (confirmados)."""
    ctx = browser.new_context(viewport={"width": 1280, "height": 900})
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps({'profiles': [perfil(papel)]})}; window.__MFA__ = {{fatores: {json.dumps(list(fatores))}}};"
        + (f"window.__SESSAO__ = {{user: {{id: 'u1', factors: {json.dumps(list(fatores))}}}, access_token: window.__jwt('{aal}')}};" if com_sessao else "window.__SESSAO__ = null;"))
    page.goto((REPO / arquivo).as_uri())
    if esperar == "boot":
        page.wait_for_function("() => typeof state !== 'undefined' && state.authChecked === true", timeout=30000)
        page.wait_for_timeout(500)
    elif esperar == "desafio":
        page.wait_for_selector("#mfa-desafio", timeout=15000)
    return ctx, page


def digita_e_confirma(page, codigo):
    page.fill("#mfa-codigo", codigo)
    page.locator("#mfa-ok").click()
    page.wait_for_timeout(500)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    print("\n== precisaDoSegundoFator (regra pura)")
    ctx, page = abre(browser, "AEMatriz.html")
    casos = page.evaluate("""() => { const j = window.__jwt; const f = (s) => [{id: 'a', status: s, factor_type: 'totp'}];
        return {
          semJwt: precisaDoSegundoFator({access_token: 'x', user: {factors: f('verified')}}),
          semSessao: precisaDoSegundoFator(null),
          aal2: precisaDoSegundoFator({access_token: j('aal2'), user: {factors: f('verified')}}),
          semFator: precisaDoSegundoFator({access_token: j('aal1'), user: {}}),
          naoConfirmado: precisaDoSegundoFator({access_token: j('aal1'), user: {factors: f('unverified')}}),
          comFator: precisaDoSegundoFator({access_token: j('aal1'), user: {factors: f('verified')}}) }; }""")
    conf(casos["comFator"] is True, "login de senha (aal1) com fator confirmado pede o codigo", str(casos))
    conf(not any(casos[k] for k in ("semJwt", "semSessao", "aal2", "semFator", "naoConfirmado")),
         "sem JWT, sem sessao, aal2, sem fator ou fator nao confirmado: nao pede", str(casos))
    ctx.close()

    for arquivo in APPS:
        print(f"\n== {arquivo}")

        # ---- conta sem celular cadastrado: abre direto
        ctx, page = abre(browser, arquivo, aal="aal1", fatores=())
        conf(page.locator("#mfa-desafio").count() == 0 and page.evaluate("() => state.perfil && state.perfil.papel") == "admin", "conta sem celular cadastrado: abre direto, sem pedir codigo")
        ctx.close()

        # ---- conta com celular: o app so abre depois do codigo
        ctx, page = abre(browser, arquivo, aal="aal1", fatores=[FATOR], esperar="desafio")
        conf(page.evaluate("() => state.authChecked") is False and page.evaluate("() => state.perfil") is None, "pede o codigo antes de carregar qualquer coisa do app")
        conf("6 números" in page.inner_text("#mfa-desafio"), "a tela explica o que digitar")
        digita_e_confirma(page, "12")
        conf(page.locator("#mfa-desafio").count() == 1 and "6 números" in page.inner_text("#mfa-erro"), "codigo incompleto: avisa e continua pedindo")
        digita_e_confirma(page, "000000")
        conf(page.locator("#mfa-desafio").count() == 1 and "inválido" in page.inner_text("#mfa-erro"), "codigo errado: mostra o erro e continua pedindo")
        digita_e_confirma(page, "123456")
        page.wait_for_function("() => state.authChecked === true && state.perfil", timeout=8000)
        conf(page.locator("#mfa-desafio").count() == 0 and page.evaluate("() => state.perfil.papel") == "admin", "codigo certo: a tela some e o app abre")
        conf(page.evaluate("() => precisaDoSegundoFator(state.session)") is False, "a sessao passa a ser confirmada (aal2)")
        ctx.close()

        # ---- cancelar
        ctx, page = abre(browser, arquivo, aal="aal1", fatores=[FATOR], esperar="desafio")
        page.locator("#mfa-sair").click()
        page.wait_for_function("() => state.authChecked === true", timeout=8000)
        t = page.inner_text("body")
        conf(page.locator("#mfa-desafio").count() == 0 and "Entrar" in t and page.evaluate("() => state.session") is None, "cancelar: volta para a tela de login, sem sessao", t[:80])
        ctx.close()

        # ---- login com senha numa conta com celular
        ctx, page = abre(browser, arquivo, com_sessao=False)
        page.evaluate("""() => { window.__SESSAO__ = {user: {id: 'u1', factors: window.__MFA__.fatores}, access_token: window.__jwt('aal1')};
                               window.__MFA__.fatores = [{id: 'f_ok', friendly_name: 'Celular', factor_type: 'totp', status: 'verified'}];
                               window.__SESSAO__.user.factors = window.__MFA__.fatores;
                               state.loginDraft = {usuario: 'chefe', senha: 'segredo'}; fazerLogin(); }""")
        page.wait_for_selector("#mfa-desafio", timeout=8000)
        page.evaluate("() => { const c = window.__authCallbacks[window.__authCallbacks.length - 1]; c('SIGNED_IN', window.__SESSAO__); }")
        page.wait_for_timeout(500)
        conf(page.evaluate("() => state.perfil") is None, "senha certa mas falta o codigo: o app nao carrega, nem com evento de sessao no meio")
        digita_e_confirma(page, "123456")
        page.wait_for_function("() => state.perfil", timeout=8000)
        conf(page.locator("#mfa-desafio").count() == 0 and page.evaluate("() => state.perfil.papel") == "admin", "com o codigo certo o login termina e o app abre")
        ctx.close()

        # ---- sessao ja confirmada neste aparelho: abre sem pedir, mesmo sem internet
        ctx, page = abre(browser, arquivo, aal="aal2", fatores=[FATOR])
        conf(page.locator("#mfa-desafio").count() == 0 and page.evaluate("() => state.perfil && state.perfil.papel") == "admin", "sessao ja confirmada (aal2): abre sem pedir de novo")
        ctx.close()
        ctx, page = abre(browser, arquivo, aal="aal1", fatores=[FATOR], esperar="desafio")
        ctx.set_offline(True)
        page.fill("#mfa-codigo", "123456")
        page.locator("#mfa-ok").click()
        page.wait_for_timeout(400)
        conf("Sem internet" in page.inner_text("#mfa-erro") and page.locator("#mfa-desafio").count() == 1, "sem internet: avisa que o codigo so e conferido com sinal")
        ctx.close()

        # ---- sessao aberta so com senha e conta que ganhou celular: a renovacao do token pede o codigo
        ctx, page = abre(browser, arquivo, aal="aal1", fatores=())
        page.evaluate("""() => { const f = [{id: 'f_novo', friendly_name: 'Celular', factor_type: 'totp', status: 'verified'}];
                               window.__MFA__.fatores = f; window.__SESSAO__ = {user: {id: 'u1', factors: f}, access_token: window.__jwt('aal1')};
                               const cbs = window.__authCallbacks; const cb = cbs[cbs.length - 1]; cb('INITIAL_SESSION', null); cb('TOKEN_REFRESHED', window.__SESSAO__); }""")
        page.wait_for_selector("#mfa-desafio", timeout=5000)
        conf(True, "token renovado de um login so de senha que agora tem celular: o codigo e pedido")
        digita_e_confirma(page, "123456")
        conf(page.locator("#mfa-desafio").count() == 0 and page.evaluate("() => state.perfil && state.perfil.papel") == "admin", "com o codigo certo segue no app, sem recarregar")
        page.evaluate("""() => { const f = window.__MFA__.fatores; const cbs = window.__authCallbacks; const cb = cbs[cbs.length - 1];
                               window.__SESSAO__ = {user: {id: 'u1', factors: f}, access_token: window.__jwt('aal1')}; cb('TOKEN_REFRESHED', window.__SESSAO__); }""")
        page.wait_for_selector("#mfa-desafio", timeout=5000)
        page.locator("#mfa-sair").click()
        page.wait_for_function("() => state.session === null", timeout=5000)
        conf("Entrar" in page.inner_text("body"), "cancelar o codigo na renovacao: sai do app")
        ctx.close()

        # ---- ativar: botao so para quem tem acesso total
        for papel, ve in (("gestor", False), ("proprietario", True), ("admin", True)):
            ctx, page = abre(browser, arquivo, aal="aal2", papel=papel)
            # quem nao e admin pode nem ter tela no app (gestor sem permissao): confere o texto da tela Trocar senha
            tem = page.evaluate("() => { editDraft = {senhaAtual: '', novaSenha: '', confirmarSenha: ''}; return ModalTrocarSenha().includes('data-mfa-abrir'); }")
            conf(tem == ve, f"{papel}: {'ve' if ve else 'nao ve'} o botao da verificacao em duas etapas na tela Trocar senha")
            if papel != "admin":
                ctx.close()
                continue
            page.evaluate("() => { editDraft = {senhaAtual: '', novaSenha: '', confirmarSenha: ''}; state.modal = {type: 'trocarSenha'}; render(); }")
            page.wait_for_selector("#f-senhaatual", timeout=5000)
            conf(page.locator("[data-mfa-abrir]").count() == 1, "admin: o botao aparece na tela de verdade")

            # admin: ativa passo a passo
            page.locator("[data-mfa-abrir]").click()
            page.wait_for_selector("#mfa-dialogo", timeout=5000)
            page.wait_for_selector("[data-mfa-ativar]", timeout=5000)
            conf("só com senha" in page.inner_text("#mfa-dialogo"), "sem celular cadastrado: diz que o login e so com senha")
            page.locator("[data-mfa-ativar]").click()
            page.wait_for_selector("#mfa-ativar-codigo", timeout=5000)
            conf("JBSWY3DPEHPK3PXP" in page.inner_text("#mfa-dialogo"), "mostra a chave para digitar no app")
            page.wait_for_timeout(200)
            confere_qr(page, "formato do Supabase (SVG do servidor, sem viewBox, quadradinhos pretos e brancos)")
            conf(page.evaluate("() => { const a = document.querySelector('#mfa-abrir-app'); return !!a && a.getAttribute('href').startsWith('otpauth://totp/') && a.getAttribute('href').includes('secret=JBSWY3DPEHPK3PXP'); }"),
                 "tem o botao 'Estou neste celular: abrir no app autenticador' (link otpauth com a chave)")
            conf(page.locator("#f-senhaatual").count() == 0, "a tela Trocar senha do app sai de baixo da janela")
            page.fill("#mfa-ativar-codigo", "000000")
            page.locator("[data-mfa-confirmar]").click()
            page.wait_for_timeout(400)
            conf("inválido" in page.inner_text("#mfa-dialogo") and page.evaluate("() => __MFA__.fatores.filter(f => f.status === 'verified').length") == 0, "codigo errado nao ativa")
            page.fill("#mfa-ativar-codigo", "123456")
            page.locator("[data-mfa-confirmar]").click()
            page.wait_for_selector("[data-mfa-remover]", timeout=5000)
            conf("ativada" in page.inner_text("#mfa-dialogo") and page.evaluate("() => __MFA__.fatores.filter(f => f.status === 'verified').length") == 1, "codigo certo ativa e lista o celular")
            conf(page.evaluate("() => state.session && state.session.access_token") is not None and page.evaluate("() => state.perfil.papel") == "admin", "ativar nao derruba nem recarrega o app")

            # cadastrar outro e desistir no meio
            page.locator("[data-mfa-ativar]").click()
            page.wait_for_selector("#mfa-ativar-codigo", timeout=5000)
            conf(page.evaluate("() => __MFA__.fatores.length") == 2, "outro celular: comeca um cadastro novo")
            page.locator("[data-mfa-voltar]").click()
            page.wait_for_selector("[data-mfa-remover]", timeout=5000)
            # o mesmo QR com a cor escrita como '#000000' (cor com '#' cortava o endereco da imagem)
            page.evaluate("() => { window.__QR_FORMATO__ = 'hex'; }")
            page.locator("[data-mfa-ativar]").click()
            page.wait_for_selector("#mfa-ativar-codigo", timeout=5000)
            confere_qr(page, "SVG com a cor escrita como #000000")
            page.locator("[data-mfa-voltar]").click()
            page.wait_for_selector("[data-mfa-remover]", timeout=5000)
            # SVG que nao da para ler: plano B (imagem), e a chave e o botao continuam la
            page.evaluate("() => { window.__QR_FORMATO__ = 'ilegivel'; }")
            page.locator("[data-mfa-ativar]").click()
            page.wait_for_selector("#mfa-ativar-codigo", timeout=5000)
            page.wait_for_timeout(300)
            conf(page.evaluate("() => { const i = document.querySelector('#mfa-qr img'); return !!i && i.complete && i.naturalWidth > 0 && !document.querySelector('#mfa-qr svg'); }"),
                 "SVG que nao da para ler: cai na imagem, que carrega")
            conf("JBSWY3DPEHPK3PXP" in page.inner_text("#mfa-dialogo") and page.locator("#mfa-abrir-app").count() == 1, "mesmo assim a chave e o botao de abrir no app aparecem")
            page.locator("[data-mfa-voltar]").click()
            page.wait_for_selector("[data-mfa-remover]", timeout=5000)
            page.evaluate("() => { window.__QR_FORMATO__ = 'gotrue'; }")
            conf(page.evaluate("() => __MFA__.fatores.length") == 1, "desistir no meio nao deixa fator pela metade")

            # remover
            page.evaluate("() => { window.confirm = () => true; }")   # o confirm() nativo responde sim
            page.locator("[data-mfa-remover]").click()
            page.wait_for_selector("[data-mfa-ativar]", timeout=5000)
            conf(page.evaluate("() => __MFA__.fatores.length") == 0 and "só com senha" in page.inner_text("#mfa-dialogo"), "remover o unico celular: o login volta a ser so com senha")
            page.locator("[data-mfa-fechar]").first.click()
            conf(page.locator("#mfa-dialogo").count() == 0, "fechar a janela")
            ctx.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
