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
print(f"\n  linhas carregadas : {n} de {N}")
print(f"  total somado      : R$ {total:,.2f}  (esperado R$ {esperado:,.2f})")
print(f"  páginas pedidas   : {paginas}")
print(f"  alguma consulta sem paginação foi truncada: {'SIM' if truncou else 'não'}")
print(f"\n  {'ok — paginação funciona' if ok else 'FALHOU — ainda está cortando'}")
sys.exit(0 if ok else 1)
