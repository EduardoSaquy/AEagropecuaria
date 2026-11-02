"""
AECana.html / AECereais.html: texto digitado entra no HTML escapado
(revisao geral de 02/11/2026). Antes nenhum texto era escapado: um nome com
aspas ("Adubo 20" 05") era cortado no campo de edicao e, ao salvar, gravava
o nome cortado; um "<" quebrava a tabela; e um nome com tag rodaria como
codigo na tela de quem abrisse.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
NOME = 'Adubo 20" <b>forte</b> & cia'
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}

def banco(tabela):
    return {
        "fazendas": [{"id": 1, "nome": "Faz A", "estado": "SP", "area_ha": 100, "ativo": True}],
        "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 100},
                               {"id": 2, "fazenda_id": 1, "atividade": "graos", "area_ha": 100}],
        "culturas": [{"id": 10, "nome": "Cana", "frente": "cana", "ativo": True},
                     {"id": 11, "nome": "Soja", "frente": "graos", "ativo": True}],
        "safras": [], "talhoes_areas": [], "plantios_cana": [], "plantios_graos": [],
        "colheitas_cana": [], "colheitas_graos": [],
        "insumos_cana": [], "insumos_graos": [],
        tabela: [{"id": 50, "nome": NOME, "categoria": "adubo", "unidade": "kg", "ativo": True}],
        "entradas_insumo_cana": [], "entradas_insumo_graos": [],
        "aplicacoes_cana": [], "aplicacoes_graos": [], "profiles": [ADMIN],
    }

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for arquivo, tabela, chave in (("AECana.html", "insumos_cana", "insumosCana"), ("AECereais.html", "insumos_graos", "insumosGraos")):
        print(f"\n  {arquivo}: TEXTO ESCAPADO")
        page = browser.new_page()
        erros = []
        page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
        page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
        page.add_init_script(STUB)
        page.add_init_script(f"window.__DB__ = {json.dumps(banco(tabela))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        page.goto((REPO / arquivo).as_uri()); page.wait_for_timeout(1500)
        conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))
        page.evaluate(f"() => {{ state.page = '{chave}'; render(); }}"); page.wait_for_timeout(200)
        conf(page.locator("main b, .main b, table b").count() == 0, "o <b> do nome nao vira negrito (nao vira HTML)")
        conf(NOME in page.evaluate("() => document.body.textContent"), "a lista mostra o nome inteiro, com aspas, < e &")
        page.evaluate(f"() => {{ abrirEditarCadastro('{chave}', 50); render(); }}"); page.wait_for_timeout(200)
        valor = page.evaluate("() => { const i = [...document.querySelectorAll('.modal input[type=text]')][0]; return i ? i.value : null; }")
        conf(valor == NOME, "o campo de edicao traz o nome inteiro (antes cortava nas aspas)", repr(valor))
        page.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
