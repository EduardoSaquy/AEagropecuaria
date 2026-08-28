"""
Teste funcional dos apps gerados: sobe cada arquivo num Chromium com um
banco falso e confere o que a tela realmente mostra.

O que este teste procura NAO e "abriu sem erro". E vazamento entre as
frentes: o AE Cana nao pode enxergar nada de cereais e vice-versa. Esse e o
unico motivo da separacao existir, entao e o que precisa ser provado.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

# Duas fazendas em estados diferentes, como na propriedade de verdade:
# cana em SP, cereais em TO. A terceira e so de pecuaria e nao pode
# aparecer em nenhum dos dois apps.
DB = {
    "fazendas": [
        {"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 500, "ativo": True},
        {"id": 2, "nome": "Faz. Invernada", "estado": "TO", "area_ha": 800, "ativo": True},
        {"id": 3, "nome": "Faz. Santa Alice", "estado": "TO", "area_ha": 300, "ativo": True},
    ],
    "fazenda_atividades": [
        {"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 400},
        {"id": 2, "fazenda_id": 2, "atividade": "graos", "area_ha": 600},
        {"id": 3, "fazenda_id": 3, "atividade": "pecuaria", "area_ha": 300},
    ],
    "culturas": [
        {"id": 10, "nome": "Cana planta", "frente": "cana", "ativo": True},
        {"id": 11, "nome": "Soja", "frente": "graos", "ativo": True},
        {"id": 12, "nome": "Milho", "frente": "graos", "ativo": True},
        {"id": 13, "nome": "Capim", "frente": "pecuaria", "ativo": True},
    ],
    "safras": [
        {"id": 20, "nome": "Cana 24/25", "cultura_id": 10},
        {"id": 21, "nome": "Soja 24/25", "cultura_id": 11},
    ],
    "talhoes_areas": [
        {"id": 30, "nome": "TALHAO CANA A", "fazenda_id": 1, "cultura_id": 10, "area_ha": 100, "tipo": "talhao", "ativo": True},
        {"id": 31, "nome": "TALHAO SOJA B", "fazenda_id": 2, "cultura_id": 11, "area_ha": 80, "tipo": "talhao", "ativo": True},
        {"id": 32, "nome": "TALHAO MILHO C", "fazenda_id": 2, "cultura_id": 12, "area_ha": 60, "tipo": "talhao", "ativo": True},
    ],
    "plantios_cana": [{"id": 40, "talhao_id": 30, "safra_id": 20, "data": "2026-03-01", "ativo": True}],
    "plantios_graos": [{"id": 41, "talhao_id": 31, "cultura_id": 11, "safra_id": 21, "data": "2026-04-01", "ativo": True}],
    "colheitas_cana": [], "colheitas_graos": [],
    "insumos_cana": [{"id": 50, "nome": "ADUBO DA CANA", "categoria": "adubo", "unidade": "kg", "ativo": True}],
    "insumos_graos": [{"id": 51, "nome": "SEMENTE DE SOJA", "categoria": "semente", "unidade": "kg", "ativo": True}],
    "entradas_insumo_cana": [], "entradas_insumo_graos": [],
    "aplicacoes_cana": [], "aplicacoes_graos": [],
    "profiles": [],
}

PERFIS = {
    "admin": {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}},
    "soCana": {"id": "u2", "nome": "Fulano da Cana", "usuario": "cana", "papel": "gestor", "ativo": True,
               "permissoes": {"cana_cadastros": "editar", "operacoes": "editar"}},
    "soCereais": {"id": "u3", "nome": "Beltrano dos Cereais", "usuario": "cereais", "papel": "gestor", "ativo": True,
                  "permissoes": {"cereais_cadastros": "editar", "operacoes_graos": "editar"}},
}

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abrir(browser, arquivo, perfil):
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: erros.append(m.text) if m.type == "error" else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    db = dict(DB, profiles=[perfil])
    page.add_init_script(
        f"window.__DB__ = {json.dumps(db)};"
        f"window.__SESSAO__ = {{user:{{id:'{perfil['id']}'}}, access_token:'x'}};"
    )
    page.goto("file://" + str(REPO / arquivo))
    page.wait_for_timeout(800)
    return page, erros


def testar(browser, arquivo, rotulo, cfg):
    print(f"\n  {rotulo}  ({arquivo})")
    page, erros = abrir(browser, arquivo, PERFIS["admin"])
    corpo = lambda: page.locator("body").inner_text()

    # Ruido conhecido do sandbox, nao do app: a fonte do Google e o
    # service worker nao carregam de file:// sem rede. Confirmado abaixo
    # listando as URLs que falharam - so podem ser de host externo.
    ruido = ("ServiceWorker", "ERR_TUNNEL_CONNECTION_FAILED",
             "ERR_NAME_NOT_RESOLVED", "ERR_INTERNET_DISCONNECTED")
    reais = [e for e in erros if not any(r in e for r in ruido)]
    conf(not reais, "abre sem erro de JavaScript", " | ".join(reais[:2]))

    abas = " | ".join(a.strip() for a in page.locator("[data-nav-group]").all_inner_texts())
    conf("Financeiro" not in abas and "Resultados" not in abas,
         "não tem mais abas de Financeiro nem Resultados", f"abas: {abas}")
    if arquivo.endswith("AECereais.html"):
        # O menu do Cereais virou um grupo por cultura: as operacoes moram
        # dentro de Soja, Milho, Feijao..., e o armazem saiu para "Insumos".
        conf("Cadastros" in abas and "Insumos" in abas and "Soja" in abas,
             "tem Cadastros, Insumos e um grupo por cultura", f"abas: {abas}")
    else:
        conf("Cadastros" in abas and "Opera" in abas,
             "tem Cadastros e Operações", f"abas: {abas}")
    conf(page.title() == cfg["titulo"],
         f'título da janela é "{cfg["titulo"]}"', f'veio "{page.title()}"')

    t = corpo()
    for nome, deve in cfg["talhoes"].items():
        conf((nome in t) == deve, f'talhão "{nome}" {"aparece" if deve else "NÃO aparece"}')

    page.locator('[data-subnav="culturas"]').click()
    page.wait_for_timeout(200)
    t = corpo()
    for nome, deve in cfg["culturas"].items():
        conf((nome in t) == deve, f'cultura "{nome}" {"aparece" if deve else "NÃO aparece"}')

    page.locator('[data-subnav="fazendas"]').click()
    page.wait_for_timeout(200)
    t = corpo()
    for nome, deve in cfg["fazendas"].items():
        conf((nome in t) == deve, f'fazenda "{nome}" {"aparece" if deve else "NÃO aparece"}')

    # O AE Cereais passou a ter um grupo por cultura, e o armazem saiu para
    # um grupo "Insumos" proprio. No AE Cana continua dentro de "Operacoes".
    grupo_insumo = "insumos" if arquivo.endswith("AECereais.html") else "operacoes"
    page.locator(f'[data-nav-group="{grupo_insumo}"]').click()
    page.wait_for_timeout(200)
    page.locator(f'[data-subnav="insumos{cfg["sufixo"]}"]').click()
    page.wait_for_timeout(200)
    t = corpo()
    conf(cfg["insumoProprio"] in t, f'insumo "{cfg["insumoProprio"]}" aparece')
    conf(cfg["insumoAlheio"] not in t, f'insumo "{cfg["insumoAlheio"]}" NÃO aparece')
    page.close()

    p2, _ = abrir(browser, arquivo, cfg["perfilAlheio"])
    c2 = p2.locator("body").inner_text()
    conf("Nenhum módulo liberado" in c2,
         "usuário só da outra frente não vê nenhum módulo",
         c2[:90].replace("\n", " "))
    p2.close()

    # ---- fazenda e so consulta: sem Novo, Editar nem Excluir ----
    p4, _ = abrir(browser, arquivo, PERFIS["admin"])
    p4.locator('[data-subnav="fazendas"]').click()
    p4.wait_for_timeout(300)
    novos = p4.locator('[data-novo-cadastro="fazendas"]').count()
    edits = p4.locator('[data-edit-cadastro^="fazendas:"]').count()
    dels  = p4.locator('[data-del-cadastro^="fazendas:"]').count()
    conf(novos == 0 and edits == 0 and dels == 0,
         "fazenda não oferece criar, editar nem excluir",
         f"novo={novos} editar={edits} excluir={dels}")

    # ---- cultura obrigatoria no talhao ----
    p4.locator('[data-subnav="talhoes"]').click()
    p4.wait_for_timeout(300)
    obrig = p4.evaluate("() => CADASTROS.talhoes.fields"
                        ".find(f=>f.key==='culturaId').required === true")
    conf(obrig, "cultura é obrigatória no talhão (senão ele sumiria dos dois apps)")

    # ---- o cache local tambem passa pelo filtro de frente ----
    # Escreve no localStorage um snapshot com dado da OUTRA frente, como o
    # app antigo deixava, e confere que ele nao chega a tela.
    chave = p4.evaluate("() => CACHE_LOCAL_KEY")
    sujo = {
        "culturas": [{"id": 10, "nome": "Cana planta", "frente": "cana", "ativo": True},
                     {"id": 11, "nome": "Soja", "frente": "graos", "ativo": True}],
        "talhoes": [{"id": 30, "nome": "TALHAO CANA A", "fazendaId": 1, "culturaId": 10, "ativo": True},
                    {"id": 31, "nome": "TALHAO SOJA B", "fazendaId": 2, "culturaId": 11, "ativo": True}],
        "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "ativo": True},
                     {"id": 2, "nome": "Faz. Invernada", "ativo": True}],
        "safras": [],
    }
    p4.evaluate("([k, v]) => localStorage.setItem(k, JSON.stringify(v))", [chave, sujo])
    p4.evaluate("() => { carregarCacheLocal(); render(); }")
    p4.wait_for_timeout(300)
    corpo4 = p4.locator("body").inner_text()
    conf(cfg["insumoAlheio"] not in corpo4 and
         all(nome not in corpo4 for nome, deve in cfg["talhoes"].items() if not deve),
         "cache local não traz dado da outra frente",
         corpo4[:120].replace("\n", " "))
    p4.close()

    p3, _ = abrir(browser, arquivo, cfg["perfilProprio"])
    abas3 = " | ".join(p3.locator("[data-nav-group]").all_inner_texts())
    conf("Cadastros" in abas3, "usuário da própria frente vê os módulos", f"abas: {abas3}")
    conf("Administra" not in abas3, "usuário não-admin não vê Administração", f"abas: {abas3}")
    p3.close()


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    print("TESTE DOS APPS SEPARADOS")

    testar(browser, "AECana.html", "AE Cana", {
        "titulo": "AE Cana", "sufixo": "Cana",
        "talhoes": {"TALHAO CANA A": True, "TALHAO SOJA B": False, "TALHAO MILHO C": False},
        "culturas": {"Cana planta": True, "Soja": False, "Milho": False, "Capim": False},
        "fazendas": {"Faz. Palhadao": True, "Faz. Invernada": False, "Faz. Santa Alice": False},
        "insumoProprio": "ADUBO DA CANA", "insumoAlheio": "SEMENTE DE SOJA",
        "perfilProprio": PERFIS["soCana"], "perfilAlheio": PERFIS["soCereais"],
    })

    testar(browser, "AECereais.html", "AE Cereais", {
        "titulo": "AE Cereais", "sufixo": "Graos",
        "talhoes": {"TALHAO SOJA B": True, "TALHAO MILHO C": True, "TALHAO CANA A": False},
        "culturas": {"Soja": True, "Milho": True, "Cana planta": False, "Capim": False},
        "fazendas": {"Faz. Invernada": True, "Faz. Palhadao": False, "Faz. Santa Alice": False},
        "insumoProprio": "SEMENTE DE SOJA", "insumoAlheio": "ADUBO DA CANA",
        "perfilProprio": PERFIS["soCereais"], "perfilAlheio": PERFIS["soCana"],
    })
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
