"""
Pedido do Eduardo em 23/09/2026: na tela "Animais do Lote" (clicar num
lote a partir de Lotes ou do Painel de Resultado), a tabela "Pesagens
deste lote" mostrava só Data/Peso médio/Observação -- sem o GMD (ganho
médio diário) entre uma pesagem e a anterior, que já existe em outro
lugar do app (lista "Todos os lançamentos" da tela Pesagem).

Adicionada a mesma coluna "GMD desde a anterior", com o mesmo cálculo
(gmdEntre, comparando cada pesagem com a imediatamente anterior no
histórico cronológico do lote -- pesagensDoLote() -- não com a ordem de
exibição da tabela, que é mais recente primeiro). Vale para qualquer
lote (Confinamento/Pasto/Cria), já que ContextoLoteDetalhe(lote,
contexto) é a mesma função pras três áreas.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

LOTES = [
    {"id": 20, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 108,
     "data_inicio": "2026-07-21", "data_fim": None, "dieta_id": None, "sexo": "macho"},
]

DB = {
    "lotes": LOTES,
    "dietas": [], "ingredientes": [],
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "animais": [],
    "pesagens": [
        {"id": 10, "lote_id": 20, "data": "2026-07-21", "peso_medio_kg": 435.0, "observacao": ""},
        {"id": 11, "lote_id": 20, "data": "2026-09-03", "peso_medio_kg": 510.1, "observacao": "Lançado via Manejo"},
        {"id": 12, "lote_id": 20, "data": "2026-09-23", "peso_medio_kg": 523.4, "observacao": "Lancado a partir da caderneta"},
    ],
    "pesagens_animais": [],
    "manejos": [], "movimentos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [],
    "producoes_racao": [], "reproducao_custos": [],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [],
    "abates": [],
    "custos_fixos": [], "precos_arroba": [], "investimentos": [], "receitas": [],
    "config_financeiro": [{"id": 1}], "config_fazenda": [], "funcionarios": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

# gmd esperado, calculado igual o app (dias corridos entre as datas)
GMD_JUL_SET = (510.1 - 435.0) / 44   # 21/07 -> 03/09 = 44 dias
GMD_SET_SET = (523.4 - 510.1) / 20   # 03/09 -> 23/09 = 20 dias

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

    print("\n  GMD ENTRE PESAGENS NA TELA 'ANIMAIS DO LOTE'")

    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    page.evaluate("""() => {
      state.loteDetalheId = 20;
      state.loteDetalheOrigem = 'pesagemConfinamento';
      state.loteDetalheContexto = 'pesagem';
      state.page = 'loteDetalhe';
      render();
    }""")
    page.wait_for_timeout(300)

    linhas = page.evaluate("""() => {
      const linhas = [...document.querySelectorAll('table tbody tr')];
      return linhas.map(tr => tr.textContent.replace(/\\s+/g,' ').trim());
    }""")
    linhaRecente = next((l for l in linhas if '23/09/2026' in l), None)
    linhaMeio = next((l for l in linhas if '03/09/2026' in l), None)
    linhaAntiga = next((l for l in linhas if '21/07/2026' in l), None)

    conf(linhaRecente is not None, "achou a linha da pesagem de 23/09/2026", str(linhas))

    def gmd_do_texto(txt):
        import re
        m = re.search(r'([+-]?\d+,\d+) kg/dia', txt or '')
        return float(m.group(1).replace(',', '.')) if m else None

    g1 = gmd_do_texto(linhaMeio)
    g2 = gmd_do_texto(linhaRecente)
    conf(g1 is not None and abs(g1 - GMD_JUL_SET) < 0.01,
         f"GMD 21/07->03/09 = {GMD_JUL_SET:.3f} kg/dia (achou {g1})", str(linhaMeio))
    conf(g2 is not None and abs(g2 - GMD_SET_SET) < 0.01,
         f"GMD 03/09->23/09 = {GMD_SET_SET:.3f} kg/dia (achou {g2})", str(linhaRecente))
    conf(linhaAntiga is not None and '—' in linhaAntiga.split('kg')[-1],
         "primeira pesagem do lote (21/07) nao tem anterior -- mostra '—'", str(linhaAntiga))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
