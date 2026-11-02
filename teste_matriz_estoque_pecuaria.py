"""
Resultados > Operacional (AEMatriz.html): "Rebanho estocado na fazenda",
pedido do Eduardo em 02/11/2026 -- UA/ha e @/ha estocadas hoje.
Peso vivo = cabecas do lote ativo x peso medio da ultima pesagem do lote;
UA = PV / 450; @ = PV x 50% / 15; valor = @ x ultimo preco da @ (femea para
lote de femeas). Lote sem pesagem fica de fora e a tela avisa. Dados
inventados.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
FOTO = sys.argv[1] if len(sys.argv) > 1 else None

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Teste", "estado": "SP", "area_ha": 500, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "pecuaria", "area_ha": 300}],
    "centros_custo": [], "lancamentos_financeiros": [],
    "lotes": [
        {"id": 1, "nome": "Curral 2", "destino": "confinamento", "sexo": "macho", "numero_animais": 120, "data_fim": None},
        {"id": 2, "nome": "Bezerros Invernada", "destino": "pasto", "sexo": "macho", "numero_animais": 90, "data_fim": None},
        {"id": 3, "nome": "Vacas 07/08", "destino": "cria", "sexo": "femea", "numero_animais": 87, "data_fim": None},
        {"id": 4, "nome": "Novilhas Eradas", "destino": "cria", "sexo": "femea", "numero_animais": 66, "data_fim": None},
        {"id": 5, "nome": "Curral 1", "destino": "confinamento", "sexo": "macho", "numero_animais": 0, "data_fim": "2026-10-30"},
    ],
    "pesagens": [
        {"id": 1, "lote_id": 1, "data": "2026-09-01", "peso_medio_kg": 420},
        {"id": 2, "lote_id": 1, "data": "2026-10-20", "peso_medio_kg": 480},   # a mais recente vale
        {"id": 3, "lote_id": 2, "data": "2026-10-10", "peso_medio_kg": 260},
        {"id": 4, "lote_id": 3, "data": "2026-10-19", "peso_medio_kg": 430},
        {"id": 5, "lote_id": 5, "data": "2026-10-01", "peso_medio_kg": 600},   # lote encerrado: fora
    ],
    "precos_arroba": [
        {"id": 1, "data": "2026-09-01", "valor": 300, "sexo": "macho"},
        {"id": 2, "data": "2026-10-25", "valor": 320, "sexo": "macho"},
        {"id": 3, "data": "2026-10-25", "valor": 300, "sexo": "femea"},
    ],
    "ingredientes": [], "dietas": [], "saidas_racao": [], "pasto": [], "reproducao_custos": [],
    "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "abates": [],
    "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [],
    "insumos_cana": [], "entradas_insumo_cana": [], "aplicacoes_cana": [],
    "insumos_graos": [], "entradas_insumo_graos": [], "aplicacoes_graos": [],
}
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))
def perto(a, b, tol=0.01): return a is not None and abs(a - b) < tol

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEMatriz.html").as_uri()); page.wait_for_timeout(1800)
    print("\n  AE MATRIZ: Resultados > Operacional > Rebanho estocado")
    conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))

    r = page.evaluate("() => estoquePecuaria()")
    conf(r is not None and not r.get("erro"), "carregou o rebanho", json.dumps(r)[:200])
    if r and not r.get("erro"):
        lotes = [x["lote"]["nome"] for x in r["linhas"]]
        conf("Curral 1" not in lotes and len(lotes) == 4, "so lotes ativos com animais (Curral 1 encerrado fica fora)", str(lotes))
        curral = next(x for x in r["linhas"] if x["lote"]["nome"] == "Curral 2")
        conf(curral["pesoMedio"] == 480, "usa a ultima pesagem do lote (480, nao 420)")
        conf(perto(curral["ua"], 120*480/450) and perto(curral["arrobas"], 120*480*0.5/15) and perto(curral["valor"], 1920*320),
             "Curral 2: UA = PV/450, @ = PV x 50%/15, valor = @ x preco da @ macho mais recente (R$ 320)")
        vacas = next(x for x in r["linhas"] if x["lote"]["nome"] == "Vacas 07/08")
        conf(perto(vacas["valor"], 87*430*0.5/15*300), "lote de femeas usa o preco da @ femea (R$ 300)")
        conf(r["cabecas"] == 363 and r["cabecasSemPeso"] == 66 and r["lotesSemPeso"] == ["Novilhas Eradas"],
             "Novilhas sem pesagem: 66 cabecas contam nas cabecas, ficam fora do peso e a tela diz qual lote")
        pv = 120*480 + 90*260 + 87*430
        conf(perto(r["pesoVivo"], pv) and perto(r["ua"], pv/450) and perto(r["arrobas"], pv*0.5/15),
             f"totais: {pv} kg PV, {pv/450:.1f} UA, {pv*0.5/15:.0f} @")
        conf(perto(r["uaPorHa"], pv/450/300) and perto(r["arrobasPorHa"], pv*0.5/15/300) and perto(r["cabecasPorHa"], 363/300),
             f"por hectare (300 ha): {pv/450/300:.2f} UA/ha, {pv*0.5/15/300:.1f} @/ha, 1,21 cab/ha")

    page.evaluate("() => { state.periodo = {tipo:'safra', safra:2025}; state.page='resultados'; state.subAbaResultados='operacional'; render(); }")
    page.wait_for_timeout(400)
    txt = page.evaluate("() => document.body.textContent")
    conf("Rebanho estocado na fazenda" in txt and "UA/ha" in txt and "@/ha" in txt and "Novilhas Eradas" in txt,
         "a tela mostra o bloco com UA/ha, @/ha e o aviso do lote sem pesagem")
    for w in (1280, 390, 320):
        page.set_viewport_size({"width": w, "height": 900}); page.wait_for_timeout(200)
        larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(larg <= 0, f"sem rolar de lado em {w} px", f"passa {larg} px")
    if FOTO:
        card = page.locator(".card", has=page.locator("text=Rebanho estocado na fazenda")).last
        page.set_viewport_size({"width": 1280, "height": 900}); page.wait_for_timeout(200)
        card.scroll_into_view_if_needed(); card.screenshot(path=FOTO + "_desktop.png")
        page.set_viewport_size({"width": 390, "height": 844}); page.wait_for_timeout(300)
        card.screenshot(path=FOTO + "_celular.png")
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
