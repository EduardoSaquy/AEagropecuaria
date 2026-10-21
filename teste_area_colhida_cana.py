"""
Cana: area colhida na colheita (pedido do Eduardo em 21/10/2026).

Na Palmito, 40 ha de cana planta do ano ficaram sem colher no meio dos
talhoes; pela area toda do talhao o TCH saia 24 t/ha num talhao de 102.
Campo opcional "Area colhida (ha)": em branco = talhao inteiro.
Confere o TCH do formulario, o historico do talhao (media ponderada), a
trava de area maior que o talhao e a produtividade do Matriz.
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Palmito", "estado": "SP", "area_ha": 200, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 60}],
    "culturas": [{"id": 10, "nome": "Cana", "frente": "cana", "ativo": True}],
    "safras": [],
    "talhoes_areas": [
        {"id": 30, "nome": "Talhao 1", "fazenda_id": 1, "cultura_id": 10, "area_ha": 30, "tipo": "talhao", "ativo": True},
        {"id": 31, "nome": "Talhao 2", "fazenda_id": 1, "cultura_id": 10, "area_ha": 30, "tipo": "talhao", "ativo": True},
    ],
    # Talhao 1: 10 de 30 ha colhidos (1000 t -> 100 t/ha). Talhao 2: inteiro (3000 t).
    "colheitas_cana": [
        {"id": 1, "talhao_id": 30, "data": "2026-10-20", "toneladas": 1000, "area_colhida": 10},
        {"id": 2, "talhao_id": 31, "data": "2026-10-20", "toneladas": 3000, "area_colhida": None},
        {"id": 3, "talhao_id": 30, "data": "2025-10-20", "toneladas": 2400, "area_colhida": None},
    ],
    "plantios_cana": [], "colheitas_graos": [], "plantios_graos": [],
    "insumos_cana": [], "insumos_graos": [], "entradas_insumo_cana": [], "entradas_insumo_graos": [],
    "aplicacoes_cana": [], "aplicacoes_graos": [],
    "centros_custo": [], "lancamentos_financeiros": [], "lotes": [], "funcionarios": [], "funcionario_atividades": [],
}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def abrir(pw, arquivo):
    b = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    p = b.new_page()
    erros = []
    p.on("pageerror", lambda e: erros.append(str(e)))
    p.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    p.add_init_script(STUB)
    p.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                      f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    p.goto("file://" + str(REPO / arquivo))
    p.wait_for_timeout(1200)
    return b, p, erros

with sync_playwright() as pw:
    print("\n  CANA: AREA COLHIDA")
    b, p, erros = abrir(pw, "AECana.html")
    tch = p.evaluate("() => CADASTROS.colheitasCana.fields.find(f=>f.key==='tch').compute({talhaoId:30, toneladas:1000, areaColhida:10})")
    conf(tch in ("100,00", "100"), "TCH do formulario usa a area colhida (1000 t / 10 ha)", tch)
    tch2 = p.evaluate("() => CADASTROS.colheitasCana.fields.find(f=>f.key==='tch').compute({talhaoId:30, toneladas:1200, areaColhida:''})")
    conf(tch2 in ("40,00", "40"), "em branco: area do talhao inteiro (1200 t / 30 ha)", tch2)
    conf(p.evaluate("() => CADASTROS.colheitasCana.fields.some(f=>f.key==='areaColhida' && f.type==='number')"),
         "campo 'Area colhida (ha)' no formulario da colheita")

    # historico do talhao 1: (1000 + 2400) / (10 + 30) = 85 t/ha
    p.evaluate("() => { state.modal = {type:'historicoTalhao', talhaoId:30}; render(); }")
    p.wait_for_timeout(300)
    txt = p.inner_text("body") if p.locator(".modal").count() == 0 else p.inner_text(".modal")
    conf("85,00 t/ha" in txt, "historico do talhao: TCH medio ponderado pela area colhida (85 t/ha)", txt[:400])
    conf("10,00 ha colhidos" in txt, "historico mostra a area colhida do corte parcial")

    # trava: area colhida maior que o talhao
    p.evaluate("""() => { state.modal = {type:'cadastro', key:'colheitasCana'}; editDraft = {talhaoId:30, data:'2026-10-21', toneladas:'500', areaColhida:'45'}; render(); }""")
    p.wait_for_timeout(300)
    p.evaluate("() => { window.__ESCRITAS__ = []; }")
    p.click("[data-save-cadastro='colheitasCana']"); p.wait_for_timeout(500)
    conf(p.evaluate("() => (window.__ESCRITAS__||[]).filter(e=>e.tabela==='colheitas_cana').length") == 0
         and "passa da área do talhão" in p.evaluate("() => state.cadastroError"),
         "area colhida maior que o talhao nao salva", p.evaluate("() => state.cadastroError"))
    reais = [e for e in erros if "ServiceWorker" not in e]
    conf(not reais, "AECana sem erro de JavaScript", " | ".join(reais[:3]))
    b.close()

    b, p, erros = abrir(pw, "AEMatriz.html")
    p.wait_for_timeout(800)
    area = p.evaluate("() => areaColhidaNoPeriodo('cana', {tipo:'mes', mes:'2026-10'})")
    conf(abs(area - 40) < 1e-9, "Matriz: area colhida de out/2026 = 10 (parcial) + 30 (inteiro) = 40 ha", str(area))
    prod = p.evaluate("() => produtividadeOperacaoNoPeriodo('cana', {tipo:'mes', mes:'2026-10'})")
    conf(prod and abs(prod["porHa"] - 100) < 1e-9, "Matriz: produtividade 4000 t / 40 ha = 100 t/ha", str(prod))
    reais = [e for e in erros if "ServiceWorker" not in e]
    conf(not reais, "Matriz sem erro de JavaScript", " | ".join(reais[:3]))
    b.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
