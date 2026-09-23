"""
Pedido do Eduardo em 23/09/2026: no Painel de Resultado dos Lotes (dentro
da sub-aba Pesagem de Confinamento/Pasto/Cria), colocar o Custo/@ ao lado
da @ produzidas -- ate entao esse painel so mostrava peso inicial/atual,
ganho, GMD e @ produzidas, sem custo nenhum.

Reusa a mesma janela que o painel ja usa pra "@ produzidas" (primeira
pesagem do lote ate a ultima, nao o mes corrente -- ver
teste_custo_arroba_confinamento_janela.py, que fixou esse mesmo principio
pro Confinamento na tela Financeiro em 07/09/2026), agora generalizada
pras tres areas (Confinamento/Pasto/Cria), nao so Confinamento.

Confinamento: variavel (reproducao_custos, 1000+500=1500) + fixo alocado
(despesa de R$300/mes marcada so pra area confinamento, 10 animais ativos
-> R$1,00/animal/dia * 10 animais * 45 dias da janela = R$450) = R$1950
para 20 @ produzidas = R$97,50/@.

Pasto: sem despesa fixa cadastrada pra essa area (fixo aloca zero) --
so R$100 de custo variavel (reproducao_custos) para 3,3333 @ produzidas
= R$30,00/@ exato. Confirma que a conta generaliza pras outras areas (nao
fica presa ao Confinamento) sem quebrar quando o fixo alocado e zero.

Cria: lote sem nenhuma pesagem lancada -- confere que a linha "Nenhuma
pesagem registrada ainda" continua renderizando certo (colspan da nova
coluna) sem erro de JavaScript.
"""
import json, sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

HOJE = date.today()
PRIMEIRA_CONF = HOJE - timedelta(days=45)
CUSTO_MES_ANTERIOR = PRIMEIRA_CONF + timedelta(days=2)
CUSTO_MES_ATUAL = HOJE.replace(day=1) + timedelta(days=1)
PRIMEIRA_PASTO = HOJE - timedelta(days=10)

LOTES = [
    {"id": 20, "nome": "Curral Teste", "destino": "confinamento", "numero_animais": 10,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "macho"},
    {"id": 21, "nome": "Pasto Teste", "destino": "pasto", "numero_animais": 5,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "macho"},
    {"id": 22, "nome": "Cria Sem Pesagem", "destino": "cria", "numero_animais": 8,
     "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "femea"},
]

DB = {
    "lotes": LOTES,
    "dietas": [], "ingredientes": [],
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [], "centros_custo": [{"id": 1, "nome": "Despesas Gerais"}],
    # despesa fixa recorrente (sem "mes"), so pra area confinamento --
    # lancamentos_rateados no stub vem direto de lancamentos_financeiros
    # (ver teste_stub_supabase.js), entao e aqui que entra.
    "lancamentos_financeiros": [
        {"id": 1, "tipo": "despesa", "atividade": "pecuaria", "centro_custo_id": 1,
         "descricao": "Aluguel curral", "valor": 300.0, "mes": None, "data": None,
         "areas": ["confinamento"], "fazenda_id": None},
    ],
    "animais": [],
    "pesagens": [
        {"id": 10, "lote_id": 20, "data": PRIMEIRA_CONF.isoformat(), "peso_medio_kg": 400.0, "observacao": ""},
        {"id": 11, "lote_id": 20, "data": HOJE.isoformat(), "peso_medio_kg": 460.0, "observacao": ""},
        {"id": 12, "lote_id": 21, "data": PRIMEIRA_PASTO.isoformat(), "peso_medio_kg": 300.0, "observacao": ""},
        {"id": 13, "lote_id": 21, "data": HOJE.isoformat(), "peso_medio_kg": 320.0, "observacao": ""},
    ],
    "pesagens_animais": [],
    "manejos": [], "movimentos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [],
    "producoes_racao": [],
    "reproducao_custos": [
        {"id": 1, "lote_id": 20, "data": CUSTO_MES_ANTERIOR.isoformat(), "custo": 1000.0, "observacao": ""},
        {"id": 2, "lote_id": 20, "data": CUSTO_MES_ATUAL.isoformat(), "custo": 500.0, "observacao": ""},
        {"id": 3, "lote_id": 21, "data": (PRIMEIRA_PASTO + timedelta(days=1)).isoformat(), "custo": 100.0, "observacao": ""},
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

    print("\n  CUSTO/@ NO PAINEL DE RESULTADO DOS LOTES (Pesagem)")

    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # ---- Confinamento: variavel (1500) + fixo alocado (450) / 20 @ = 97,50 ----
    page.evaluate("""() => { state.page = 'pesagemConfinamento'; render(); }""")
    page.wait_for_timeout(300)
    linhaConf = page.evaluate("""() => {
      const linhas = [...document.querySelectorAll('table tbody tr')];
      const alvo = linhas.find(tr => tr.textContent.includes('Curral Teste'));
      return alvo ? alvo.textContent.replace(/\\s+/g,' ').trim() : null;
    }""")
    conf(linhaConf is not None and '2,00 @' in linhaConf,
         "Confinamento: @/animal = 2,00 @ (ganho 60kg / 30)", str(linhaConf))
    conf(linhaConf is not None and '20,0 @' in linhaConf,
         "Confinamento: @ produzidas = 20,0 @ (igual antes, nao mudou)", str(linhaConf))
    conf(linhaConf is not None and 'R$ 97,50' in linhaConf,
         "Confinamento: Custo/@ = R$ 97,50 (variavel 1500 + fixo 450, / 20 @)", str(linhaConf))

    # ---- Pasto: so variavel (100), sem despesa fixa cadastrada pra pasto ----
    page.evaluate("""() => { state.page = 'pesagemPasto'; render(); }""")
    page.wait_for_timeout(300)
    linhaPasto = page.evaluate("""() => {
      const linhas = [...document.querySelectorAll('table tbody tr')];
      const alvo = linhas.find(tr => tr.textContent.includes('Pasto Teste'));
      return alvo ? alvo.textContent.replace(/\\s+/g,' ').trim() : null;
    }""")
    conf(linhaPasto is not None and 'R$ 30,00' in linhaPasto,
         "Pasto: Custo/@ = R$ 30,00 (so variavel, fixo alocado = 0 nessa area) -- generaliza, nao fica preso ao Confinamento", str(linhaPasto))

    # ---- Cria: lote sem nenhuma pesagem -- linha "sem dados" nao quebra ----
    page.evaluate("""() => { state.page = 'pesagemReproducao'; render(); }""")
    page.wait_for_timeout(300)
    linhaCria = page.evaluate("""() => {
      const linhas = [...document.querySelectorAll('table tbody tr')];
      const alvo = linhas.find(tr => tr.textContent.includes('Cria Sem Pesagem'));
      return alvo ? alvo.textContent.replace(/\\s+/g,' ').trim() : null;
    }""")
    conf(linhaCria is not None and 'Nenhuma pesagem registrada ainda' in linhaCria,
         "Cria sem pesagem: linha continua mostrando o aviso, sem erro de colspan", str(linhaCria))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
