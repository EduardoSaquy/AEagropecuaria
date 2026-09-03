"""
Produtividade (Resultados > Operacional) tinha que dividir a producao
pela area REALMENTE COLHIDA no periodo, nao pela area total cadastrada
em Fazendas -- relatado pelo Eduardo em 03/09/2026, apos importar
produtividade historica de cana (um talhao em reforma, sem colheita,
"diluia" o TCH pra baixo). Tambem adiciona custo por unidade produzida
(R$/t, R$/sc, R$/@), que nao existia em lugar nenhum do app antes.
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Teste", "estado": "SP", "area_ha": 500, "ativo": True}],
    # area TOTAL cadastrada de cana na fazenda: 300ha -- bem maior que o
    # que foi colhido de verdade no periodo (so 2 dos 3 talhoes colheram)
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 300}],
    "centros_custo": [{"id": 90, "fazenda_id": None, "nome": "INSUMOS AGRICOLAS", "frente": None, "ativo": True}],
    "lancamentos_financeiros": [
        {"id": 1, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Adubo", "valor": 8000.00, "data": "2026-08-05", "mes": "2026-08", "areas": []},
    ],
    "insumos_cana": [], "entradas_insumo_cana": [], "aplicacoes_cana": [],
    "insumos_graos": [], "entradas_insumo_graos": [], "aplicacoes_graos": [],
    "ingredientes": [], "dietas": [], "saidas_racao": [], "pasto": [], "reproducao_custos": [],
    "culturas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "profiles": [ADMIN],
}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(DB)};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    print("\n  RESULTADOS > OPERACIONAL -- area colhida (nao area total) + custo por unidade")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # 3 talhoes de cana: 2 colheram no periodo (100+50=150ha colhidos),
    # 1 (150ha) esta em reforma, sem colheita nenhuma -- nao pode entrar
    # na conta de produtividade
    setup = page.evaluate("""() => {
      state.talhoes = [
        {id:1, fazendaId:1, areaHa:100, culturaId:1, ativo:true},
        {id:2, fazendaId:1, areaHa:50,  culturaId:1, ativo:true},
        {id:3, fazendaId:1, areaHa:150, culturaId:1, ativo:true}, // em reforma, sem colheita
      ];
      state.colheitasCana = [
        {data:'2026-08-10', toneladas:8000, talhaoId:1},
        {data:'2026-08-15', toneladas:4500, talhaoId:2},
        {data:'2026-07-01', toneladas:9999, talhaoId:1}, // mes ANTERIOR, nao entra
      ];
      state.periodo = {tipo:'mes', mes:'2026-08'};
      return true;
    }""")
    conf(setup is True, "estado de teste montado")

    areaColhida = page.evaluate("() => areaColhidaNoPeriodo('cana', state.periodo)")
    conf(areaColhida == 150, "area colhida no periodo = 150ha (talhao 1 + 2, NAO o 3 que esta em reforma)", f"veio {areaColhida}")

    prod = page.evaluate("() => produtividadeOperacaoNoPeriodo('cana', state.periodo)")
    conf(prod is not None, "produtividadeOperacaoNoPeriodo nao retornou null")
    conf(abs(prod["total"] - 12500) < 0.01, "total colhido no periodo = 12500t (8000+4500, sem contar julho)", str(prod))
    conf(abs(prod["porHa"] - (12500/150)) < 0.01,
         "produtividade = 12500/150 = 83.33 t/ha (area COLHIDA), nao 12500/300=41.67 (area total cadastrada)",
         str(prod))
    conf(abs(prod["areaColhida"] - 150) < 0.01, "prod.areaColhida = 150 (exposto pra tela mostrar)")

    # custo por unidade: despesa do periodo (8000) / total colhido (12500)
    custo = page.evaluate("() => custoPorUnidadeProduzida(8000, produtividadeOperacaoNoPeriodo('cana', state.periodo))")
    conf(abs(custo - (8000/12500)) < 0.0001, "custo por tonelada = 8000/12500 = R$ 0,64/t", str(custo))

    # sem producao nenhuma no periodo -- custo por unidade tem que ser null
    # (nao pode dividir por zero)
    custoZero = page.evaluate("""() => {
      const prodVazio = {total:0, unidade:'t', porHa:null};
      return custoPorUnidadeProduzida(5000, prodVazio);
    }""")
    conf(custoZero is None, "sem producao no periodo, custo por unidade e null (nao divide por zero)")

    # nenhum talhao colhido no periodo -- porHa tem que ser null (nao NaN/Infinity)
    semColheita = page.evaluate("""() => {
      state.colheitasCana = [];
      return produtividadeOperacaoNoPeriodo('cana', state.periodo);
    }""")
    conf(semColheita["porHa"] is None, "sem colheita nenhuma no periodo, porHa e null (nao NaN)", str(semColheita))
    conf(semColheita["total"] == 0, "total = 0 quando nao colheu nada", str(semColheita))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
