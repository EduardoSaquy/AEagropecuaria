"""
A compra de racao lancada no AE Matriz (lancamento do Financeiro ou conta a pagar) ja da a entrada no
estoque da Pecuaria (13/11/2026, decisao do Eduardo; banco: estoque_compra_01.sql, ensaiado num Postgres
descartavel). Prova o lado dos apps:
  - o bloco "Este insumo entrou no estoque da Pecuaria" so aparece em despesa / conta a pagar nos centros
    Nutricao animal e Insumos pecuarios, e some em receita, conta a receber, divisao entre atividades,
    lancamento que veio de baixa de conta, parcela 2 em diante e quando o banco nao tem a funcao;
  - trocar o centro mostra e esconde o bloco; marcar abre a data (a do lancamento) e um ingrediente;
  - salvar grava o lancamento e depois as entradas numa chamada (gravar_entradas_da_compra), com o id
    do lancamento; um ingrediente so com o valor em branco vale o total;
  - itens que passam do valor, sem ingrediente ou sem quantidade: nada e gravado e o erro aparece;
  - editar traz o que ja entrou; desmarcar e salvar tira as entradas (lista vazia);
  - conta a pagar parcelada: a entrada vai na 1a parcela, conferida contra o total da compra;
  - falha so na entrada: o aviso diz que o lancamento foi salvo e a entrada nao;
  - no AE Pecuaria a entrada que veio de compra mostra de onde veio e nao tem Editar/Excluir;
  - sem rolar de lado no celular com o bloco aberto.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

DB = {
    "fazendas": [], "fazenda_atividades": [],
    "centros_custo": [
        {"id": 95, "fazenda_id": None, "nome": "NUTRIÇÃO ANIMAL", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | Nutricao"},
        {"id": 46, "fazenda_id": None, "nome": "INSUMOS PECUÁRIOS", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | Insumos"},
        {"id": 90, "fazenda_id": None, "nome": "ADUBOS", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | Adubos"},
        {"id": 10, "fazenda_id": None, "nome": "Vendas", "frente": None, "ativo": True, "tipo": "entrada", "subcategoria": "RECEITAS | Vendas"},
    ],
    "lancamentos_financeiros": [], "lotes": [],
    "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "abates": [],
}

# o banco, em JS (o de verdade esta no SQL e foi ensaiado la)
EMULA_BANCO = """
window.__ENTRADAS__ = {};
window.__RPC__ = {
  ingredientes_para_compra: () => ({ data: [{id: 1, nome: 'Milho', unidade: 'kg'}, {id: 3, nome: 'Ureia', unidade: 'ton'}], error: null }),
  entradas_da_compra: (a) => {
    const k = a.p_lancamento ? 'l' + a.p_lancamento : 't' + a.p_titulo;
    return { data: (window.__ENTRADAS__[k] || []), error: null };
  },
  gravar_entradas_da_compra: (a) => {
    if (window.__RECUSAR_ESTOQUE__) return { data: null, error: { code: 'P0001', message: window.__RECUSAR_ESTOQUE__ } };
    const k = a.p_lancamento ? 'l' + a.p_lancamento : 't' + a.p_titulo;
    window.__ENTRADAS__[k] = a.p_itens.map(i => ({ ingrediente_id: i.ingrediente_id, quantidade: i.quantidade, valor: i.valor, data: a.p_data }));
    return { data: a.p_itens.length, error: null };
  },
  salvar_titulos: (args) => {
    const ids = [];
    for (const it of args.p_itens) {
      let id = it.id;
      if (id) { Object.assign(window.__DB__.titulos.find(x => x.id === id), it.titulo); window.__DB__.titulo_rateios = window.__DB__.titulo_rateios.filter(r => r.titulo_id !== id); }
      else { id = window.__DB__.titulos.reduce((m, x) => Math.max(m, x.id), 100) + 1; window.__DB__.titulos.push({ id, cancelado: false, valor_baixado: 0, situacao: 'aberto', ...it.titulo }); }
      for (const r of it.rateios) window.__DB__.titulo_rateios.push({ id: window.__DB__.titulo_rateios.length + 1, titulo_id: id, ...r });
      ids.push(id);
    }
    return { data: ids, error: null };
  },
};
"""

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def rpc(page, nome):
    return page.evaluate("(n) => window.__CHAMADAS_RPC__.filter(c => c.nome === n)", nome)


def tem_bloco(page):
    return page.locator("#bloco-estoque").count() > 0


def abre_lanc(page, draft):
    page.evaluate("""(d) => { window.__CHAMADAS_RPC__ = []; window.__ESCRITAS__ = []; state.erroLancamento = '';
      state.page = 'financeiro'; editDraft = d; state.modal = {type:'lancamento'}; render(); }""", draft)
    page.wait_for_timeout(250)


def abre_conta(page, draft):
    page.evaluate("""(d) => { window.__CHAMADAS_RPC__ = []; window.__ESCRITAS__ = []; state.erroTitulo = '';
      state.page = 'contas'; editDraft = d; state.modal = {type:'titulo'}; render(); }""", draft)
    page.wait_for_timeout(250)


NOVA = {"tipo": "despesa", "atividade": "pecuaria", "centroCustoId": "90", "descricao": "Milho do vizinho", "valor": "8000",
        "data": "2026-11-10", "fornecedor": "", "observacao": "", "areas": [], "loteId": "", "arrobas": "", "anoSafra": ""}

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium") if Path("/opt/pw-browsers/chromium").exists() else pw.chromium.launch()
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    erros, avisos = [], []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.accept())
    page.on("console", lambda m: avisos.append(m.text[len("[aviso] "):]) if m.text.startswith("[aviso] ") else None)
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.add_init_script(EMULA_BANCO)
    page.goto((REPO / "AEMatriz.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.centrosCusto.length > 0 && state.ingredientesCompra.length > 0", timeout=30000)
    page.wait_for_timeout(400)

    print("== quando o bloco aparece")
    abre_lanc(page, dict(NOVA))
    conf(not tem_bloco(page), "despesa em ADUBOS: sem o bloco do estoque")
    page.select_option("#f-centrocustolanc", "95")
    page.wait_for_timeout(250)
    conf(tem_bloco(page), "trocar para NUTRIÇÃO ANIMAL mostra o bloco")
    page.select_option("#f-centrocustolanc", "46")
    page.wait_for_timeout(250)
    conf(tem_bloco(page), "INSUMOS PECUÁRIOS também mostra")
    page.select_option("#f-centrocustolanc", "90")
    page.wait_for_timeout(250)
    conf(not tem_bloco(page), "voltar para ADUBOS esconde")
    abre_lanc(page, dict(NOVA, tipo="receita", centroCustoId="95"))
    conf(not tem_bloco(page), "receita: sem o bloco")
    abre_lanc(page, dict(NOVA, centroCustoId="95", atividade="dividir"))
    conf(not tem_bloco(page), "dividindo entre as atividades: sem o bloco")
    abre_lanc(page, dict(NOVA, centroCustoId="95", _editId=7, tituloBaixaId=33))
    conf(not tem_bloco(page) and "baixa da conta Nº 33" in page.inner_text(".modal"), "lançamento que veio da baixa de uma conta: sem o bloco, com o aviso de onde fica")

    print("== marcar e salvar")
    abre_lanc(page, dict(NOVA, centroCustoId="95"))
    conf(page.locator("#f-est-data").count() == 0, "desmarcado: sem os campos")
    page.check("#f-est-ligado")
    page.wait_for_timeout(250)
    dt = page.evaluate("() => document.getElementById('f-est-data').value")   # o campo mostra dd/mm/aaaa; o valor e o do banco
    conf(dt == "2026-11-10", "marcado: a data vem a do lançamento", dt)
    conf(page.locator("#f-est-ing-0").count() == 1 and page.locator("#f-est-ing-1").count() == 0, "uma linha de ingrediente")
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(500)
    conf("ingrediente" in page.inner_text(".modal") and not page.evaluate("() => window.__DB__.lancamentos_financeiros.length"),
         "sem ingrediente: avisa e não grava nada")
    page.select_option("#f-est-ing-0", "1")
    page.wait_for_timeout(200)
    page.fill("#f-est-qtd-0", "10000")
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(900)
    lancs = page.evaluate("() => window.__DB__.lancamentos_financeiros")
    g = rpc(page, "gravar_entradas_da_compra")
    conf(len(lancs) == 1, "o lançamento foi gravado", str(lancs)[:200])
    lid = lancs[0]["id"] if lancs else None
    conf(len(g) == 1 and g[0]["args"]["p_lancamento"] == lid and g[0]["args"]["p_titulo"] is None, "e depois as entradas, com o id do lançamento", str(g)[:200])
    if g:
        conf(g[0]["args"]["p_itens"] == [{"ingrediente_id": 1, "quantidade": 10000, "valor": 8000}], "um ingrediente com o valor em branco vale o total (R$ 8.000)", str(g[0]["args"]["p_itens"]))
        conf(g[0]["args"]["p_data"] == "2026-11-10", "na data informada")
    conf(page.evaluate("() => state.modal") is None, "o formulário fecha")

    print("== editar traz o que entrou; desmarcar tira")
    page.evaluate(f"() => {{ const l = state.lancamentos.find(x => x.id === {lid}); }}")
    page.evaluate(f"""() => {{ window.__CHAMADAS_RPC__ = []; state.page = 'financeiro'; render(); }}""")
    page.wait_for_timeout(300)
    page.click(f"[data-edit-lancamento='{lid}']")
    page.wait_for_timeout(600)
    conf(page.is_checked("#f-est-ligado") and page.locator("#f-est-ing-0").input_value() == "1"
         and page.locator("#f-est-qtd-0").input_value() == "10000", "editar abre com o milho e os 10.000 kg que entraram")
    page.uncheck("#f-est-ligado")
    page.wait_for_timeout(250)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(800)
    g = rpc(page, "gravar_entradas_da_compra")
    conf(len(g) == 1 and g[0]["args"]["p_itens"] == [] and g[0]["args"]["p_lancamento"] == lid, "desmarcar e salvar tira as entradas", str(g)[:200])

    print("== conferências")
    abre_lanc(page, dict(NOVA, centroCustoId="95", estoque={"ligado": True, "data": "2026-11-10",
              "itens": [{"ingredienteId": 1, "quantidade": 100, "valor": 5000}, {"ingredienteId": 3, "quantidade": 1, "valor": 3001}]}))
    n = page.evaluate("() => window.__DB__.lancamentos_financeiros.length")
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(500)
    conf("mais que a compra" in page.inner_text(".modal") and page.evaluate("() => window.__DB__.lancamentos_financeiros.length") == n,
         "itens somando R$ 8.001 numa compra de R$ 8.000: avisa e não grava")
    abre_lanc(page, dict(NOVA, centroCustoId="95", estoque={"ligado": True, "data": "2026-11-10",
              "itens": [{"ingredienteId": 1, "quantidade": 100, "valor": ""}, {"ingredienteId": 3, "quantidade": 1, "valor": 100}]}))
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(400)
    conf("Informe o valor" in page.inner_text(".modal"), "dois ingredientes com um valor em branco: pede o valor")
    abre_lanc(page, dict(NOVA, centroCustoId="95", estoque={"ligado": True, "data": "2026-11-10", "itens": [{"ingredienteId": 3, "quantidade": "", "valor": ""}]}))
    conf("Quantidade (ton)" in page.inner_text(".modal"), "ingrediente em tonelada: a quantidade diz ton")
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(400)
    conf("quantidade tem que ser maior" in page.inner_text(".modal").lower(), "sem quantidade: avisa")

    print("== falha só na entrada")
    page.evaluate("() => { window.__RECUSAR_ESTOQUE__ = 'Sem permissao para mexer nesta compra.'; }")
    abre_lanc(page, dict(NOVA, centroCustoId="95", estoque={"ligado": True, "data": "2026-11-10", "itens": [{"ingredienteId": 1, "quantidade": 50, "valor": ""}]}))
    avisos.clear()
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(900)
    conf(any("foi salvo, mas a entrada no estoque não" in a and "Sem permissao" in a for a in avisos), "o aviso diz que o lançamento foi salvo e a entrada não, com o motivo", str(avisos))
    page.evaluate("() => { window.__RECUSAR_ESTOQUE__ = null; }")

    print("== conta a pagar")
    CONTA = {"tipo": "pagar", "descricao": "Racao", "valor": "6000", "vencimento": "2026-12-10", "parcelas": 2, "intervaloTipo": "mensal",
             "previsao": False, "entidadeNome": "",
             "rateios": [{"fazendaId": "", "atividade": "pecuaria", "centroCustoId": "90", "competencia": "2026-11", "valor": 6000}]}
    abre_conta(page, dict(CONTA))
    conf(not tem_bloco(page), "conta em ADUBOS: sem o bloco")
    page.select_option("#f-rat-centro-0", "95")
    page.wait_for_timeout(300)
    conf(tem_bloco(page), "trocar o centro da conta para NUTRIÇÃO ANIMAL mostra o bloco")
    page.check("#f-est-ligado")
    page.wait_for_timeout(250)
    page.select_option("#f-est-ing-0", "1")
    page.wait_for_timeout(200)
    page.fill("#f-est-qtd-0", "7500")
    page.click("[data-save='titulo']")
    page.wait_for_timeout(1000)
    st = rpc(page, "salvar_titulos")
    g = rpc(page, "gravar_entradas_da_compra")
    ids = [i for i in page.evaluate("() => window.__DB__.titulos.map(t => t.id)")]
    conf(len(st) == 1 and len(ids) == 2, "a conta em 2 parcelas foi gravada", str(ids))
    conf(len(g) == 1 and g[0]["args"]["p_titulo"] == min(ids) and g[0]["args"]["p_lancamento"] is None, "a entrada vai na 1ª parcela", str(g)[:200])
    if g:
        conf(g[0]["args"]["p_itens"] == [{"ingrediente_id": 1, "quantidade": 7500, "valor": 6000}], "pelo total da compra (R$ 6.000), não pela parcela", str(g[0]["args"]["p_itens"]))
    abre_conta(page, dict(CONTA, tipo="receber", rateios=[dict(CONTA["rateios"][0], centroCustoId="95")]))
    conf(not tem_bloco(page), "conta a receber: sem o bloco")
    abre_conta(page, dict(CONTA, _editId=max(ids), _parcela=2, _grupo="g", parcelas=2, rateios=[dict(CONTA["rateios"][0], centroCustoId="95")]))
    conf(not tem_bloco(page), "parcela 2 em diante: sem o bloco (a entrada fica na 1ª)")

    print("== sem a função no banco")
    page.evaluate("() => { state.ingredientesCompra = []; }")
    abre_lanc(page, dict(NOVA, centroCustoId="95"))
    conf(not tem_bloco(page), "antes do SQL (sem a lista de ingredientes): nada muda no formulário")
    page.evaluate("() => carregarIngredientesCompra()")
    page.wait_for_timeout(300)
    conf(tem_bloco(page), "a lista chega e o bloco aparece no formulário aberto")

    print("== celular")
    page.set_viewport_size({"width": 390, "height": 800})
    abre_lanc(page, dict(NOVA, centroCustoId="95", estoque={"ligado": True, "data": "2026-11-10",
              "itens": [{"ingredienteId": 1, "quantidade": 100, "valor": 100}, {"ingredienteId": 3, "quantidade": 1, "valor": 100}]}))
    larg = page.evaluate("() => ({doc: document.documentElement.scrollWidth, tela: document.documentElement.clientWidth, "
                         "modal: Math.max(...[...document.querySelectorAll('#bloco-estoque *')].map(e => e.getBoundingClientRect().right))})")
    conf(larg["doc"] <= larg["tela"] and larg["modal"] <= larg["tela"] + 1, "390 px: nada passa da tela com o bloco aberto", str(larg))

    conf(not erros, "Matriz sem erro de JavaScript", "; ".join(erros[:3]))

    print("== AE Pecuária: entrada que veio de compra")
    pec = browser.new_page(viewport={"width": 1280, "height": 900})
    erros_pec = []
    pec.on("pageerror", lambda e: erros_pec.append(str(e)) if "ServiceWorker" not in str(e) else None)
    DBP = {"ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 0.8}],
           "movimentos": [{"id": 5, "data": "2026-11-10", "ingrediente_id": 1, "tipo": "entrada", "quantidade": 1000, "preco_kg": 0.8, "ajuste": False, "lancamento_id": 77, "titulo_id": None},
                          {"id": 6, "data": "2026-11-09", "ingrediente_id": 1, "tipo": "entrada", "quantidade": 500, "preco_kg": 0.8, "ajuste": False, "lancamento_id": None, "titulo_id": None}],
           "dietas": [], "lotes": [], "animais": [], "profiles": [ADMIN]}
    pec.add_init_script(STUB)
    pec.add_init_script(f"window.__DB__ = {json.dumps(DBP)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    pec.goto((REPO / "AEpecuaria.html").as_uri())
    pec.wait_for_function("() => typeof state !== 'undefined' && state.movimentos && state.movimentos.length === 2", timeout=30000)
    pec.evaluate("() => { const m = state.movimentos.find(x => x.id === 5); }")
    conf(pec.evaluate("() => state.movimentos.find(x => x.id === 5).lancamentoId") == 77, "a Pecuária lê de onde a entrada veio")
    pec.evaluate("() => { state.page = 'estoque'; state.movGruposExpandidos = {'entrada:1': true}; render(); }")
    pec.wait_for_timeout(400)
    txt = pec.inner_text("body")
    conf("Compra: lançamento Nº 77" in txt, "a entrada mostra 'Compra: lançamento Nº 77'")
    conf(pec.locator("[data-edit-mov='5']").count() == 0 and pec.locator("[data-del-mov='5']").count() == 0, "e não tem Editar nem Excluir")
    conf(pec.locator("[data-edit-mov='6']").count() == 1, "a entrada comum continua editável")
    conf(not erros_pec, "Pecuária sem erro de JavaScript", "; ".join(erros_pec[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falharam")
sys.exit(1 if falhas else 0)
