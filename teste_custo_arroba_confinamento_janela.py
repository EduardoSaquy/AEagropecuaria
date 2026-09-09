"""
Defeito relatado pelo Eduardo em 07/09/2026: no relatorio financeiro por
lote (Financeiro > Por Lote), o Custo/@ de um lote de Confinamento
aparecia "muito baixo". Causa: o ganho de peso usado pra achar @
produzida compara a pesagem mais recente ANTES do mes com a mais
recente DENTRO do mes -- se nao ha pesagem exatamente no limite do mes,
esse "ganho" pode na verdade ter se acumulado ao longo de VARIOS meses.
O custo, porem, so somava ração/pasto/cria do MES CORRENTE -- um custo
de 1 mes so dividido por uma arroba que representa 1 mes e meio de
ganho, gerando custo/@ artificialmente baixo (varios meses de custo real
ficavam de fora da conta).

Eduardo pediu explicitamente: pro Confinamento, @ produzida e custo
SEMPRE devem comparar a primeira e a ultima pesagem do lote (a mesma
janela nos dois lados da conta), nao o mes corrente.
"""
import json, sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

HOJE = date.today()
PRIMEIRA_PESAGEM = HOJE - timedelta(days=45)   # cai num mes anterior ao atual
ULTIMA_PESAGEM = HOJE                          # dentro do mes atual
CUSTO_MES_ANTERIOR = PRIMEIRA_PESAGEM + timedelta(days=2)   # ainda no mes anterior
CUSTO_MES_ATUAL = HOJE.replace(day=1) + timedelta(days=1)   # dia 2 do mes atual

LOTES = [
    {"id": 20, "nome": "Curral Teste", "destino": "confinamento", "numero_animais": 10,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "macho"},
]

DB = {
    "lotes": LOTES,
    "dietas": [], "ingredientes": [],
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "animais": [],
    "pesagens": [
        {"id": 10, "lote_id": 20, "data": PRIMEIRA_PESAGEM.isoformat(), "peso_medio_kg": 400.0, "observacao": ""},
        {"id": 11, "lote_id": 20, "data": ULTIMA_PESAGEM.isoformat(), "peso_medio_kg": 460.0, "observacao": ""},
    ],
    "pesagens_animais": [],
    "manejos": [], "movimentos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [],
    "producoes_racao": [],
    # custoReproducao(r) = Number(r.custo) direto -- uso essa tabela so pra
    # injetar um custo exato e datado, sem precisar montar dieta/ingrediente.
    # O app aplica esses lancamentos por loteId, sem restringir por tipo de
    # lote, entao serve pra simular custo de confinamento tambem.
    "reproducao_custos": [
        {"id": 1, "lote_id": 20, "data": CUSTO_MES_ANTERIOR.isoformat(), "custo": 1000.0, "observacao": "custo do mes anterior"},
        {"id": 2, "lote_id": 20, "data": CUSTO_MES_ATUAL.isoformat(), "custo": 500.0, "observacao": "custo do mes atual"},
    ],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [],
    "abates": [],
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

    print("\n  CUSTO/@ DO CONFINAMENTO USA A JANELA DA PESAGEM (NAO SO O MES)")

    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    r = page.evaluate("""() => {
      const d = custosDiariosPorLote();
      const linha = d.custosMesPorLote.find(x => x.lote.nome === 'Curral Teste');
      return linha ? {arrobas: linha.arrobas, custoPorArroba: linha.custoPorArroba, total: linha.total} : null;
    }""")
    conf(r is not None, "achou a linha do Curral Teste no relatorio por lote", str(r))
    # ganho = 460-400 = 60kg / 30 = 2 @/animal * 10 animais = 20 @
    conf(r is not None and abs(r["arrobas"] - 20) < 0.01,
         "arrobas = ganho(60kg)/30 x 10 animais = 20 @ (primeira x ultima pesagem)", str(r))
    # custo da JANELA (primeira a ultima pesagem) = 1000 (mes anterior) + 500 (mes atual) = 1500
    # custo/@ = 1500/20 = 75
    conf(r is not None and abs(r["custoPorArroba"] - 75.0) < 0.01,
         "custo/@ = 1500 (janela inteira, incluindo o mes anterior) / 20 @ = R$ 75,00", str(r))
    conf(r is not None and abs(r["custoPorArroba"] - 25.0) > 1,
         "NAO e mais R$ 25,00 (o que daria contando so os R$ 500 do mes atual)", str(r))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
