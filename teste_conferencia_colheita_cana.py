"""
Cana: conferencia da colheita por fazenda na safra (pedido do Eduardo, 13/11/2026: "a area colhida ate agora foi de
aproximadamente 340 hectares, nao estou achando onde esta o erro"). Os erros eram de lancamento: colheita no talhao
errado, talhao colhido sem colheita lancada e area de talhao diferente do mapa. Prova:
  - a lista de colheitas mostra a area que entra na conta ("(inteiro)" quando o campo ficou em branco);
  - a tabela de conferencia, por fazenda: area de cana, soma dos talhoes (com aviso quando nao fecha), area colhida na
    safra (cada talhao uma vez, pela maior area), toneladas, TCH e os talhoes sem colheita na safra;
  - a safra segue o campo "Safra" da colheita e, em branco, maio a abril; colheita de outra safra nao entra;
  - talhao "Historico ..." e talhao inativo ficam fora; trocar a safra no seletor refaz a tabela;
  - no celular a tabela rola dentro do card, a pagina nao rola de lado.
"""
import json
from datetime import date
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}
HOJE = date.today()
SAFRA = HOJE.year if HOJE.month >= 5 else HOJE.year - 1          # safra corrente (maio a abril)
D = lambda mes, ano=SAFRA: f"{ano}-{mes:02d}-10"                  # dia 10 do mes, no ano da safra

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Alfa", "estado": "SP", "area_ha": 200, "ativo": True},
                 {"id": 2, "nome": "Faz. Beta", "estado": "SP", "area_ha": 90, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 60},
                           {"id": 2, "fazenda_id": 2, "atividade": "cana", "area_ha": 50}],
    "culturas": [{"id": 10, "nome": "Cana", "frente": "cana", "ativo": True}],
    "safras": [],
    "talhoes_areas": [
        {"id": 30, "nome": "Talhão 1", "fazenda_id": 1, "cultura_id": 10, "area_ha": 30, "tipo": "talhao", "ativo": True},
        {"id": 31, "nome": "Talhão 2", "fazenda_id": 1, "cultura_id": 10, "area_ha": 30, "tipo": "talhao", "ativo": True},
        {"id": 32, "nome": "Histórico 2025", "fazenda_id": 1, "cultura_id": 10, "area_ha": 99, "tipo": "talhao", "ativo": True},
        {"id": 40, "nome": "Talhão 1", "fazenda_id": 2, "cultura_id": 10, "area_ha": 25, "tipo": "talhao", "ativo": True},
        {"id": 41, "nome": "Talhão 2", "fazenda_id": 2, "cultura_id": 10, "area_ha": 31, "tipo": "talhao", "ativo": True},  # soma 56 x 50 da fazenda
        {"id": 42, "nome": "Talhão 9", "fazenda_id": 2, "cultura_id": 10, "area_ha": 7, "tipo": "talhao", "ativo": False},
    ],
    "colheitas_cana": [
        # Alfa: T1 parcial 10 ha (1000 t) + 2o corte com 12 ha (600 t) -> conta 12 ha; T2 inteiro (3000 t)
        {"id": 1, "talhao_id": 30, "data": D(6), "toneladas": 1000, "area_colhida": 10},
        {"id": 2, "talhao_id": 30, "data": D(9), "toneladas": 600, "area_colhida": 12},
        {"id": 3, "talhao_id": 31, "data": D(7), "toneladas": 3000, "area_colhida": None},
        # historico e safra passada: fora
        {"id": 4, "talhao_id": 32, "data": D(8), "toneladas": 9000, "area_colhida": None},
        {"id": 5, "talhao_id": 40, "data": D(8, SAFRA - 1), "toneladas": 2000, "area_colhida": None},
        # Beta: abril do ano seguinte, mas marcado como desta safra -> entra; T2 sem colheita na safra
        {"id": 6, "talhao_id": 40, "data": f"{SAFRA}-04-13", "toneladas": 2500, "area_colhida": None, "ano_safra": SAFRA},
    ],
    "plantios_cana": [], "colheitas_graos": [], "plantios_graos": [],
    "insumos_cana": [], "insumos_graos": [], "entradas_insumo_cana": [], "entradas_insumo_graos": [],
    "aplicacoes_cana": [], "aplicacoes_graos": [],
    "centros_custo": [], "lancamentos_financeiros": [], "lotes": [], "funcionarios": [], "funcionario_atividades": [],
}

passes = falhas = 0


def conf(ok, nome, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {nome}")
    else:
        falhas += 1
        print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))


def abrir(browser, w=1280, h=900):
    p = browser.new_page(viewport={"width": w, "height": h})
    erros = []
    p.on("pageerror", lambda e: None if "ServiceWorker" in str(e) else erros.append(str(e)))
    p.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    p.add_init_script(STUB)
    p.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                      f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    p.goto("file://" + str(REPO / "AECana.html"))
    p.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.colheitasCana && state.colheitasCana.length > 0", timeout=30000)
    p.evaluate("() => { state.page = 'colheitasCana'; render(); }")
    p.wait_for_timeout(400)
    return p, erros


LINHA = """(id) => { const tr = document.querySelector(`[data-fazenda-conferencia="${id}"]`); return tr ? [...tr.children].map(td => td.innerText.trim()) : null; }"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    print(f"\n  CANA: CONFERENCIA DA COLHEITA (safra {SAFRA}/{SAFRA + 1})")
    p, erros = abrir(browser)
    conf(p.locator("[data-conferencia-colheita]").count() == 1, "a tela de Colheita tem a conferencia por fazenda")
    cab = p.evaluate("() => [...document.querySelectorAll('table')].pop().querySelector('thead').innerText")
    conf("área colhida" in cab.lower(), "a lista de colheitas ganhou a coluna 'Área colhida (ha)'", cab)
    corpo = p.evaluate("() => [...document.querySelectorAll('table')].pop().querySelector('tbody').innerText")
    conf("(inteiro)" in corpo, "colheita com o campo em branco mostra a area do talhao com '(inteiro)'", corpo[:300])
    conf("12,00" in corpo and "10,00" in corpo, "colheita com area informada mostra essa area")

    a = p.evaluate(LINHA, 1)
    conf(a is not None, "linha da Faz. Alfa", str(a))
    if a:
        conf(a[1] == "60,00 ha", "Alfa: area de cana da fazenda (Matriz > Fazendas)", a[1])
        conf(a[2] == "60,00 ha", "Alfa: soma dos talhoes sem o 'Historico' e sem aviso (fecha com a fazenda)", a[2])
        conf(a[3] == "42,00 ha", "Alfa: area colhida = T1 pela maior area dos dois cortes (12) + T2 inteiro (30)", a[3])
        conf(a[4] == "4.600,00 t", "Alfa: toneladas dos tres cortes da safra (sem o historico)", a[4])
        conf(a[5] == "109,52", "Alfa: TCH = 4.600 / 42", a[5])
        conf(a[6] == "—", "Alfa: nenhum talhao sem colheita", a[6])
    b = p.evaluate(LINHA, 2)
    conf(b is not None, "linha da Faz. Beta", str(b))
    if b:
        conf("56,00 ha" in b[2] and "+6,00 ha" in b[2], "Beta: soma dos talhoes (56) com aviso de +6 ha sobre a area de cana (50); talhao inativo fora", b[2])
        conf(b[3] == "25,00 ha", "Beta: colheita de abril marcada como desta safra entra; a da safra passada nao", b[3])
        conf("Talhão 2 (31,00 ha)" in b[6] and "Talhão 9" not in b[6], "Beta: lista o talhao sem colheita na safra (o inativo nao)", b[6])
    total = p.evaluate("() => [...document.querySelectorAll('[data-conferencia-colheita] tbody tr')].pop().innerText")
    conf("67,00 ha" in total, "total da area colhida (42 + 25)", total)

    # trocar para a safra anterior
    p.select_option("[data-safra-conferencia]", str(SAFRA - 1))
    p.wait_for_timeout(300)
    b2 = p.evaluate(LINHA, 2)
    conf(b2 is not None and b2[3] == "25,00 ha" and "2.000,00" in b2[4], "safra anterior: Beta mostra a colheita daquela safra", str(b2))
    a2 = p.evaluate(LINHA, 1)
    conf(a2 is not None and a2[3] == "0,00 ha" and "Talhão 1" in a2[6] and "Talhão 2" in a2[6], "safra anterior: Alfa sem colheita, os dois talhoes listados", str(a2))
    conf(not erros, "sem erro de JavaScript", "; ".join(erros))
    p.close()

    for w in (390, 360):
        p, erros = abrir(browser, w, 800)
        largura = p.evaluate("() => [document.documentElement.scrollWidth, document.documentElement.clientWidth]")
        conf(largura[0] <= largura[1] + 1, f"celular {w} px: a pagina nao rola de lado (a tabela rola dentro do card)", str(largura))
        p.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falharam")
raise SystemExit(1 if falhas else 0)
