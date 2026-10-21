"""
GMD boi a boi (pedido do Eduardo em 21/10/2026).

O ganho pela media do lote compara grupos diferentes quando o curral e
apartado entre uma pesagem e outra: o Curral 2 mostrava +0,22 kg/dia pela
media (108 bois antes, 62 depois) e +1,02 kg/dia boi a boi. Agora, com
peso por animal, o GMD sai do mesmo animal nas duas pesagens (em qualquer
lote do mesmo tipo); sem peso por animal, continua pela media.
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

# Curral A antigo (lote 1): 4 bois pesados em 01/09 (2 leves, 2 pesados).
# Apartacao: os 2 leves vao pro Curral B (lote 2), pesados em 01/10 com +30 kg.
# A media do lote 2 nao tem pesagem anterior propria; a do lote 1 (pesados) idem.
# Vaca 101 (lote 3, cria) tem o mesmo numero de um boi: nao pode entrar.
LOTES = [
    {"id": 1, "nome": "Curral A", "destino": "confinamento", "numero_animais": 2, "data_inicio": "2026-08-01", "data_fim": None, "dieta_id": None, "sexo": "macho"},
    {"id": 2, "nome": "Curral B", "destino": "confinamento", "numero_animais": 2, "data_inicio": "2026-09-02", "data_fim": None, "dieta_id": None, "sexo": "macho"},
    {"id": 3, "nome": "Vacas",    "destino": "cria",         "numero_animais": 1, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "femea"},
    {"id": 4, "nome": "Curral C", "destino": "confinamento", "numero_animais": 10, "data_inicio": "2026-08-01", "data_fim": None, "dieta_id": None, "sexo": "macho"},
]
PESAGENS = [
    {"id": 10, "lote_id": 1, "data": "2026-09-01", "peso_medio_kg": 450.0, "observacao": ""},
    {"id": 11, "lote_id": 1, "data": "2026-10-01", "peso_medio_kg": 530.0, "observacao": ""},
    {"id": 12, "lote_id": 2, "data": "2026-10-01", "peso_medio_kg": 430.0, "observacao": ""},
    {"id": 13, "lote_id": 3, "data": "2026-09-15", "peso_medio_kg": 300.0, "observacao": ""},
    # lote so com media (sem peso por animal): continua pela media
    {"id": 14, "lote_id": 4, "data": "2026-09-01", "peso_medio_kg": 400.0, "observacao": ""},
    {"id": 15, "lote_id": 4, "data": "2026-10-01", "peso_medio_kg": 430.0, "observacao": ""},
]
PA = [
    # 01/09 no Curral A: 101=400, 102=400, 201=500, 202=500
    {"id": 1, "pesagem_id": 10, "numero_animal": "101", "peso_kg": 400},
    {"id": 2, "pesagem_id": 10, "numero_animal": "102", "peso_kg": 400},
    {"id": 3, "pesagem_id": 10, "numero_animal": "201", "peso_kg": 500},
    {"id": 4, "pesagem_id": 10, "numero_animal": "202", "peso_kg": 500},
    # 01/10 no Curral A (so os pesados): +30 e +60 kg -> 1,0 e 2,0 kg/dia
    {"id": 5, "pesagem_id": 11, "numero_animal": "201", "peso_kg": 530},
    {"id": 6, "pesagem_id": 11, "numero_animal": "202", "peso_kg": 560},
    # 01/10 no Curral B (os leves): +30 kg cada -> 1,0 kg/dia; 999 sem peso anterior
    {"id": 7, "pesagem_id": 12, "numero_animal": "101", "peso_kg": 430},
    {"id": 8, "pesagem_id": 12, "numero_animal": "102", "peso_kg": 430},
    {"id": 9, "pesagem_id": 12, "numero_animal": "999", "peso_kg": 430},
    # vaca 101 na Cria: nao entra no historico do boi 101
    {"id": 10, "pesagem_id": 13, "numero_animal": "101", "peso_kg": 300},
]
DB = {
    "lotes": LOTES, "pesagens": PESAGENS, "pesagens_animais": PA,
    "animais": [
        {"id": 1, "numero": "101", "lote_id": 2, "sexo": "macho", "raca": "nelore", "status": "ativo"},
        {"id": 2, "numero": "101", "lote_id": 3, "sexo": "femea", "raca": "nelore", "status": "ativo"},
    ],
    "dietas": [], "ingredientes": [],
    "fazendas": [{"id": 1, "nome": "Faz", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "manejos": [], "movimentos": [], "saidas_racao": [], "leituras_cocho": [], "pasto": [],
    "producoes_racao": [], "reproducao_custos": [], "diagnosticos_gestacionais": [], "partos": [],
    "desmamas": [], "abates": [], "custos_fixos": [], "precos_arroba": [], "investimentos": [],
    "receitas": [], "config_financeiro": [], "config_fazenda": [], "funcionarios": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

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
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_timeout(1000)
    ev = lambda js: page.evaluate(js)
    print("\n  GMD BOI A BOI")

    r = ev("() => gmdDesdeAnterior(state.lotes.find(l=>l.id===2), state.pesagens.find(p=>p.id===12))")
    conf(r and r["boiABoi"] and r["animais"] == 2 and abs(r["gmd"] - 1.0) < 1e-9,
         "lote novo apartado: GMD dos bois vindos de outro curral (2 bois, 1,0 kg/dia; 999 sem par fica de fora)", str(r))

    r = ev("() => gmdDesdeAnterior(state.lotes.find(l=>l.id===1), state.pesagens.find(p=>p.id===11))")
    conf(r and r["boiABoi"] and abs(r["gmd"] - 1.5) < 1e-9,
         "curral que perdeu os leves: 1,5 kg/dia boi a boi (pela media daria 80/30 = 2,67)", str(r))

    r = ev("() => gmdDesdeAnterior(state.lotes.find(l=>l.id===4), state.pesagens.find(p=>p.id===15))")
    conf(r and not r["boiABoi"] and abs(r["gmd"] - 1.0) < 1e-9, "sem peso por animal: continua pela media do lote", str(r))

    r = ev("() => ganhoDoLoteNaJanela(state.lotes.find(l=>l.id===1), state.pesagens.find(p=>p.id===10), state.pesagens.find(p=>p.id===11))")
    conf(r["boiABoi"] and abs(r["ganhoKg"] - 45) < 1e-9, "janela do lote: ganho = GMD boi a boi x 30 dias = 45 kg", str(r))

    h = ev("() => historicoPesoAnimal(state.lotes.find(l=>l.id===2), '101')")
    conf([x["pesoKg"] for x in h] == [400, 430], "historico do boi 101 atravessa curral e ignora a vaca 101", str(h))

    # pesagem com o mesmo numero duas vezes: ambiguo, nao entra
    ev("() => { state.pesagensAnimais = [...state.pesagensAnimais, {id:99, pesagemId:12, numeroAnimal:'102', pesoKg:999}]; }")
    r = ev("() => gmdDesdeAnterior(state.lotes.find(l=>l.id===2), state.pesagens.find(p=>p.id===12))")
    conf(r and r["animais"] == 1, "numero repetido na mesma pesagem fica de fora", str(r))
    ev("() => { state.pesagensAnimais = state.pesagensAnimais.filter(x=>x.id!==99); }")

    # tela: lista de pesagens do Confinamento mostra o metodo
    ev("() => { state.page='pesagemConfinamento'; state.listasExpandidas['pesagem-confinamento']=true; render(); }")
    page.wait_for_timeout(300)
    texto = page.inner_text("body")
    conf("boi a boi, 2" in texto and "média do lote" in texto, "lista de pesagens mostra 'boi a boi' e 'média do lote'", texto[:300] if "boi a boi" not in texto else "")
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
