"""
Lote encerrado ou zerado nao recebe lancamento.

Defeito relatado pelo Eduardo: "o lote pausado sem animais ainda da para
lancar racao pra ele e nao deveria poder".

So a tela de Venda checava isso. Racao, cocho e pasto listavam qualquer
lote do tipo certo - o custo ia parar num lote que nao existe mais.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

LOTES = [
    {"id": 1, "nome": "Curral 1 ATIVO",      "destino": "confinamento", "numero_animais": 50,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
    {"id": 2, "nome": "Curral 2 ENCERRADO",  "destino": "confinamento", "numero_animais": 40,
     "data_inicio": "2025-01-01", "data_fim": "2026-06-30", "dieta_id": 1},
    {"id": 3, "nome": "Curral 3 SEM ANIMAL", "destino": "confinamento", "numero_animais": 0,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
    {"id": 4, "nome": "Pasto 1 ATIVO",       "destino": "pasto", "numero_animais": 80,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
    {"id": 5, "nome": "Pasto 2 SEM ANIMAL",  "destino": "pasto", "numero_animais": 0,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
    {"id": 6, "nome": "Cria 1 ATIVO",        "destino": "cria", "numero_animais": 30,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
    {"id": 7, "nome": "Cria 2 ENCERRADO",    "destino": "cria", "numero_animais": 30,
     "data_inicio": "2025-01-01", "data_fim": "2026-05-01", "dieta_id": 1},
]

DB = {
    "lotes": LOTES,
    "dietas": [{"id": 1, "nome": "Dieta A", "tipo": "confinamento", "itens": []}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg"}],
    "fazendas": [{"id": 1, "nome": "Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "animais": [], "pesagens": [], "manejos": [], "movimentos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [], "producoes_racao": [], "reproducao_custos": [],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [], "abates": [],
    "custos_fixos": [], "precos_arroba": [], "investimentos": [], "receitas": [],
    "config_financeiro": [], "config_fazenda": [], "funcionarios": [],
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
    page = browser.new_page()
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_timeout(1000)

    print("\n  LOTE ENCERRADO OU ZERADO NAO RECEBE LANCAMENTO")

    # ---- a regra, direto ----
    print("\n  -- a regra --")
    for tipo, esperado in [("confinamento", ["Curral 1 ATIVO"]),
                           ("pasto",        ["Pasto 1 ATIVO"]),
                           ("reproducao",   ["Cria 1 ATIVO"])]:
        nomes = page.evaluate("(t) => lotesQueRecebem(t).map(l => l.nome)", tipo)
        conf(nomes == esperado, f"{tipo}: so o lote ativo com animais", str(nomes))

    # ---- o lote ja gravado continua na lista ao editar ----
    nomes = page.evaluate("() => lotesQueRecebem('confinamento', 2).map(l => l.nome)")
    conf("Curral 2 ENCERRADO" in nomes,
         "ao editar, o lote ja gravado continua na lista mesmo encerrado", str(nomes))
    conf("Curral 3 SEM ANIMAL" not in nomes,
         "mas os outros inelegiveis continuam de fora", str(nomes))

    # ---- o que a tela realmente oferece ----
    print("\n  -- o select de cada lancamento --")
    for tipo_modal, esperados, proibidos in [
        ("saidaRacao",     ["Curral 1 ATIVO"], ["Curral 2 ENCERRADO", "Curral 3 SEM ANIMAL"]),
        ("saidaRacaoCria", ["Cria 1 ATIVO"],   ["Cria 2 ENCERRADO"]),
        ("cocho",          ["Curral 1 ATIVO"], ["Curral 2 ENCERRADO", "Curral 3 SEM ANIMAL"]),
        ("pasto",          ["Pasto 1 ATIVO"],  ["Pasto 2 SEM ANIMAL"]),
    ]:
        # openNewModal so prepara editDraft e state.modal; quem desenha e o
        # chamador. Sem o render() o teste media um modal que nao existe.
        aberto = page.evaluate("(t) => { try { const r = openNewModal(t); render();"
                               "    return r !== false; }"
                               "  catch(e) { return 'erro: ' + e.message; } }", tipo_modal)
        page.wait_for_timeout(200)
        opcoes = page.evaluate(
            "() => [...document.querySelectorAll('#f-lote option')].map(o => o.textContent.trim())")
        for nome in esperados:
            conf(nome in opcoes, f"{tipo_modal}: oferece '{nome}'", f"opcoes={opcoes}")
        for nome in proibidos:
            conf(nome not in opcoes, f"{tipo_modal}: NAO oferece '{nome}'", f"opcoes={opcoes}")
        page.evaluate("() => { state.modal = null; render(); }")
        page.wait_for_timeout(100)

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
