"""
Precos trancados no banco (seguranca_07a/07b, 12/11/2026).

Depois do 07b quem esta logado nao le mais as colunas de preco direto da tabela: a leitura vai pela visao <tabela>_leitura, que so
preenche o preco para quem pode (insumo: acesso total e consultor; venda: acesso total e Vendas; o resto: acesso total). O stub
reproduz isso: ler direto da tabela com '*' ou com a coluna de preco da erro de permissao (window.__LEITURAS_BARRADAS__) e a visao
devolve o preco vazio quando o teste manda (window.__SEM_PRECO__). Prova:
  - os cinco apps carregam e percorrem as telas sem nenhuma leitura barrada (inclusive a copia de seguranca do Matriz);
  - quem NAO ve preco edita ingrediente, entrada de estoque e inseminacao (Pecuaria), nota de diesel (Combustivel) e entrada de
    insumo (Cana) sem apagar o preco gravado; o preco medio do ingrediente nao e recalculado pelo app (fica com o banco);
  - quem nao ve o valor da venda nao ganha o botao de editar venda; o administrador ve e continua gravando o preco ao editar.
Falha no codigo anterior (leituras barradas e precos apagados ao editar).
"""
import json
import sys
from datetime import date
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
HOJE = date.today().isoformat()
passes = falhas = 0
TODAS = {"ingredientes": ["preco_kg"], "movimentos": ["preco_kg"], "abates": ["valor_arroba", "valor_por_animal", "valor_kg"],
         "reproducao_custos": ["custo"], "entradas_estoque": ["valor_total"], "manutencoes": ["custo"],
         "entradas_insumo_cana": ["preco_pago"], "entradas_insumo_graos": ["preco_pago"]}


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def perfil(i, nome, papel, permissoes=None):
    return {"id": i, "nome": nome, "usuario": nome.lower(), "papel": papel, "ativo": True, "permissoes": permissoes or {}, "frentes": []}


ADMIN = perfil("u1", "Chefe", "admin")
ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource", "net::ERR")


def abre(browser, arquivo, db, logado, sem_preco=None, largura=1280):
    ctx = browser.new_context(viewport={"width": largura, "height": 900})
    page = ctx.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("dialog", lambda d: d.accept())
    page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    perfis = (db.get("profiles") or []) + [logado]
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(db, profiles=perfis))};"
                         f"window.__SEM_PRECO__ = {json.dumps(sem_preco or {})};"
                         f"window.__SESSAO__ = {{user:{{id:{json.dumps(logado['id'])}}}, access_token:'x'}};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.perfil.id", timeout=30000)
    page.wait_for_timeout(1500)
    return ctx, page, erros


def barradas(page):
    return page.evaluate("() => window.__LEITURAS_BARRADAS__ || []")


def ir(page, pagina):
    page.evaluate(f"() => {{ state.page = {json.dumps(pagina)}; render(); }}")
    page.wait_for_timeout(400)


def db_val(page, tabela, coluna, i=0):
    return page.evaluate(f"() => (window.__DB__[{json.dumps(tabela)}]||[])[{i}]?.[{json.dumps(coluna)}]")


DB_PEC = {
    "ingredientes": [{"id": 1, "nome": "Milho", "categoria": "energetico", "unidade": "kg", "ms": 88, "pb": 9, "ndt": 80, "preco_kg": 1.5, "estoque_min": 0}],
    "movimentos": [{"id": 1, "ingrediente_id": 1, "tipo": "entrada", "data": HOJE, "quantidade": 100, "preco_kg": 1.5, "ajuste": False}],
    "dietas": [], "lotes": [{"id": 1, "nome": "Vacas", "destino": "cria", "tipo": "reproducao", "numero_animais": 10, "data_inicio": "2026-01-01", "sexo": "femea"}],
    "animais": [{"id": 1, "numero": "10", "sexo": "femea", "lote_id": 1, "raca": "nelore", "status": "ativo"}],
    "reproducao_custos": [{"id": 1, "data": HOJE, "lote_id": 1, "numero_vaca": "10", "raca_touro": "Angus", "qual_inseminacao": "1", "custo": 80}],
    "abates": [{"id": 1, "data": HOJE, "lote_id": 1, "quantidade": 1, "tipo_venda": "cabeca", "valor_por_animal": 3000, "categoria": "descarte"}],
    "saidas_racao": [], "leituras_cocho": [], "pasto": [], "producoes_racao": [], "partos": [], "desmamas": [],
    "diagnosticos_gestacionais": [], "pesagens": [], "pesagens_animais": [], "precos_arroba": [], "manejos": [],
    "lancamentos_financeiros": [], "centros_custo": [], "fazendas": [], "protocolos": [],
}
OPERADOR = perfil("u7", "Curral", "operador", {"insumos": "editar", "cria": "editar", "estoque": "editar", "dietas": "visualizar"})

with sync_playwright() as p:
    browser = p.chromium.launch(executable_path="/opt/pw-browsers/chromium", args=["--no-sandbox"]) if Path("/opt/pw-browsers/chromium").exists() else p.chromium.launch()

    print("Pecuaria: quem nao ve preco")
    ctx, page, erros = abre(browser, "AEpecuaria.html", DB_PEC, OPERADOR, sem_preco=TODAS)
    for pg in ["ingredientes", "estoque", "dietas", "reproducaoGeral", "vendasGeral", "lotesReproducao"]:
        ir(page, pg)
    conf(barradas(page) == [], "nenhuma leitura de preco direto da tabela", str(barradas(page)))
    conf(page.evaluate("() => state.ingredientes[0].precoKg") is None, "o preco do ingrediente nao chega a quem nao ve")
    ir(page, "ingredientes")
    page.click('[data-edit-ing="1"]')
    page.wait_for_timeout(300)
    page.click('[data-save="ingrediente"]')
    page.wait_for_timeout(800)
    conf(db_val(page, "ingredientes", "preco_kg") == 1.5, "editar o ingrediente nao apaga o preco", str(db_val(page, "ingredientes", "preco_kg")))
    ir(page, "estoque")
    page.evaluate("() => { state.movGruposExpandidos = new Proxy({}, {get: () => true}); render(); }")
    page.wait_for_timeout(300)
    page.click('[data-edit-mov="1"]')
    page.wait_for_timeout(300)
    page.click('[data-save="movimento"]')
    page.wait_for_timeout(800)
    conf(db_val(page, "movimentos", "preco_kg") == 1.5, "editar a entrada de estoque nao apaga o preco", str(db_val(page, "movimentos", "preco_kg")))
    escritas = page.evaluate("() => window.__ESCRITAS__.filter(e => e.tabela==='ingredientes' && e.op==='update').length")
    conf(escritas == 1, "o app nao recalcula o preco medio de quem nao ve preco (fica com o banco)", f"updates em ingredientes: {escritas}")
    ir(page, "reproducaoGeral")
    if page.locator('[data-edit-reproducao="1"]').count():
        page.click('[data-edit-reproducao="1"]')
        page.wait_for_timeout(300)
        page.click('[data-save="reproducaoCusto"]')
        page.wait_for_timeout(1000)
        conf(db_val(page, "reproducao_custos", "custo") == 80, "editar a inseminacao sem ver o custo nao apaga o custo", str(db_val(page, "reproducao_custos", "custo")))
        conf(page.evaluate("() => (window.__AVISOS__||[]).some(a => /Custo do protocolo/.test(a.texto||a))") is False,
             "e nao exige o custo que a pessoa nao ve")
    else:
        conf(False, "botao de editar inseminacao aparece para quem tem Cria")
    ir(page, "vendasGeral")
    conf(page.locator("[data-edit-venda]").count() == 0, "quem nao ve o valor da venda nao edita a venda")
    conf(not [e for e in erros if not any(r in e for r in ruido)], "sem erro de JavaScript", str(erros))
    ctx.close()

    print("Pecuaria: administrador")
    ctx, page, erros = abre(browser, "AEpecuaria.html", DB_PEC, ADMIN)
    ir(page, "ingredientes")
    conf(page.evaluate("() => state.ingredientes[0].precoKg") == 1.5, "o administrador recebe o preco pela visao")
    page.click('[data-edit-ing="1"]')
    page.wait_for_timeout(300)
    page.fill("#f-preco", "2.25")
    page.click('[data-save="ingrediente"]')
    page.wait_for_timeout(800)
    conf(db_val(page, "ingredientes", "preco_kg") == 2.25, "o administrador continua gravando o preco ao editar")
    ir(page, "vendasGeral")
    conf(page.locator("[data-edit-venda]").count() == 1, "o administrador edita a venda")
    conf(barradas(page) == [], "nenhuma leitura barrada para o administrador", str(barradas(page)))
    ctx.close()

    print("Matriz")
    DB_M = {"fazendas": [], "fazenda_atividades": [], "talhoes_areas": [], "culturas": [], "centros_custo": [], "lancamentos_financeiros": [],
            "funcionarios": [], "funcionario_atividades": [], "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
            "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
            "tanques": [{"id": 1, "nome": "T1", "ativo": True, "fazenda_id": None}],
            "entradas_estoque": [{"id": 1, "tanque_id": 1, "data": HOJE, "volume_litros": 1000, "valor_total": 6000}],
            "abastecimentos": [], "ajustes_estoque": [], "alertas": [], "equipamentos": [],
            "ingredientes": DB_PEC["ingredientes"], "reproducao_custos": DB_PEC["reproducao_custos"], "abates": DB_PEC["abates"],
            "lotes": DB_PEC["lotes"], "saidas_racao": [], "pasto": [], "dietas": [], "movimentos": DB_PEC["movimentos"]}
    ctx, page, erros = abre(browser, "AEMatriz.html", DB_M, ADMIN)
    for pg in ["painel", "resultados", "financeiro", "contas", "financiamentos", "usuarios"]:
        ir(page, pg)
    page.evaluate("async () => { window.__COPIA__ = await lerTabelaParaCopia('ingredientes', ['id']); }")
    conf(page.evaluate("() => window.__COPIA__.error") is None and page.evaluate("() => window.__COPIA__.data[0].preco_kg") == 1.5,
         "a copia de seguranca le pela visao e leva o preco")
    conf(barradas(page) == [], "nenhuma leitura de preco direto da tabela", str(barradas(page)))
    conf(not [e for e in erros if not any(r in e for r in ruido)], "sem erro de JavaScript", str(erros))
    ctx.close()

    print("Combustivel: quem nao ve preco")
    FROTA = perfil("u8", "Frentista", "colaborador", {"combustivel_estoque": "editar", "combustivel_manutencao": "editar"})
    DB_C = {"tanques": [{"id": 1, "nome": "T1", "ativo": True, "fazenda_id": None, "capacidade_litros": 5000}],
            "fornecedores": [{"id": 1, "nome": "Posto", "ativo": True}],
            "entradas_estoque": [{"id": 1, "tanque_id": 1, "fornecedor_id": 1, "data": HOJE, "volume_litros": 1000, "valor_total": 6000}],
            "manutencoes": [], "equipamentos": [], "abastecimentos": [], "ajustes_estoque": [], "medicoes_fisicas": [], "alertas": [],
            "log_auditoria_combustivel": [], "funcionarios": [], "fazendas": [], "talhoes_areas": [], "culturas": [], "safras": []}
    ctx, page, erros = abre(browser, "AECombustivel.html", DB_C, FROTA, sem_preco=TODAS)
    ir(page, "entradasEstoque")
    page.click('[data-edit-cadastro="entradasEstoque:1"]')
    page.wait_for_timeout(300)
    page.click("[data-save-cadastro]")
    page.wait_for_timeout(800)
    conf(db_val(page, "entradas_estoque", "valor_total") == 6000, "editar a nota sem ver o valor nao apaga o valor nem o exige",
         str(db_val(page, "entradas_estoque", "valor_total")) + " " + str(page.evaluate("() => state.cadastroError")))
    conf(barradas(page) == [], "nenhuma leitura de preco direto da tabela", str(barradas(page)))
    ctx.close()

    print("Cana: quem nao ve preco")
    OPC = perfil("u9", "Apontador", "operador", {"operacoes": "editar", "cana_cadastros": "visualizar"})
    DB_L = {"fazendas": [], "talhoes_areas": [], "culturas": [], "safras": [], "fazenda_atividades": [],
            "insumos_cana": [{"id": 1, "nome": "Adubo", "unidade": "kg", "ativo": True}],
            "entradas_insumo_cana": [{"id": 1, "insumo_id": 1, "data": HOJE, "quantidade": 10, "preco_pago": 50, "fornecedor": "X"}],
            "aplicacoes_cana": [], "colheitas_cana": [], "centros_custo": []}
    ctx, page, erros = abre(browser, "AECana.html", DB_L, OPC, sem_preco=TODAS)
    ir(page, "entradasInsumoCana")
    page.click('[data-edit-cadastro="entradasInsumoCana:1"]')
    page.wait_for_timeout(300)
    page.click("[data-save-cadastro]")
    page.wait_for_timeout(800)
    conf(db_val(page, "entradas_insumo_cana", "preco_pago") == 50, "editar a entrada de insumo sem ver o preco nao o apaga",
         str(db_val(page, "entradas_insumo_cana", "preco_pago")))
    conf(barradas(page) == [], "nenhuma leitura de preco direto da tabela", str(barradas(page)))
    ctx.close()

    print("Cereais")
    DB_G = {"fazendas": [], "talhoes_areas": [], "culturas": [], "safras": [], "fazenda_atividades": [], "insumos_graos": [],
            "entradas_insumo_graos": [{"id": 1, "insumo_id": 1, "data": HOJE, "quantidade": 10, "preco_pago": 60}],
            "aplicacoes_graos": [], "colheitas_graos": [], "centros_custo": []}
    ctx, page, erros = abre(browser, "AECereais.html", DB_G, ADMIN)
    conf(barradas(page) == [], "nenhuma leitura de preco direto da tabela", str(barradas(page)))
    ctx.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falharam")
sys.exit(1 if falhas else 0)
