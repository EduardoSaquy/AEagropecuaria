"""
Limitacao achada em 10/09/2026 ao revisar o card "Custo por @ produzida no
ano" (Financeiro > Resumo): um lote vendido/encerrado durante o ano corrente
sumia do calculo do ANO INTEIRO, nao so dos meses depois da venda --
arrobasProduzidasFazendaNoMes(mes) filtrava por `!lote.dataFim`, ou seja,
pelo status ATUAL do lote (avaliado hoje), nao pelo status QUE ELE TINHA
naquele mes passado. O custo desse lote (lancado por loteId em
saidas_racao/pasto/reproducao_custos, sem olhar status) continuava contando
em totalAno -- so a arroba dele sumia, inflando o custo/@ do ano sem motivo
real. Vale pra qualquer tipo de lote (Confinamento, Pasto, Cria), nao so
Confinamento.

Corrigido com loteAtivoNoMes(lote, mesStr): um lote conta pro mes se ja
tinha comecado ate o fim dele e (se ja encerrou) encerrou DEPOIS que esse
mes comecou. Junto, resolve o numero de animais pra um lote ja encerrado
(numeroAnimais fica zerado pela venda) do mesmo jeito que
numeroAnimaisParaArroba ja faz no Painel de Resultado dos Lotes -- senao o
lote aparece "ativo no mes" mas com 0 arroba mesmo assim.
"""
import json, sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

HOJE = date.today()
# lote vendido ha 3 meses -- bem antes de hoje, garante que o mes da venda
# NAO e o mes corrente (senao o teste nao provaria nada sobre meses passados)
VENDA = HOJE - timedelta(days=90)
PESAGEM_INICIAL = VENDA - timedelta(days=60)   # 2 meses antes da venda
PESAGEM_FINAL = VENDA                           # pesagem do dia da venda

LOTES = [
    {"id": 30, "nome": "Pasto Vendido", "destino": "pasto", "numero_animais": 0,
     "data_inicio": "2026-01-01", "data_fim": VENDA.isoformat(), "dieta_id": None, "sexo": "macho"},
]

DB = {
    "lotes": LOTES, "dietas": [], "ingredientes": [],
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "animais": [],
    "pesagens": [
        {"id": 30, "lote_id": 30, "data": PESAGEM_INICIAL.isoformat(), "peso_medio_kg": 300.0, "observacao": ""},
        {"id": 31, "lote_id": 30, "data": PESAGEM_FINAL.isoformat(), "peso_medio_kg": 360.0, "observacao": "Vendida"},
    ],
    "pesagens_animais": [],
    "manejos": [], "movimentos": [], "saidas_racao": [], "leituras_cocho": [], "pasto": [],
    "producoes_racao": [],
    # custoReproducao(r) = Number(r.custo) direto -- uso essa tabela so pra
    # injetar um custo exato e datado sem montar dieta/ingrediente (mesmo
    # truque usado nos outros testes desta sessao). Lancado ENQUANTO o lote
    # ainda estava ativo -- ja contava antes da correcao (nao tem filtro de
    # status), continua contando igual.
    "reproducao_custos": [
        {"id": 1, "lote_id": 30, "data": (PESAGEM_INICIAL + timedelta(days=5)).isoformat(), "custo": 800.0, "observacao": ""},
    ],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [],
    # a propria venda -- numeroAnimaisParaArroba cai pra soma de vendas
    # quando nao ha pesagens_animais por animal (mesmo criterio ja usado
    # pro Painel de Resultado dos Lotes).
    "abates": [{"id": 1, "lote_id": 30, "data": VENDA.isoformat(), "quantidade": 8, "valor_total": 12000.0,
                "comprador": "Frigorifico X", "tipo": "venda"}],
    "custos_fixos": [], "precos_arroba": [], "investimentos": [], "receitas": [],
    "config_financeiro": [{"id": 1}], "config_fazenda": [], "funcionarios": [],
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

    print("\n  CARD DO ANO CONTINUA CONTANDO A ARROBA DE LOTE JA VENDIDO NESTE ANO")

    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    d = page.evaluate("() => dadosFinanceiro()")
    # ganho = 360-300 = 60kg / 30 = 2 @/animal x 8 animais (vendidos) = 16 @
    esperado_arrobas = (360 - 300) / 30 * 8
    conf(abs(d["arrobasAno"] - esperado_arrobas) < 0.01,
         f"arrobasAno = {esperado_arrobas:.2f} @ (lote vendido ha 3 meses continua contando, nao mais 0)",
         str(d.get("arrobasAno")))
    conf(d["totalAno"] >= 800 - 0.01,
         "totalAno inclui o custo lancado quando o lote ainda estava ativo (isso ja funcionava antes)",
         str(d.get("totalAno")))
    conf(d["custoPorArrobaAno"] is not None,
         "custoPorArrobaAno nao fica None so porque o unico lote do fixture ja foi vendido",
         str(d.get("custoPorArrobaAno")))

    r = page.evaluate("""() => {
      const mes = new Date().toISOString().slice(0,7);
      return loteAtivoNoMes({dataInicio:'2026-01-01', dataFim: null}, mes);
    }""")
    conf(r is True, "loteAtivoNoMes: lote sem data_fim continua ativo em qualquer mes", str(r))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
