"""
AE Matriz: o resultado da Pecuaria conta a COMPRA do insumo, nunca o consumo.

Decisao do Eduardo (28/10/2026): o custo financeiro da racao e a compra (ja
lancada nas despesas, centro Nutricao animal). A saida de racao (kg x preco da
dieta) serve para o custo por animal, nao para o resultado. O Matriz somava as
duas coisas e contava a racao duas vezes (R$ 99 mil de jul a out/2026). Prova:
  - despesa do mes = so o que esta lancado no Financeiro (compra incluida);
  - racao, pasto e reproducao consumidos NAO entram em despesa nem em
    despesaPorCategoria, mas continuam disponiveis em consumoGerencial;
  - o periodo agregado (Resultados) tambem nao traz "Racao (Confinamento)";
  - o resultado do mes = receita - despesa lancada.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
MES = "2026-08"

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 500, "ativo": True}],
    "fazenda_atividades": [],
    "centros_custo": [
        {"id": 90, "fazenda_id": None, "nome": "NUTRICAO ANIMAL", "frente": None, "ativo": True},
        {"id": 91, "fazenda_id": None, "nome": "Vendas", "frente": "geral", "ativo": True},
        {"id": 92, "fazenda_id": None, "nome": "SALARIOS", "frente": None, "ativo": True},
    ],
    "lancamentos_financeiros": [
        # compra de racao: JA e o custo financeiro da racao
        {"id": 1, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Compra de racao", "valor": 5000.00, "data": "2026-08-10", "mes": MES, "areas": []},
        {"id": 2, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Salarios", "valor": 3000.00, "data": "2026-08-30", "mes": MES, "areas": []},
        {"id": 3, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 91,
         "descricao": "Venda", "valor": 40000.00, "data": "2026-08-20", "mes": MES, "areas": []},
    ],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 2.00}],
    "dietas": [{"id": 1, "nome": "Dieta", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}]}],
    # consumo: 10.000 kg x R$ 2,00 = R$ 20.000 de racao; 1.000 x 2 = R$ 2.000 de pasto
    "saidas_racao": [{"id": 1, "data": "2026-08-10", "lote_id": 1, "dieta_id": 1, "quantidade_kg": 10000}],
    "pasto": [{"id": 1, "data": "2026-08-12", "dieta_id": 1, "quantidade": 1000}],
    "reproducao_custos": [{"id": 1, "data": "2026-08-15", "custo": 500}],
    "abates": [],
    "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
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
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_timeout(1200)

    print("\n  AE MATRIZ: racao consumida nao entra no resultado")
    conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))

    page.evaluate("() => carregarResultadoPecuaria()")
    page.wait_for_timeout(800)
    m = page.evaluate(
        "() => { const x = (state.resultados.pecuaria.mensal||[]).find(r=>r.mes==='%s'); return x || null; }" % MES)
    conf(m is not None, "o resultado da Pecuaria carregou o mes")
    if m:
        conf(abs(m["despesa"] - 8000.0) < 0.01,
             "despesa do mes = so o lancado (compra R$ 5.000 + salarios R$ 3.000), sem somar o consumo",
             f'veio R$ {m["despesa"]:,.2f}')
        conf(abs(m["resultado"] - 32000.0) < 0.01, "resultado do mes = receita - despesa lancada",
             f'veio R$ {m["resultado"]:,.2f}')
        conf(m["despesaPorCategoria"] == {"fixa": 8000.0},
             "despesaPorCategoria so tem a parte lancada (sem racao/pasto/reproducao)",
             json.dumps(m["despesaPorCategoria"]))
        g = m.get("consumoGerencial") or {}
        conf(abs(g.get("racao", 0) - 20000.0) < 0.01 and abs(g.get("pasto", 0) - 2000.0) < 0.01
             and abs(g.get("reproducao", 0) - 500.0) < 0.01,
             "o consumo continua calculado em consumoGerencial (racao 20.000, pasto 2.000, reproducao 500)",
             json.dumps(g))

    ag = page.evaluate("() => agregarPeriodo(state.resultados.pecuaria, ['%s'])" % MES)
    conf(abs(ag["despesa"] - 8000.0) < 0.01 and abs(ag["resultado"] - 32000.0) < 0.01,
         "periodo agregado (Resultados): despesa R$ 8.000 e resultado R$ 32.000", json.dumps(ag)[:200])
    rotulos = [d["label"] for d in ag["despesaDetalhe"]]
    conf(not any("Ração" in r or "Pasto" in r or "Reprodução" in r for r in rotulos),
         "a quebra da despesa nao mostra Racao, Pasto nem Reproducao consumidos", str(rotulos))

    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
