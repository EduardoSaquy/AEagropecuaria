"""
Defeito relatado pelo Eduardo em 07/09/2026: no Painel de Resultado dos
Lotes (Pesagem), um lote ja encerrado (vendido -- numero_animais zerado
pela venda) mostrava "0,0 @" produzidas mesmo tendo ganho de peso real
registrado nas pesagens (ex: Vacas de Descarte 2026, +25,1 kg no
periodo). A conta multiplicava o ganho por animal pelo numero_animais
ATUAL do lote (0, ja vendido) em vez do numero de animais que existiu
durante o periodo medido.

Corrigido com numeroAnimaisParaArroba(): lote ativo usa numero_animais
normal; lote encerrado com numero_animais zerado usa o total vendido
(state.vendas, que vem de abates.quantidade) como o efetivo do periodo.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

LOTES = [
    {"id": 10, "nome": "Vacas Encerrado", "destino": "confinamento", "numero_animais": 0,
     "data_inicio": "2026-01-01", "data_fim": "2026-08-20", "dieta_id": 1, "sexo": "femea"},
    {"id": 11, "nome": "Curral Ativo", "destino": "confinamento", "numero_animais": 89,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1, "sexo": "macho"},
]

DB = {
    "lotes": LOTES,
    "dietas": [{"id": 1, "nome": "Dieta A", "tipo": "confinamento", "itens": []}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg"}],
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "animais": [],
    "pesagens": [
        {"id": 1, "lote_id": 10, "data": "2026-07-24", "peso_medio_kg": 443.4, "observacao": ""},
        {"id": 2, "lote_id": 10, "data": "2026-08-20", "peso_medio_kg": 468.45, "observacao": "Vendida"},
        {"id": 3, "lote_id": 11, "data": "2026-07-21", "peso_medio_kg": 435.0, "observacao": ""},
        {"id": 4, "lote_id": 11, "data": "2026-09-03", "peso_medio_kg": 510.1, "observacao": ""},
    ],
    "pesagens_animais": [],
    "manejos": [], "movimentos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [], "producoes_racao": [], "reproducao_custos": [],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [],
    "abates": [
        {"id": 1, "lote_id": 10, "data": "2026-08-20", "quantidade": 47, "tipo_venda": "arroba",
         "peso_medio_kg": 468.45, "categoria": "abate", "sexo": "femea", "observacao": "Vendida - Boi Brasil"},
    ],
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
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_timeout(1200)

    print("\n  ARROBA PRODUZIDA DE LOTE ENCERRADO (VENDIDO)")

    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    r = page.evaluate("""() => {
      const l = state.lotes.find(x=>x.nome==='Vacas Encerrado');
      return {numeroAnimaisAtual: l.numeroAnimais, efetivo: numeroAnimaisParaArroba(l)};
    }""")
    conf(r["numeroAnimaisAtual"] == 0, "lote encerrado tem numero_animais atual = 0 (zerado pela venda)", str(r))
    conf(r["efetivo"] == 47, "numeroAnimaisParaArroba usa o total vendido (47), nao o atual (0)", str(r))

    r2 = page.evaluate("""() => {
      const l = state.lotes.find(x=>x.nome==='Curral Ativo');
      return {numeroAnimaisAtual: l.numeroAnimais, efetivo: numeroAnimaisParaArroba(l)};
    }""")
    conf(r2["efetivo"] == 89, "lote ativo continua usando o numero_animais normal (nao mexe nesse caminho)", str(r2))

    arroba = page.evaluate("""() => {
      const l = state.lotes.find(x=>x.nome==='Vacas Encerrado');
      const hist = pesagensDoLote(l.id);
      const ganho = Number(hist[hist.length-1].pesoMedioKg) - Number(hist[0].pesoMedioKg);
      return (ganho/KG_POR_ARROBA) * numeroAnimaisParaArroba(l);
    }""")
    conf(abs(arroba - 39.245) < 0.01,
         "@ produzidas do lote encerrado = ganho/30 x 47 = 39,2 @ (nao 0,0 @)", str(arroba))

    # ---- a tela renderizada de verdade nao mostra mais "0,0 @" pra ele ----
    page.evaluate("""() => { state.page = 'pesagemConfinamento'; render(); }""")
    page.wait_for_timeout(300)
    linhaHtml = page.evaluate("""() => {
      const linhas = [...document.querySelectorAll('table tbody tr')];
      const alvo = linhas.find(tr => tr.textContent.includes('Vacas Encerrado'));
      return alvo ? alvo.textContent.replace(/\\s+/g,' ').trim() : null;
    }""")
    conf(linhaHtml is not None and '0,0 @' not in linhaHtml,
         "a linha renderizada do lote encerrado NAO mostra '0,0 @'", str(linhaHtml))
    conf(linhaHtml is not None and '39,2 @' in linhaHtml,
         "a linha renderizada mostra '39,2 @' (arredondado de 39,245)", str(linhaHtml))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
