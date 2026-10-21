"""
Contas: nao lancar a mesma conta duas vezes e baixar varias de uma vez
(pedidos do Eduardo em 21/10/2026).

Conta repetida = mesmo tipo, fornecedor, valor e vencimento, em titulo nao
cancelado (pago ou em aberto). A descricao fica de fora de proposito.

Baixa em lote: caixa de selecao em cada conta em aberto com rateio, "marcar
todas" da lista, e um insert so em titulo_baixas (saldo inteiro de cada
uma), com a data do vencimento de cada conta ou uma data para todas.
"""
import json, datetime
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

HOJE = datetime.date.today()
D1 = (HOJE + datetime.timedelta(days=5)).isoformat()
D2 = (HOJE + datetime.timedelta(days=40)).isoformat()
ONTEM = (HOJE - datetime.timedelta(days=3)).isoformat()

def tit(i, ent, desc, valor, venc, **kw):
    t = {"id": i, "tipo": "pagar", "entidade_id": ent, "descricao": desc, "valor": valor,
         "vencimento": venc, "parcela": 1, "parcelas": 1, "previsao": False, "cancelado": False,
         "valor_baixado": 0, "situacao": "aberto", "conta_bancaria_id": None}
    t.update(kw); return t

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. A", "estado": "SP", "area_ha": 500, "ativo": True}],
    "fazenda_atividades": [], "lancamentos_financeiros": [], "lotes": [], "funcionarios": [],
    "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "centros_custo": [{"id": 90, "fazenda_id": None, "nome": "ADUBOS", "frente": None,
                       "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | INSUMOS"}],
    "entidades": [{"id": 5, "nome": "FORNECEDOR A", "documento": "", "papel": "fornecedor", "ativo": True},
                  {"id": 6, "nome": "FORNECEDOR B", "documento": "", "papel": "fornecedor", "ativo": True}],
    "contas_bancarias": [{"id": 2, "nome": "CONTA PRINCIPAL", "ativo": True}],
    "titulos": [
        tit(1, 5, "Adubo", 1000.00, D1),
        tit(2, 6, "Peca trator", 250.50, D2),
        tit(3, 5, "Vencida", 300.00, ONTEM),
        tit(4, 5, "Ja paga", 800.00, ONTEM, valor_baixado=800.00, situacao="pago"),
        tit(5, 6, "Cancelada", 999.00, D1, cancelado=True),
        tit(6, 6, "Sem rateio", 50.00, D1),
        tit(7, 5, "Parcial", 500.00, D2, valor_baixado=200.00, situacao="parcial"),
    ],
    "titulo_rateios": [
        {"id": i, "titulo_id": t, "fazenda_id": 1, "atividade": "cana", "centro_custo_id": 90,
         "competencia": "2026-10", "valor": v}
        for i, (t, v) in enumerate([(1, 1000.0), (2, 250.5), (3, 300.0), (4, 800.0), (5, 999.0), (7, 500.0)], 1)],
    "titulo_baixas": [{"id": 1, "titulo_id": 4, "data": ONTEM, "valor": 800.00, "conta_bancaria_id": None},
                      {"id": 2, "titulo_id": 7, "data": ONTEM, "valor": 200.00, "conta_bancaria_id": None}],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

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
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1000)
    ev = page.evaluate
    print("\n  CONTA REPETIDA E BAIXA EM LOTE")

    print("\n  -- conta repetida --")
    def salvar(entidade, valor, venc, desc="Outra descricao", extra=""):
        ev("""(a) => { state.page='contas'; state.erroTitulo=''; window.__ESCRITAS__=[];
          editDraft={tipo:'pagar', entidadeNome:a.ent, descricao:a.desc, valor:String(a.valor), vencimento:a.venc,
            parcelas:1, intervaloTipo:'mensal', intervaloDias:'', previsao:false,
            rateios:[{fazendaId:'', atividade:'cana', centroCustoId:90, competencia:'2026-10', valor:a.valor}]};
          """ + extra + """
          state.modal={type:'titulo'}; render(); }""", {"ent": entidade, "valor": valor, "venc": venc, "desc": desc})
        page.wait_for_timeout(200)
        page.click("[data-save='titulo']"); page.wait_for_timeout(500)
        gravou = ev("() => (window.__ESCRITAS__||[]).filter(e=>e.tabela==='titulos').length")
        erro = ev("() => state.erroTitulo")
        return gravou, erro

    g, e = salvar("fornecedor a", 1000.00, D1)
    conf(g == 0 and "já está lançada" in e, "mesmo fornecedor, valor e vencimento (descricao e caixa diferentes): bloqueia", f"{g} {e}")
    g, e = salvar("FORNECEDOR A", 800.00, ONTEM)
    conf(g == 0 and "já está lançada" in e, "repetir conta ja PAGA tambem bloqueia", f"{g} {e}")
    g, e = salvar("FORNECEDOR B", 999.00, D1)
    conf(g == 1 and not e, "igual a uma conta CANCELADA: deixa lancar", f"{g} {e}")
    g, e = salvar("FORNECEDOR A", 1000.01, D1)
    conf(g == 1, "um centavo diferente: deixa lancar", f"{g} {e}")
    g, e = salvar("FORNECEDOR A", 1000.00, D2)
    conf(g == 1, "outro vencimento: deixa lancar", f"{g} {e}")
    g, e = salvar("FORNECEDOR NOVO", 1000.00, D1)
    conf(g == 1, "fornecedor novo: deixa lancar", f"{g} {e}")
    # editar a propria conta sem mudar nada nao acusa ela mesma
    g, e = salvar("FORNECEDOR A", 1000.00, D1, extra="editDraft._editId=1;")
    conf(not e, "editar a propria conta nao acusa repeticao com ela mesma", e)
    # parcelas: a 2a parcela bate com uma conta existente
    ev("""(a) => { state.page='contas'; state.erroTitulo=''; window.__ESCRITAS__=[];
      editDraft={tipo:'pagar', entidadeNome:'FORNECEDOR B', descricao:'Parcelado', valor:'501', vencimento:a.d2,
        parcelas:2, intervaloTipo:'mensal', intervaloDias:'', previsao:false, vencimentos:[a.d2, '2027-12-01'], valoresParcela:[250.5, 250.5],
        rateios:[{fazendaId:'', atividade:'cana', centroCustoId:90, competencia:'2026-10', valor:501}]};
      state.modal={type:'titulo'}; render(); }""", {"d1": D1, "d2": D2})
    page.wait_for_timeout(200)
    page.click("[data-save='titulo']"); page.wait_for_timeout(500)
    conf(ev("() => (window.__ESCRITAS__||[]).filter(e=>e.tabela==='titulos').length") == 0
         and "já está lançada" in ev("() => state.erroTitulo"),
         "parcelado: se a 1a parcela repete conta existente, nenhuma parcela e gravada")

    print("\n  -- selecao --")
    ev("() => { state.modal=null; state.page='contas'; state.abaContas='pagar'; state.filtroContas='todos'; state.contasSelecionadas=[]; render(); }")
    page.wait_for_timeout(300)
    ids = ev("() => [...document.querySelectorAll('[data-selecionar-titulo]')].map(e=>Number(e.dataset.selecionarTitulo)).sort((a,b)=>a-b)")
    base = [i for i in ids if i <= 7]
    conf(base == [1, 2, 3, 7], "caixa so em conta baixavel (nao em paga, cancelada ou sem rateio)", str(ids))
    page.check("[data-selecionar-titulo='1']"); page.wait_for_timeout(150)
    page.check("[data-selecionar-titulo='7']"); page.wait_for_timeout(150)
    barra = page.inner_text("body")
    conf("2 contas selecionadas · R$ 1.300,00" in barra, "barra mostra quantas e o saldo somado (1000 + 300 do parcial)")
    page.check("[data-selecionar-todos]"); page.wait_for_timeout(150)
    conf(len(ev("() => state.contasSelecionadas")) == len(ids), "marcar todas pega todas as baixaveis da lista")
    page.uncheck("[data-selecionar-todos]"); page.wait_for_timeout(150)
    conf(ev("() => state.contasSelecionadas.length") == 0, "desmarcar todas limpa")

    print("\n  -- baixa em lote --")
    for i in (1, 2, 7): page.check(f"[data-selecionar-titulo='{i}']"); page.wait_for_timeout(100)
    page.click("[data-baixar-selecionados]"); page.wait_for_timeout(250)
    conf("Baixar 3 contas" in page.inner_text(".modal"), "abre o modal com as 3 contas")
    ev("() => { window.__ESCRITAS__=[]; }")
    page.click("[data-save='baixaLote']"); page.wait_for_timeout(600)
    bx = ev("() => window.__DB__.titulo_baixas.filter(b=>b.id>2).map(b=>({t:b.titulo_id, d:b.data, v:Number(b.valor)}))")
    esperado = sorted([{"t": 1, "d": D1, "v": 1000.0}, {"t": 2, "d": D2, "v": 250.5}, {"t": 7, "d": D2, "v": 300.0}], key=lambda x: x["t"])
    conf(sorted(bx, key=lambda x: x["t"]) == esperado, "uma baixa por conta: saldo inteiro, data = vencimento de cada uma", str(bx))
    ins = ev("() => (window.__ESCRITAS__||[]).filter(e=>e.tabela==='titulo_baixas').length")
    conf(ins == 1, "tudo num insert so (o banco aceita todas ou nenhuma)", str(ins))
    conf(ev("() => state.contasSelecionadas.length") == 0 and ev("() => state.modal") is None, "depois limpa a selecao e fecha")

    # uma data para todas
    ev("() => { state.filtroContas='todos'; state.contasSelecionadas=[3]; render(); }")
    page.wait_for_timeout(200)
    page.click("[data-baixar-selecionados]"); page.wait_for_timeout(250)
    page.check("input[name='f-bxl-modo'][value='unica']"); page.wait_for_timeout(200)
    page.fill("#f-bxl-data", "2026-10-15")
    page.select_option("#f-bxl-conta", "2")
    page.click("[data-save='baixaLote']"); page.wait_for_timeout(600)
    b3 = ev("() => window.__DB__.titulo_baixas.find(b=>b.titulo_id===3)")
    conf(b3 and b3["data"] == "2026-10-15" and b3["conta_bancaria_id"] == 2,
         "uma data para todas e conta bancaria escolhida", str(b3))

    reais = [e for e in erros if "ServiceWorker" not in e]
    conf(not reais, "sem erro de JavaScript", " | ".join(reais[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhou")
raise SystemExit(1 if falhas else 0)
