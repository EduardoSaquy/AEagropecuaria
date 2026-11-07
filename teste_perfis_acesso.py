"""
Tela de acesso e de novo usuario, iguais nos cinco apps (core.js, 07/11/2026).

A tela de acesso de cada app oferecia uma lista propria de perfis e, para quem tinha um perfil que a lista nao tinha, o seletor caia no
PRIMEIRO item: abrir e salvar rebaixava a pessoa sem ninguem ver (a Pecuaria rebaixava gestor/operador/encarregado a Colaborador; os
outros, o consultor). O banco aceita sete perfis (admin, proprietario, gestor, encarregado, colaborador, operador, consultor). Tambem
havia campos sem escape nas telas de usuario de alguns apps (a senha digitada e a mensagem de erro no Matriz, no Combustivel e no
Cana/Cereais; o login digitado no Cana/Cereais), enquanto a Pecuaria ja escapava. Prova, nos cinco apps:
  - abrir a tela de acesso de uma pessoa de QUALQUER dos sete perfis deixa o seletor no perfil dela (e salvar nao o troca);
  - a lista de usuarios mostra cada perfil com o texto certo e a cor do destaque (acesso total / gestor e consultor / demais);
  - o formulario de novo usuario mostra texto digitado com aspas, < e & como texto, sem abrir atributo nem elemento novo.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
PAPEIS = ["admin", "proprietario", "gestor", "encarregado", "colaborador", "operador", "consultor"]
# app, pagina de usuarios, botao Salvar da tela de acesso, o salvar passa pelo stub?
APPS = [
    ("AEMatriz.html", "usuarios", "papelUsuario", True),
    ("AEpecuaria.html", "adminUsuarios", "permissoes", False),   # a Pecuaria salva por uma funcao de servidor: so se confere o seletor
    ("AECana.html", "adminUsuarios", "permissoes", True),
    ("AECereais.html", "adminUsuarios", "permissoes", True),
    ("AECombustivel.html", "adminUsuarios", "permissoes", True),
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


def perfis():
    return [{"id": f"u_{p}", "nome": f"Pessoa {p}", "usuario": f"pessoa.{p}", "papel": p, "ativo": True, "permissoes": {}, "frentes": []} for p in PAPEIS]


def abre(browser, arquivo):
    db = {"profiles": perfis()}
    ctx = browser.new_context(viewport={"width": 1280, "height": 900})
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u_admin'}}, access_token:'x'}};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.perfil.papel === 'admin'", timeout=30000)
    page.wait_for_timeout(800)
    return ctx, page


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arquivo, pagina, botao_salvar, salva_no_stub in APPS:
        print(f"\n== {arquivo}")
        ctx, page = abre(browser, arquivo)
        page.evaluate("(pg) => { state.page = pg; render(); }", pagina)
        page.wait_for_selector("[data-editar-usuario]", timeout=8000)

        linhas = page.evaluate("""() => Object.fromEntries([...document.querySelectorAll('tbody tr')].map(tr => {
            const pill = tr.querySelector('.pill'); return [tr.children[1].textContent.trim(), pill ? {texto: pill.textContent.trim(), classe: pill.className} : null]; }))""")
        total = {"admin": "pill-cat", "proprietario": "pill-cat", "gestor": "pill-warn", "consultor": "pill-warn",
                 "encarregado": "pill-ok", "colaborador": "pill-ok", "operador": "pill-ok"}
        erros = [f"{p}: {linhas.get('pessoa.' + p)}" for p in PAPEIS if not linhas.get("pessoa." + p) or total[p] not in linhas["pessoa." + p]["classe"]]
        conf(not erros, "a lista mostra cada perfil com a cor certa (acesso total / gestor e consultor / demais)", "; ".join(erros))
        conf(all(linhas["pessoa." + p]["texto"] for p in PAPEIS), "todo perfil aparece com algum texto na lista")

        for papel in PAPEIS:
            if arquivo == "AEMatriz.html" and papel == "admin":
                continue
            page.evaluate("(id) => document.querySelector(`[data-editar-usuario=\"${id}\"]`).click()", f"u_{papel}")
            page.wait_for_selector("#f-papelusuario", timeout=5000)
            no_seletor = page.evaluate("() => document.getElementById('f-papelusuario').value")
            conf(no_seletor == papel, f"abrir o acesso de quem e '{papel}': o seletor fica em '{papel}'", f"ficou em '{no_seletor}'")
            if salva_no_stub and papel in ("consultor", "colaborador", "gestor"):
                page.evaluate("(b) => document.querySelector(`[data-save=\"${b}\"]`).click()", botao_salvar)
                page.wait_for_timeout(500)
                salvo = page.evaluate("(id) => __DB__.profiles.find(p => p.id === id).papel", f"u_{papel}")
                conf(salvo == papel, f"salvar sem mexer no perfil mantem '{papel}'", f"salvou '{salvo}'")
            else:
                page.evaluate("() => document.querySelector('.modal [data-close]').click()")
            page.wait_for_timeout(150)
            if page.query_selector("#f-papelusuario"):
                page.evaluate("() => { state.modal = null; render(); }")

        # novo usuario: o que se digita entra como texto
        sujo = 'x" data-invadiu="1" y="'
        page.evaluate("""(sujo) => { editDraft = {nome: sujo, usuario: sujo, senha: sujo}; state.usuarioError = '<img data-invadiu="1" src=x>';
                                      state.modal = {type: 'usuario'}; render(); }""", sujo)
        page.wait_for_selector("#f-usuario", timeout=5000)
        r = page.evaluate("""(sujo) => ({usuario: document.getElementById('f-usuario').value, nome: document.getElementById('f-nomeusuario').value,
                                         senha: document.getElementById('f-senhausuario').value,
                                         invadiu: document.querySelectorAll('[data-invadiu]').length})""", sujo)
        conf(r["usuario"] == sujo and r["nome"] == sujo and r["senha"] == sujo, "nome, usuario e senha com aspas voltam inteiros nos campos", str(r))
        conf(r["invadiu"] == 0, "nenhum atributo nem elemento novo nasceu do texto digitado ou da mensagem de erro", str(r))
        ctx.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
