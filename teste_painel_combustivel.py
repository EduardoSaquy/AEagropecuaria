"""
Indicadores do AE Combustivel no Painel do AE Matriz (pedido do Eduardo, 08/11/2026: a janelinha do Combustivel
estava sem numeros). Contas a mao, as mesmas do Painel do proprio AE Combustivel:
  - estoque = entradas - abastecimentos + ajustes, so dos tanques ATIVOS (inclusive nota com data futura);
  - consumo do mes = litros abastecidos do dia 1 ate hoje (inclusive no posto, sem tanque); mes passado fica fora;
  - custo do mes = litros x custo medio ponderado das notas do tanque ate o dia do abastecimento (nota futura nao entra;
    posto sem tanque fica sem custo);
  - alertas abertos (resolvido nao conta);
  - cada numero so aparece para quem tem a permissao do modulo no AE Combustivel; sem nenhuma, um aviso;
  - o custo NAO entra em Resultados (state.resultados.combustivelPorFrente segue vazio);
  - a janelinha cabe em 1180 e 390 px sem a pagina rolar de lado.
"""
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
HOJE = date.today()
dia = lambda n: (HOJE + timedelta(days=n)).isoformat()
DB = {
    "profiles": [ADMIN],
    "tanques": [{"id": 1, "nome": "Tanque sede", "ativo": True}, {"id": 2, "nome": "Velho", "ativo": False}],
    "entradas_estoque": [
        {"id": 1, "tanque_id": 1, "data": dia(-60), "volume_litros": 1000, "valor_total": 5000},
        {"id": 2, "tanque_id": 1, "data": dia(1), "volume_litros": 1000, "valor_total": 7000},
        {"id": 3, "tanque_id": 2, "data": dia(-60), "volume_litros": 500, "valor_total": 2500},
    ],
    "ajustes_estoque": [{"id": 1, "tanque_id": 1, "data": dia(-10), "volume_ajuste_litros": -20}],
    "abastecimentos": [
        {"id": 1, "tanque_id": 1, "data_hora": HOJE.isoformat() + "T12:00:00-03:00", "volume_litros": 200},
        {"id": 2, "tanque_id": 1, "data_hora": dia(-40) + "T12:00:00-03:00", "volume_litros": 100},
        {"id": 3, "tanque_id": None, "data_hora": HOJE.isoformat() + "T09:00:00-03:00", "volume_litros": 50},
    ],
    "alertas": [{"id": 1, "status": "aberto"}, {"id": 2, "status": "aberto"}, {"id": 3, "status": "resolvido"}],
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


def abre(browser, w, h, perfil=ADMIN):
    ctx = browser.new_context(viewport={"width": w, "height": h})
    page = ctx.new_page()
    erros = []
    page.on("pageerror", lambda e: None if "ServiceWorker" in str(e) else erros.append(str(e)))
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    db = {**DB, "profiles": [perfil]}
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => state.indicadores && state.indicadores.combustivel && state.indicadores.combustivel.loading === false", timeout=30000)
    page.wait_for_timeout(300)
    return page, erros


CARD = """() => { const c = [...document.querySelectorAll('.app-card')].find(x => x.textContent.includes('AE Combustível'));
  if(!c) return null;
  return {stats: [...c.querySelectorAll('.app-card-stat')].map(s => [s.querySelector('.l').textContent.trim(), s.querySelector('.v').textContent.trim()]),
          texto: c.textContent.replace(/\\s+/g, ' ')}; }"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    print("== admin, 1180 px")
    page, erros = abre(browser, 1180, 820)
    ind = page.evaluate("() => state.indicadores.combustivel")
    conf(ind["estoqueAtual"] == 1680, "estoque = 2000 - 300 - 20 = 1.680 L (tanque inativo fora, nota futura dentro)", str(ind))
    conf(ind["consumoMes"] == 250, "consumo do mes = 200 + 50 do posto = 250 L (mes passado fora)", str(ind))
    conf(abs(ind["custoMes"] - 1000) < 0.01, "custo do mes = 200 L x R$ 5,00 = R$ 1.000 (nota futura e posto fora)", str(ind))
    conf(ind["alertasAbertos"] == 2, "2 alertas abertos (resolvido nao conta)", str(ind))
    card = page.evaluate(CARD)
    stats = dict(card["stats"]) if card else {}
    conf(stats.get("Estoque nos tanques") == "1.680 L", "janelinha mostra o estoque", str(stats))
    conf(stats.get("Consumo no mês") == "250 L", "janelinha mostra o consumo", str(stats))
    conf(stats.get("Custo no mês") == "R$ 1.000", "janelinha mostra o custo", str(stats))
    conf(stats.get("Alertas abertos") == "2", "janelinha mostra os alertas", str(stats))
    comb = page.evaluate("() => state.resultados.combustivelPorFrente")
    conf(comb["mensal"] == [], "o custo do combustivel nao entra em Resultados", str(comb))
    larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(larg <= 0, "1180 px: a pagina nao rola de lado", str(larg))
    conf(not erros, "sem erro de JavaScript", str(erros))

    print("== admin, 390 px")
    page, erros = abre(browser, 390, 844)
    larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(larg <= 0, "390 px: a pagina nao rola de lado", str(larg))
    escondido = page.evaluate("() => getComputedStyle(document.querySelector('.painel-cartoes')).display === 'none'")
    conf(escondido, "390 px: no celular os numeros nao aparecem (so os icones, pedido de 09/11/2026)")

    print("== so abastecimento")
    so_abast = {**ADMIN, "papel": "colaborador", "permissoes": {"matriz_painel_combustivel": "visualizar", "combustivel_abastecimento": "visualizar"}}
    page, erros = abre(browser, 1180, 820, so_abast)
    stats = dict(page.evaluate(CARD)["stats"])
    conf(stats.get("Consumo no mês") == "250 L", "com Abastecimento ve o consumo", str(stats))
    conf(stats.get("Estoque nos tanques") == "—" and stats.get("Custo no mês") == "—" and stats.get("Alertas abertos") == "—",
         "sem Estoque, Rateio e Alertas ve tracos (nao 0 falso)", str(stats))
    conf(not erros, "sem erro de JavaScript", str(erros))

    print("== sem nenhum modulo do Combustivel")
    sem = {**ADMIN, "papel": "colaborador", "permissoes": {"matriz_painel_combustivel": "visualizar"}}
    page, erros = abre(browser, 1180, 820, sem)
    card = page.evaluate(CARD)
    conf(card and not card["stats"] and "Sem acesso aos módulos do AE Combustível" in card["texto"], "sem acesso: aviso no lugar dos numeros", str(card))
    conf(not erros, "sem erro de JavaScript", str(erros))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
