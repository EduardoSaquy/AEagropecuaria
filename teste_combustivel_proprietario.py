"""
AE Combustivel e o papel Proprietario (07/11/2026, decisao do Eduardo: "Sim", igualar aos outros apps).

Antes o Combustivel nao conhecia o papel `proprietario`: temPermissao() usava souAdmin() (so `admin`), entao um proprietario caia na
matriz de modulos como um colaborador qualquer, enquanto no Matriz, na Pecuaria, no Cana e no Cereais ele tem acesso total. A tela de
acesso tambem nao tinha a opcao "Proprietario": editar um proprietario por ali e salvar o rebaixava a Operador (o primeiro item do
seletor) sem ninguem ver. Prova:
  - proprietario, sem nenhuma permissao marcada, ve e edita todos os modulos; a tela de Usuarios continua so do administrador;
  - gestor sem permissao continua sem nada (a regra dos demais nao mudou);
  - na tela de Usuarios o proprietario aparece como "Proprietario" (e nao "proprietario" cru);
  - editar e salvar um proprietario mantem proprietario; um colaborador (perfil que a tela nao lista) tambem mantem o dele.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def perfil(id, nome, usuario, papel, permissoes=None):
    return {"id": id, "nome": nome, "usuario": usuario, "papel": papel, "ativo": True, "permissoes": permissoes or {}, "frentes": []}


ADMIN = perfil("u1", "Chefe", "chefe", "admin")
DONO = perfil("u2", "Dono", "dono", "proprietario")
GESTOR = perfil("u3", "Gestor sem nada", "gestor", "gestor")
COLAB = perfil("u4", "Colaborador", "colab", "colaborador", {"combustivel_abastecimento": "visualizar"})


def base(logado):
    return {
        "fazendas": [{"id": 1, "nome": "Mata Verde", "estado": "GO", "area_ha": 100, "ativo": True}],
        "tanques": [{"id": 1, "fazenda_id": 1, "nome": "Tanque 1", "produto_id": 1, "capacidade_litros": 10000, "tipo": "fixo", "ativo": True}],
        "entradas_estoque": [], "equipamentos": [], "abastecimentos": [], "manutencoes": [], "lancamentos_financeiros": [],
        "produtos": [{"id": 1, "nome": "Diesel S10", "unidade": "L", "ativo": True}], "fornecedores": [{"id": 1, "nome": "Posto", "ativo": True}],
        "operadores": [], "profiles": [logado] if logado is not ADMIN else [ADMIN, DONO, GESTOR, COLAB],
    }


def abre(browser, logado):
    db = base(logado)
    # o usuario logado tem que estar entre os perfis
    if logado is not ADMIN:
        db["profiles"] = [logado]
    ctx = browser.new_context(viewport={"width": 1280, "height": 900})
    page = ctx.new_page()
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:{json.dumps(logado['id'])}}}, access_token:'x'}};")
    page.goto((REPO / "AECombustivel.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && !state.carregando", timeout=30000)
    page.wait_for_timeout(500)
    return ctx, page


NAV = "() => [...document.querySelectorAll('.nav-item')].map(e => e.textContent.trim().replace(/\\s+/g, ' '))"
PERMS = """() => ({
  verEstoque: temPermissao('combustivel_estoque', 'visualizar'), editarAbast: temPermissao('combustivel_abastecimento', 'editar'),
  editarCad: temPermissao('combustivel_cadastros', 'editar'), auditoria: temPermissao('combustivel_auditoria', 'visualizar'), admin: souAdmin(), papel: state.perfil.papel
})"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    print("\n== administrador (referencia)")
    ctx, page = abre(browser, ADMIN)
    nav_admin = page.evaluate(NAV)
    p = page.evaluate(PERMS)
    conf(p["verEstoque"] and p["editarAbast"] and p["admin"], "administrador: tudo liberado e a tela de Usuarios", str(p))
    conf(any("Administra" in t for t in nav_admin), "administrador: o menu tem Administracao", str(nav_admin))

    print("\n== proprietario sem nenhuma permissao marcada")
    ctx2, page2 = abre(browser, DONO)
    p = page2.evaluate(PERMS)
    nav_dono = page2.evaluate(NAV)
    conf(p["papel"] == "proprietario", "entrou como proprietario")
    conf(p["verEstoque"] and p["editarAbast"] and p["editarCad"] and p["auditoria"], "ve e edita todos os modulos, sem depender da matriz", str(p))
    conf(not p["admin"], "a tela de Usuarios continua so do administrador (souAdmin falso)", str(p))
    conf(not any("Administra" in t for t in nav_dono), "o menu dele nao tem Administracao", str(nav_dono))
    esperado = [t for t in nav_admin if "Administra" not in t]
    conf(nav_dono == esperado and len(nav_dono) >= 4, "o menu dele e o do administrador menos a Administracao", f"{nav_dono} x {esperado}")
    ctx2.close()

    print("\n== gestor sem permissao (a regra dos demais nao mudou)")
    ctx3, page3 = abre(browser, GESTOR)
    p = page3.evaluate(PERMS)
    conf(not p["verEstoque"] and not p["editarAbast"] and not p["editarCad"], "gestor sem matriz marcada nao ve nem edita nada", str(p))
    ctx3.close()

    print("\n== tela de Usuarios (como administrador)")
    # abre a Administracao > Usuarios
    page.evaluate("() => { state.page = 'adminUsuarios'; state.grupo = 'admin'; render(); }")
    page.wait_for_timeout(400)
    linhas = page.evaluate("""() => [...document.querySelectorAll('tbody tr')].map(tr => ({nome: tr.children[0].textContent.trim(), pill: tr.children[2].textContent.trim(), classe: (tr.querySelector('.pill')||{}).className}))""")
    dono = next((l for l in linhas if l["nome"] == "Dono"), None)
    conf(dono is not None and dono["pill"] == "Proprietário" and "pill-cat" in dono["classe"], "o proprietario aparece como Proprietario (destaque de acesso total)", str(linhas))

    def edita_e_salva(id_perfil):
        page.evaluate("(id) => { document.querySelector(`[data-editar-usuario=\"${id}\"]`).click(); }", id_perfil)
        page.wait_for_selector("#f-papelusuario", timeout=5000)
        escolhido = page.evaluate("() => document.getElementById('f-papelusuario').value")
        texto = page.evaluate("() => document.querySelector('.modal .hint').textContent")
        page.evaluate("() => document.querySelector('[data-save=\"permissoes\"]').click()")
        page.wait_for_timeout(500)
        salvo = page.evaluate("(id) => __DB__.profiles.find(p => p.id === id).papel", id_perfil)
        return escolhido, texto, salvo

    esc_dono, hint, salvo = edita_e_salva("u2")
    conf(esc_dono == "proprietario" and salvo == "proprietario", "editar e salvar o proprietario mantem proprietario", f"seletor={esc_dono} salvo={salvo}")
    conf("Proprietário têm acesso total" in hint, "o texto da tela diz que Administrador e Proprietario tem acesso total", hint)
    esc_col, _, salvo = edita_e_salva("u4")
    conf(esc_col == "colaborador" and salvo == "colaborador", "editar e salvar um colaborador (perfil que a tela nao lista) mantem colaborador", f"seletor={esc_col} salvo={salvo}")
    esc_ges, _, salvo = edita_e_salva("u3")
    conf(esc_ges == "gestor" and salvo == "gestor", "editar e salvar um gestor mantem gestor", f"seletor={esc_ges} salvo={salvo}")
    ctx.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
