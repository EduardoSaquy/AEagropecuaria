"""
Continuacao do defeito relatado pelo Eduardo em 07/09/2026 (custo/@ do
Confinamento artificialmente baixo no Financeiro > Por Lote, corrigido por
lote). Os cards de RESUMO da fazenda (Financeiro > Resumo, topo da tela)
nunca tinham teste direto em dadosFinanceiro() -- so cobertos indiretamente
via custosDiariosPorLote() (teste_custo_arroba_confinamento_janela.py).
Este arquivo cobre os dois cards ali direto:

1. "Custo por @ produzida" (Mes) -- tinha o MESMO bug do Por Lote: somava
   arroba do mes corrente pra todo lote, inclusive Confinamento, dividido
   pelo custo do mes. Corrigido em 09/09/2026 reusando
   custosDiariosPorLote() (que ja usa a janela primeira/ultima pesagem pro
   Confinamento) em vez de recalcular por conta propria.

2. "Custo por @ produzida no ano" -- a suspeita inicial (10/09/2026) era
   que o mesmo problema existia aqui: um ciclo de Confinamento que atravessa
   2+ meses seria contado em cada mes que toca, duplicando a arroba. Ao
   investigar pra corrigir, a suspeita nao se confirmou: arrobasProduzidasFazendaNoMes(mes),
   somado mes a mes (mesesAno), faz uma soma telescopica -- o "final" de um
   mes e o "inicial" do mes seguinte sempre apontam pro mesmo par de
   pesagens vizinhas, entao a soma colapsa exatamente no ganho total entre a
   primeira e a ultima pesagem do lote, sem duplicar nem faltar nada. Testado
   com 3 pesagens espalhadas em 3 meses diferentes (300kg ha 5 meses, 350kg
   ha 3 meses, 460kg hoje): resultado bateu exato com o esperado tanto no
   codigo antigo quanto tentando reescrever pela janela -- ou seja, NAO HAVIA
   bug aqui, e a tentativa de "corrigir" foi revertida (nao mexe em nada que
   ja funciona certo). Este teste fica de guarda contra uma regressao futura
   que quebre essa soma telescopica sem querer.

   Limitacao real do card do Ano (sem mudanca, nao e o que foi investigado
   agora): um lote (de qualquer tipo, nao so Confinamento) que fecha
   (data_fim) durante o ano some do calculo pra TODOS os meses, inclusive os
   que ele esteve ativo -- porque arrobasProduzidasFazendaNoMes só soma
   `!l.dataFim`, e isso e avaliado com o estado ATUAL do lote, nao o de cada
   mes passado. O custo dele (lancado por loteId em saidas_racao etc.) nao
   tem esse filtro e continua contando. Se isso importar de verdade, precisa
   de uma conta nova que junte o historico de lote encerrado -- avisar antes
   de mexer.
"""
import json, sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

HOJE = date.today()

FAZENDA = {"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

def base_db(**overrides):
    db = {
        "lotes": [], "dietas": [], "ingredientes": [], "fazendas": [FAZENDA],
        "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
        "animais": [], "pesagens": [], "pesagens_animais": [],
        "manejos": [], "movimentos": [], "saidas_racao": [],
        "leituras_cocho": [], "pasto": [], "producoes_racao": [], "reproducao_custos": [],
        "diagnosticos_gestacionais": [], "partos": [], "desmamas": [], "abates": [],
        "custos_fixos": [], "precos_arroba": [], "investimentos": [], "receitas": [],
        "config_financeiro": [{"id": 1}], "config_fazenda": [], "funcionarios": [],
    }
    db.update(overrides)
    return db

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def dados_financeiro(db):
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
        page = browser.new_page()
        erros = []
        page.on("pageerror", lambda e: erros.append(str(e)))
        page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        page.add_init_script(STUB)
        page.add_init_script(
            f"window.__DB__ = {json.dumps(dict(db, profiles=[ADMIN]))};"
            f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        page.goto("file://" + str(REPO / "AEpecuaria.html"))
        page.wait_for_timeout(1200)
        d = page.evaluate("() => dadosFinanceiro()")
        browser.close()
        return d, erros

ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")

print("\n  CARD DO MES (RESUMO) USA A JANELA DA PESAGEM NO CONFINAMENTO")
PRIMEIRA = HOJE - timedelta(days=45)
DB_MES = base_db(
    lotes=[{"id": 20, "nome": "Curral Teste", "destino": "confinamento", "numero_animais": 10,
            "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "macho"}],
    pesagens=[
        {"id": 10, "lote_id": 20, "data": PRIMEIRA.isoformat(), "peso_medio_kg": 400.0, "observacao": ""},
        {"id": 11, "lote_id": 20, "data": HOJE.isoformat(), "peso_medio_kg": 460.0, "observacao": ""},
    ],
    reproducao_custos=[
        {"id": 1, "lote_id": 20, "data": (PRIMEIRA + timedelta(days=2)).isoformat(), "custo": 1000.0, "observacao": ""},
        {"id": 2, "lote_id": 20, "data": (HOJE.replace(day=1) + timedelta(days=1)).isoformat(), "custo": 500.0, "observacao": ""},
    ],
)
d, erros = dados_financeiro(DB_MES)
conf(not [e for e in erros if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros[:3]))
# ganho = 460-400 = 60kg / 30 = 2 @/animal x 10 animais = 20 @; custo da janela = 1000+500 = 1500
conf(abs(d["arrobasMes"] - 20) < 0.01, "arrobasMes = 20 @ (janela primeira x ultima pesagem)", str(d.get("arrobasMes")))
conf(abs(d["custoPorArrobaMes"] - 75.0) < 0.01, "custoPorArrobaMes = 1500/20 = R$ 75,00 (nao R$ 25,00 do bug antigo)", str(d.get("custoPorArrobaMes")))

print("\n  CARD DO ANO (RESUMO): SOMA MES A MES JA E TELESCOPICA, SEM DUPLICAR NEM PERDER ARROBA")
P0 = HOJE - timedelta(days=150)
P1 = HOJE - timedelta(days=90)
DB_ANO = base_db(
    lotes=[{"id": 21, "nome": "Curral Multi", "destino": "confinamento", "numero_animais": 10,
            "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": None, "sexo": "macho"}],
    pesagens=[
        {"id": 20, "lote_id": 21, "data": P0.isoformat(), "peso_medio_kg": 300.0, "observacao": ""},
        {"id": 21, "lote_id": 21, "data": P1.isoformat(), "peso_medio_kg": 350.0, "observacao": ""},
        {"id": 22, "lote_id": 21, "data": HOJE.isoformat(), "peso_medio_kg": 460.0, "observacao": ""},
    ],
)
d2, erros2 = dados_financeiro(DB_ANO)
conf(not [e for e in erros2 if not any(r in e for r in ruido)], "abre sem erro de JavaScript", " | ".join(erros2[:3]))
# ganho total = 460-300 = 160kg / 30 = 5,333 @/animal x 10 animais = 53,33 @ -- espalhado
# em 3 pesagens de 3 meses diferentes, a soma mes a mes NAO deve nem duplicar
# (dar mais que 53,33) nem perder pedaco (dar menos), mesmo sem nenhum
# tratamento especial pro Confinamento nessa conta.
esperado = (460 - 300) / 30 * 10
conf(abs(d2["arrobasAno"] - esperado) < 0.01,
     f"arrobasAno = {esperado:.2f} @ (ganho total 300->460kg, 3 pesagens em 3 meses, sem duplicar nem perder)",
     str(d2.get("arrobasAno")))

conf(not [e for e in erros + erros2 if not any(r in e for r in ruido)], "sem erro de JavaScript no fluxo todo", "")

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
