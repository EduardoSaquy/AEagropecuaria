# Prova que a paginacao do Matriz busca alem de 1.000 linhas.
# O stub imita o corte do PostgREST: devolve no maximo 1.000 por resposta,
# respeitando o range pedido. Sem paginacao, o app so veria as 1.000
# primeiras e o total viria errado.
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

N = 2760          # o volume real de lancamentos_financeiros hoje
VALOR = 100.0
lanc = [{"id": i, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1,
         "centro_custo_id": 90, "descricao": f"Despesa {i}", "valor": VALOR,
         "data": "2026-08-05", "mes": "2026-08", "areas": []} for i in range(1, N + 1)]

DB = {
    "fazendas": [{"id": 1, "nome": "F", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 100}],
    "centros_custo": [{"id": 90, "fazenda_id": None, "nome": "C", "frente": None, "ativo": True}],
    "lancamentos_financeiros": lanc,
    "insumos_cana": [], "entradas_insumo_cana": [], "aplicacoes_cana": [],
    "insumos_graos": [], "entradas_insumo_graos": [], "aplicacoes_graos": [],
    "ingredientes": [], "dietas": [], "saidas_racao": [], "pasto": [], "reproducao_custos": [],
    "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [],
    "lotes": [],
    "profiles": [{"id": "u1", "nome": "C", "usuario": "c", "papel": "admin", "ativo": True, "permissoes": {}}],
}

STUB_CORTE = Path('/tmp/lav_test/stub.js').read_text().replace(
    "return Promise.resolve({ data: r.slice(de, ate + 1), error: null });",
    # imita o teto do PostgREST: no maximo 1000 linhas por resposta
    "const fatia = r.slice(de, ate + 1).slice(0, 1000);"
    "window.__PAGINAS__ = (window.__PAGINAS__||0) + 1;"
    "return Promise.resolve({ data: fatia, error: null });"
).replace(
    "then(res) { return Promise.resolve({ data: this._aplicar(), error: null }).then(res); },",
    "then(res) { const r = this._aplicar();"
    " if(r.length > 1000) window.__TRUNCOU__ = true;"
    " return Promise.resolve({ data: r.slice(0,1000), error: null }).then(res); },"
)

def medir(pw, arquivo, expr_n, expr_total, extra_db=None):
    """Abre o app com o stub que imita o teto do PostgREST e devolve o que
    ele conseguiu carregar."""
    b = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = b.new_page()
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB_CORTE)
    db = dict(DB, **(extra_db or {}))
    page.add_init_script(f"window.__DB__={json.dumps(db)};"
                         "window.__SESSAO__={user:{id:'u1'},access_token:'x'};")
    page.goto("file:///home/claude/AEagropecuaria/" + arquivo)
    page.wait_for_timeout(3000)
    n = page.evaluate(expr_n)
    total = page.evaluate(expr_total)
    truncou = page.evaluate("() => !!window.__TRUNCOU__")
    b.close()
    return n, total, truncou


with sync_playwright() as pw:
    b = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = b.new_page()
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB_CORTE)
    page.add_init_script(f"window.__DB__={json.dumps(DB)};"
                         "window.__SESSAO__={user:{id:'u1'},access_token:'x'};")
    page.goto("file:///home/claude/AEagropecuaria/AEMatriz.html")
    page.wait_for_timeout(2500)

    n = page.evaluate("() => state.lancamentos.length")
    total = page.evaluate("() => state.lancamentos.reduce((a,l)=>a+Number(l.valor),0)")
    paginas = page.evaluate("() => window.__PAGINAS__ || 0")
    truncou = page.evaluate("() => !!window.__TRUNCOU__")
    b.close()

esperado = N * VALOR
ok = n == N and abs(total - esperado) < 0.01
print(f"\n  AE Matriz")
print(f"  linhas carregadas : {n} de {N}")
print(f"  total somado      : R$ {total:,.2f}  (esperado R$ {esperado:,.2f})")
print(f"  páginas pedidas   : {paginas}")
print(f"  alguma consulta sem paginação foi truncada: {'SIM' if truncou else 'não'}")
print(f"  {'ok — Matriz pagina' if ok else 'FALHOU — Matriz ainda corta'}")

# ---- AE Pecuaria: mesma prova, contra custos_fixos remapeados ----
DB_PEC = dict(DB)
DB_PEC.update({
    "custos_fixos": [], "receitas": [], "investimentos": [],
    "ingredientes": [], "movimentos": [], "dietas": [], "lotes": [],
    "saidas_racao": [], "pasto": [], "reproducao_custos": [],
    "precos_arroba": [], "config_financeiro": [], "partos": [], "pesagens": [],
    "producao_racao": [], "abates": [], "diagnosticos_gestacionais": [],
    "desmamas": [], "animais": [], "pesagens_animais": [], "manejos": [],
    "protocolos_inseminacao": [], "config_fazenda": [],
})
with sync_playwright() as pw:
    n2, total2, truncou2 = medir(
        pw, "AEpecuaria.html",
        "() => state.custosFixos.length",
        "() => state.custosFixos.reduce((a,l)=>a+Number(l.valorMensal),0)",
        DB_PEC)

# os 2760 lancamentos do DB sao todos atividade='cana' no teste do Matriz;
# para a pecuaria o stub filtra por atividade, entao o esperado e 0 - o que
# nao prova nada. Refaz com lancamentos de pecuaria.
lanc_pec = [dict(l, atividade="pecuaria", tipo="despesa") for l in lanc]
with sync_playwright() as pw:
    n3, total3, truncou3 = medir(
        pw, "AEpecuaria.html",
        "() => state.custosFixos.length",
        "() => state.custosFixos.reduce((a,l)=>a+Number(l.valorMensal),0)",
        dict(DB_PEC, lancamentos_financeiros=lanc_pec))

ok_pec = n3 == N and abs(total3 - esperado) < 0.01
print(f"\n  AE Pecuária")
print(f"  linhas carregadas : {n3} de {N}")
print(f"  total somado      : R$ {total3:,.2f}  (esperado R$ {esperado:,.2f})")
print(f"  {'ok — Pecuária pagina' if ok_pec else 'FALHOU — Pecuária ainda corta'}")

sys.exit(0 if (ok and ok_pec) else 1)
