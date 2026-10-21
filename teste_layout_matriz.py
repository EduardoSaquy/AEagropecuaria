"""
Sem barra de rolagem lateral no AE Matriz (pedido do Eduardo em 21/10/2026,
com print da tela Pagar/Receber: os botoes da direita sumiam atras de uma
barra de rolagem).

Abre cada tela em larguras de 1920 a 320 px e falha se a pagina ou algum
card rolar de lado. Usa os dados do teste_contas.py com textos compridos
(centro de custo, fornecedor e descricao longos, como no print).
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
src = (REPO / "teste_contas.py").read_text().split("with sync_playwright")[0]
src = src.replace('Path("/home/claude/AEagropecuaria")', 'Path(__file__).resolve().parent')
g = {"__file__": str(REPO / "teste_contas.py")}
exec(src, g)
DB, ADMIN = g["DB"], g["ADMIN"]
STUB = (REPO / "teste_stub_supabase.js").read_text()

for c in DB["centros_custo"]:
    if c["id"] == 90: c["nome"] = "MANUTENÇÃO DA FROTA DE VEÍCULOS, MAQUINAS E EQUIPAMENTOS DE CAMPO"
DB["entidades"][0]["nome"] = "LORIVAL DIVINO DE PAULA SERVIÇOS DE REFRIGERAÇÃO LTDA"
for i in range(10, 16):
    DB["titulos"].append({"id": i, "tipo": "pagar", "entidade_id": 5,
        "descricao": "SERVIÇOS PRESTADOS NO AR CONDICIONADO DO TRATOR VALTRA BH 180", "valor": 1870.0,
        "vencimento": "2026-09-10", "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False,
        "valor_baixado": 0, "situacao": "aberto"})
    DB["titulo_rateios"].append({"id": 100 + i, "titulo_id": i, "fazenda_id": 1, "atividade": "cana",
        "centro_custo_id": 90, "competencia": "2026-08", "valor": 1870.0})

LARGURAS = [1920, 1366, 1280, 1100, 1024, 800, 390, 360, 320]
PAGINAS = [("painel", ""), ("resultados", "state.subAbaResultados='geral';"),
           ("resultados", "state.subAbaResultados='operacional';"),
           ("resultados", "state.subAbaResultados='relatorios';"),
           ("resultados", "state.subAbaResultados='empresa';"),
           ("financeiro", ""), ("fazendas", ""), ("centrosCusto", ""),
           ("contas", "state.abaContas='pagar'; state.filtroContas='todos';"),
           ("financiamentos", ""), ("funcionarios", ""), ("usuarios", "")]
# Compara com clientWidth (sem a barra de rolagem vertical), como o teste_empresa.
MEDE = """() => { const out=[]; const d=document.documentElement;
  if(d.scrollWidth>d.clientWidth+1) out.push('pagina +'+(d.scrollWidth-d.clientWidth)+'px');
  document.querySelectorAll('*').forEach(el=>{ const cs=getComputedStyle(el);
    if((cs.overflowX==='auto'||cs.overflowX==='scroll') && el.clientWidth>0 && el.scrollWidth>el.clientWidth+1)
      out.push((el.className||el.tagName)+' +'+(el.scrollWidth-el.clientWidth)+'px'); });
  return out; }"""

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    print("\n  AE MATRIZ SEM ROLAR DE LADO")
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    for w in LARGURAS:
        page = browser.new_page(viewport={"width": w, "height": 900})
        page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        page.add_init_script(STUB)
        page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                             f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
        page.goto("file://" + str(REPO / "AEMatriz.html"))
        page.wait_for_timeout(1000)
        ruins = []
        for pg, extra in PAGINAS:
            page.evaluate(f"() => {{ state.modal=null; state.page='{pg}'; {extra} render(); }}")
            page.wait_for_timeout(150)
            r = page.evaluate(MEDE)
            if r: ruins.append(f"{pg} {extra.split(chr(39))[1] if extra else ''}: {r}")
        conf(not ruins, f"{w} px: nenhuma tela rola de lado ({len(PAGINAS)} telas)", " | ".join(ruins))
        page.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
