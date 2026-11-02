"""
Resultados > Operacional (AEMatriz.html): bloco "Reproducao (Cria)", pedido
do Eduardo em 02/11/2026 -- custo por bezerro desmamado, taxa de prenhez e
bezerros desmamados (machos, femeas, total) no periodo.

Custo da Cria = inseminacao + consumo de racao/pasto dos lotes de Cria +
fatia do custo fixo (despesa lancada da Pecuaria SEM a compra de racao x
cabecas na Cria / cabecas totais). Taxa de prenhez = prenhas / (prenhas +
vazias) dos diagnosticos do periodo. Dados inventados.
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
    "centros_custo": [
        {"id": 90, "fazenda_id": None, "nome": "Nutrição animal", "frente": None, "ativo": True},
        {"id": 91, "fazenda_id": None, "nome": "Vendas", "frente": "geral", "ativo": True},
        {"id": 92, "fazenda_id": None, "nome": "Salários", "frente": None, "ativo": True},
    ],
    "lancamentos_financeiros": [
        # compra de racao: fica FORA do custo do bezerro (o consumo ja entra)
        {"id": 1, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Compra de racao", "valor": 50000.00, "data": "2025-08-10", "mes": "2025-08", "areas": []},
        # fixo: 100.000 no ano-safra
        {"id": 2, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Salarios", "valor": 100000.00, "data": "2025-09-30", "mes": "2025-09", "areas": []},
        {"id": 3, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 91,
         "descricao": "Venda", "valor": 400000.00, "data": "2025-10-20", "mes": "2025-10", "areas": []},
    ],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 2.00}],
    "dietas": [{"id": 1, "nome": "Dieta", "tipo": "cria", "itens": [{"ingredienteId": 1, "pct": 100}]}],
    # lotes: 300 cabecas na Cria de 1.000 ativas -> 30% do fixo
    "lotes": [
        {"id": 1, "nome": "Vacas 07/08", "destino": "cria", "numero_animais": 200, "data_fim": None},
        {"id": 2, "nome": "Novilhas", "destino": "cria", "numero_animais": 100, "data_fim": None},
        {"id": 3, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 700, "data_fim": None},
    ],
    # racao Cria 5.000 kg x 2 = 10.000; confinamento 20.000 kg nao entra
    "saidas_racao": [
        {"id": 1, "data": "2025-07-10", "lote_id": 1, "dieta_id": 1, "quantidade_kg": 5000},
        {"id": 2, "data": "2025-07-10", "lote_id": 3, "dieta_id": 1, "quantidade_kg": 20000},
    ],
    # pasto Cria 1.000 x 2 = 2.000
    "pasto": [{"id": 1, "data": "2025-08-12", "lote_id": 2, "dieta_id": 1, "quantidade": 1000}],
    # 100 inseminacoes x 46,30 = 4.630
    "reproducao_custos": [{"id": i, "data": "2025-10-19", "lote_id": 1, "custo": 46.30} for i in range(1, 101)],
    "partos": [{"id": i, "data": "2025-06-01", "lote_id": 1, "numero_mae": str(i),
                "sexo_bezerro": "macho" if i <= 45 else "femea"} for i in range(1, 81)],
    # 80 desmamados: 45 machos, 35 femeas, 200 kg
    "desmamas": [{"id": i, "parto_id": i, "data": "2026-01-15", "peso_kg": 200} for i in range(1, 81)],
    # 85 prenhas, 15 vazias -> 85%
    "diagnosticos_gestacionais": [{"id": i, "data": "2025-12-10", "lote_id": 1, "numero_vaca": str(i),
                                   "resultado": "prenha" if i <= 85 else "vazia"} for i in range(1, 101)],
    "abates": [], "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [],
    "insumos_cana": [], "entradas_insumo_cana": [], "aplicacoes_cana": [],
    "insumos_graos": [], "entradas_insumo_graos": [], "aplicacoes_graos": [],
}
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

exe = "/opt/pw-browsers/chromium"
with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_timeout(1800)

    print("\n  AE MATRIZ: Resultados > Operacional > Reproducao (Cria)")
    conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))

    r = page.evaluate("() => reproducaoNoPeriodo({tipo:'safra', safra:2025})")
    conf(r is not None and not r.get("erro"), "carregou os dados de reproducao", json.dumps(r)[:200])
    if r and not r.get("erro"):
        conf(r["desmamados"] == 80 and r["machos"] == 45 and r["femeas"] == 35,
             "80 desmamados: 45 machos e 35 femeas", json.dumps(r))
        conf(abs(r["pesoMedio"] - 200) < 0.01, "peso medio de desmama 200 kg")
        conf(r["prenhas"] == 85 and r["vazias"] == 15 and abs(r["taxaPrenhez"] - 85) < 0.01,
             "taxa de prenhez = 85 / (85+15) = 85%")
        conf(abs(r["inseminacao"] - 4630) < 0.01, "inseminacao = 100 x 46,30 = 4.630")
        conf(abs(r["racaoPasto"] - 12000) < 0.01,
             "racao e pasto so dos lotes de Cria (10.000 + 2.000), sem o confinamento", str(r["racaoPasto"]))
        conf(abs(r["fixoPecuaria"] - 100000) < 0.01,
             "fixo da Pecuaria sem a compra de racao (100.000, nao 150.000)", str(r["fixoPecuaria"]))
        conf(abs(r["fatiaCria"] - 0.3) < 1e-9 and abs(r["fixoCria"] - 30000) < 0.01,
             "fatia do fixo = 300 / 1.000 cabecas = 30% -> 30.000")
        esperado = (4630 + 12000 + 30000) / 80
        conf(abs(r["custoPorBezerro"] - esperado) < 0.01,
             f"custo por bezerro = 46.630 / 80 = {esperado:.2f}", str(r["custoPorBezerro"]))

    m = page.evaluate("() => reproducaoNoPeriodo({tipo:'mes', mes:'2026-06'})")
    conf(m and m["desmamados"] == 0 and m["custoPorBezerro"] is None and m["taxaPrenhez"] is None,
         "mes sem desmama nem diagnostico: custo e taxa ficam '—' (sem dividir por zero)", json.dumps(m)[:200])

    page.evaluate("() => { state.periodo = {tipo:'safra', safra:2025}; state.page='resultados'; state.subAbaResultados='operacional'; render(); }")
    page.wait_for_timeout(400)
    html = page.evaluate("() => document.body.textContent")
    conf("Reprodução (Cria)" in html and "Custo por bezerro desmamado" in html and "85,0%" in html,
         "a tela mostra o bloco com custo por bezerro e taxa de prenhez 85,0%")
    conf("45 machos · 35 fêmeas" in html, "a tela mostra 45 machos · 35 femeas")

    for w in (1280, 390):
        page.set_viewport_size({"width": w, "height": 900})
        page.wait_for_timeout(200)
        larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(larg <= 0, f"sem rolar de lado em {w} px", f"passa {larg} px")

    if FOTO:
        page.set_viewport_size({"width": 1280, "height": 900})
        page.wait_for_timeout(200)
        el = page.locator("text=Reprodução (Cria)").first
        el.scroll_into_view_if_needed()
        card = page.locator(".card", has=page.locator("text=Reprodução (Cria)")).last
        card.screenshot(path=FOTO + "_desktop.png")
        page.set_viewport_size({"width": 390, "height": 844})
        page.wait_for_timeout(300)
        card.screenshot(path=FOTO + "_celular.png")

    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
