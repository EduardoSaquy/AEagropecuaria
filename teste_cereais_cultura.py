"""
AE Cereais: um grupo de menu por cultura.

Pedido do Eduardo: "realizar este modelo para cereais, mas ao inves de
cria, confinamento e pasto colocar cada cultura no lugar - soja, milho,
feijao, sorgo, feno".

O que precisa ser verdade:
  os grupos saem do CADASTRO de culturas, nao do codigo
  cultura inativa nao vira grupo
  dentro do grupo, cada tela mostra so daquela cultura
  insumo, entrada e estoque continuam compartilhados (o armazem e um so)
  o talhao segue os PLANTIOS, nao o cultura_id fixo - rotacao de safra
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Tocantins", "estado": "TO", "area_ha": 900, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "graos", "area_ha": 800}],
    "culturas": [
        {"id": 7, "nome": "Soja",   "frente": "graos", "ativo": True},
        {"id": 8, "nome": "Milho",  "frente": "graos", "ativo": True},
        {"id": 9, "nome": "Feijão", "frente": "graos", "ativo": True},
        {"id": 10, "nome": "Sorgo", "frente": "graos", "ativo": False},
        {"id": 1, "nome": "Cana",   "frente": "cana",  "ativo": True},
    ],
    "safras": [{"id": 1, "fazenda_id": 1, "cultura_id": 7, "nome": "24/25", "ativo": True},
               {"id": 2, "fazenda_id": 1, "cultura_id": 8, "nome": "25/26", "ativo": True}],
    "talhoes_areas": [
        # T-01 roda soja em 24/25 e milho em 25/26 -- tem que aparecer nos dois
        {"id": 1, "fazenda_id": 1, "nome": "T-01", "tipo": "talhao", "area_ha": 100,
         "cultura_id": 7, "ativo": True},
        # T-02 so tem plantio de feijao
        {"id": 2, "fazenda_id": 1, "nome": "T-02", "tipo": "talhao", "area_ha": 80,
         "cultura_id": 7, "ativo": True},
        # T-03 nunca foi plantado: cai pela cultura do cadastro
        {"id": 3, "fazenda_id": 1, "nome": "T-03", "tipo": "talhao", "area_ha": 50,
         "cultura_id": 8, "ativo": True},
    ],
    "plantios_graos": [
        {"id": 1, "talhao_id": 1, "safra_id": 1, "cultura_id": 7, "cultivar": "TMG 7062",
         "data_plantio": "2025-10-15", "ativo": False},
        {"id": 2, "talhao_id": 1, "safra_id": 2, "cultura_id": 8, "cultivar": "AG 8088",
         "data_plantio": "2026-02-10", "ativo": True},
        {"id": 3, "talhao_id": 2, "safra_id": 1, "cultura_id": 9, "cultivar": "Carioca",
         "data_plantio": "2025-11-01", "ativo": True},
    ],
    "colheitas_graos": [
        {"id": 1, "talhao_id": 1, "safra_id": 1, "cultura_id": 7, "data": "2026-03-01", "sacas": 5400},
        {"id": 2, "talhao_id": 2, "safra_id": 1, "cultura_id": 9, "data": "2026-02-20", "sacas": 1600},
    ],
    "insumos_graos": [{"id": 1, "nome": "Ureia", "unidade": "kg", "categoria": "fertilizante", "ativo": True}],
    "entradas_insumo_graos": [{"id": 1, "insumo_id": 1, "data": "2026-01-05", "quantidade": 10000}],
    "aplicacoes_graos": [
        {"id": 1, "talhao_id": 1, "insumo_id": 1, "data": "2026-02-15",
         "tipo_operacao": "adubacao", "quantidade": 3000},
        {"id": 2, "talhao_id": 2, "insumo_id": 1, "data": "2025-11-20",
         "tipo_operacao": "adubacao", "quantidade": 900},
    ],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1200, "height": 800})
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AECereais.html"))
    page.wait_for_timeout(1100)

    print("\n  AE CEREAIS — UM GRUPO POR CULTURA")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:2]))

    # ---- os grupos ----
    print("\n  -- os grupos do menu --")
    grupos = page.evaluate("() => Object.entries(gruposAtuais()).map(([k,g]) => k + '=' + g.label)")
    conf(any(g.endswith("=Soja") for g in grupos), "existe o grupo Soja", str(grupos))
    conf(any(g.endswith("=Milho") for g in grupos), "existe o grupo Milho", str(grupos))
    conf(any(g.endswith("=Feijão") for g in grupos), "existe o grupo Feijão", str(grupos))
    conf(not any(g.endswith("=Sorgo") for g in grupos),
         "Sorgo esta inativo e NAO vira grupo", str(grupos))
    conf(not any(g.endswith("=Cana") for g in grupos),
         "Cana e de outra frente e nao entra", str(grupos))
    conf(not any("Operações" in g for g in grupos),
         "a 'Operações' unica deixou de existir", str(grupos))
    conf(any("insumos=Insumos" in g for g in grupos),
         "Insumos continua um grupo compartilhado", str(grupos))

    telas_soja = page.evaluate("() => gruposAtuais().cult7.pages.map(p => p.label)")
    conf(telas_soja == ["Talhões", "Plantio", "Colheita", "Aplicações"],
         "cada cultura tem Talhões, Plantio, Colheita e Aplicações", str(telas_soja))
    telas_ins = page.evaluate("() => gruposAtuais().insumos.pages.map(p => p.label)")
    conf(telas_ins == ["Insumos", "Entradas", "Estoque"],
         "o armazem fica fora das culturas", str(telas_ins))

    # ---- o filtro dentro do grupo ----
    print("\n  -- o que cada grupo mostra --")
    def linhas(pagina):
        page.evaluate("(p) => { state.page = p; render(); }", pagina)
        page.wait_for_timeout(200)
        return page.inner_text("body")

    soja_plantio = linhas("cult7_plantiosGraos")
    conf("TMG 7062" in soja_plantio, "Soja > Plantio mostra o plantio de soja")
    conf("AG 8088" not in soja_plantio, "e nao mostra o de milho")
    conf("Carioca" not in soja_plantio, "nem o de feijão")

    milho_plantio = linhas("cult8_plantiosGraos")
    conf("AG 8088" in milho_plantio and "TMG 7062" not in milho_plantio,
         "Milho > Plantio mostra so o de milho")

    soja_colh = linhas("cult7_colheitasGraos")
    conf("5.400" in soja_colh or "5400" in soja_colh, "Soja > Colheita traz as 5.400 sacas")
    conf("1.600" not in soja_colh and "1600" not in soja_colh,
         "e nao traz a colheita de feijão")

    # ---- rotacao: o talhao segue os plantios ----
    print("\n  -- rotacao de cultura --")
    conf(page.evaluate("() => talhaoEDaCultura(state.talhoes.find(t=>t.id===1), 7)") is True,
         "T-01 e da soja (plantio 24/25)")
    conf(page.evaluate("() => talhaoEDaCultura(state.talhoes.find(t=>t.id===1), 8)") is True,
         "T-01 TAMBEM e do milho (plantio 25/26) — rotacao")
    conf(page.evaluate("() => talhaoEDaCultura(state.talhoes.find(t=>t.id===2), 7)") is False,
         "T-02 tem cultura_id soja no cadastro mas so plantou feijao: nao e da soja")
    conf(page.evaluate("() => talhaoEDaCultura(state.talhoes.find(t=>t.id===2), 9)") is True,
         "T-02 e do feijao, pelo plantio")
    conf(page.evaluate("() => talhaoEDaCultura(state.talhoes.find(t=>t.id===3), 8)") is True,
         "T-03 nunca foi plantado: cai pela cultura do cadastro, para nao sumir")

    soja_talhoes = linhas("cult7_talhoes")
    conf("T-01" in soja_talhoes and "T-02" not in soja_talhoes,
         "Soja > Talhões traz T-01 e nao T-02")
    milho_talhoes = linhas("cult8_talhoes")
    conf("T-01" in milho_talhoes, "e o T-01 aparece TAMBEM no Milho")

    todos = linhas("talhoes")
    conf(all(x in todos for x in ["T-01", "T-02", "T-03"]),
         "Cadastros > Todos os talhões nao filtra nada")

    # ---- aplicacoes seguem o talhao ----
    apl_soja = linhas("cult7_aplicacoesGraos")
    apl_feijao = linhas("cult9_aplicacoesGraos")
    conf("3.000" in apl_soja or "3000" in apl_soja, "Soja > Aplicações traz a do T-01")
    conf("900" in apl_feijao, "Feijão > Aplicações traz a do T-02")

    # ---- novo item ja vem com a cultura ----
    print("\n  -- lancar dentro do grupo --")
    page.evaluate("() => { state.page='cult8_plantiosGraos'; render(); abrirNovoCadastro('plantiosGraos'); render(); }")
    page.wait_for_timeout(250)
    conf(page.evaluate("() => String(editDraft.culturaId)") == "8",
         "dentro de Milho, um plantio novo ja vem com Milho",
         page.evaluate("() => String(editDraft.culturaId)"))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
