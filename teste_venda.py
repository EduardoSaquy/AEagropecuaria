"""
Venda de animais como lancamento de receita no AE Matriz.

Portada do AE Pecuaria, onde era tela propria. O que precisa continuar
verdadeiro:

  o valor sai da forma de venda escolhida (arroba / cabeca / kg)
  o lote perde os animais vendidos
  o lote encerra quando a venda zera o rebanho
  nao da para vender mais animais do que o lote tem
  lote encerrado ou zerado nao aparece na lista
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

DB = {
    "fazendas": [{"id": 1, "nome": "Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [],
    "centros_custo": [
        {"id": 92, "fazenda_id": None, "nome": "VENDAS", "frente": None, "ativo": True,
         "tipo": "entrada", "subcategoria": "ATIVIDADES OPERACIONAIS"},
        {"id": 90, "fazenda_id": None, "nome": "ADUBOS", "frente": None, "ativo": True,
         "tipo": "saida", "subcategoria": "OPERACIONAL | X"},
    ],
    "lancamentos_financeiros": [],
    "lotes": [
        {"id": 1, "nome": "Curral 1", "numero_animais": 100, "destino": "confinamento", "data_fim": None},
        {"id": 2, "nome": "Curral 2 ENCERRADO", "numero_animais": 40, "destino": "confinamento", "data_fim": "2026-06-30"},
        {"id": 3, "nome": "Curral 3 VAZIO", "numero_animais": 0, "destino": "confinamento", "data_fim": None},
    ],
    "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [],
    "titulo_baixas": [], "abates": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def preencher(page, sel, valor):
    el = page.locator(sel)
    tipo = el.get_attribute("type") or "text"
    if tipo in ("month", "date"):
        el.fill(valor)
    else:
        el.click(); el.fill(""); el.type(valor)
    page.keyboard.press("Tab"); page.wait_for_timeout(90)

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1000)

    print("\n  VENDA DE ANIMAIS NO AE MATRIZ")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:2]))

    # ---- a matematica das tres formas ----
    print("\n  -- as tres formas de vender --")
    casos = [
        # abate: 30 animais, 270 kg de carcaca, R$ 320/@  ->  30*270/15 = 540 @
        ({"tipoVenda": "arroba", "qtdAnimais": 30, "pesoMedioKg": "270", "valorArroba": "320"},
         540 * 320, "abate: 30 x 270 kg carcaca a R$ 320/@"),
        # cabeca: 25 animais a R$ 2.800
        ({"tipoVenda": "cabeca", "qtdAnimais": 25, "valorPorAnimal": "2800"},
         25 * 2800, "por cabeca: 25 x R$ 2.800"),
        # kg vivo: 40 animais, 420 kg, R$ 11,50/kg
        ({"tipoVenda": "kg", "qtdAnimais": 40, "pesoMedioKg": "420", "valorKg": "11,50"},
         40 * 420 * 11.5, "por kg vivo: 40 x 420 kg a R$ 11,50"),
    ]
    for entrada, esperado, rotulo in casos:
        got = page.evaluate("(d) => valorDaVenda(d)", entrada)
        conf(abs(got - esperado) < 0.01, f"{rotulo} = R$ {esperado:,.2f}", f"deu {got}")

    conf(abs(page.evaluate("() => arrobasDaVenda({qtdAnimais:30, pesoMedioKg:'270'})") - 540) < 0.01,
         "30 animais de 270 kg de carcaca dao 540 @")
    conf(page.evaluate("() => numDecimal('11,50')") == 11.5,
         "aceita virgula (teclado do celular manda 11,50)")

    # ---- so lote ativo com animais ----
    print("\n  -- quais lotes aparecem --")
    nomes = page.evaluate("() => lotesVendaveis().map(l => l.nome)")
    conf(nomes == ["Curral 1"], "so o lote ativo com animais", str(nomes))
    nomes2 = page.evaluate("() => lotesVendaveis(2).map(l => l.nome)")
    conf("Curral 2 ENCERRADO" in nomes2,
         "ao editar, o lote ja gravado continua na lista", str(nomes2))

    # ---- o fluxo na tela ----
    print("\n  -- lancar a venda pela tela --")
    page.evaluate("""() => {
      window.__ESCRITAS__ = [];
      state.page='financeiro'; state.abaFinanceiro='receita'; state.erroLancamento='';
      editDraft = {tipo:'receita', atividade:'pecuaria', fazendaId:'', centroCustoId:92,
                   descricao:'Venda de boi gordo', valor:'', data:'2026-09-10',
                   ehVenda:true, tipoVenda:'arroba', loteId:1, qtdAnimais:30,
                   arrobasTotais:'540', valorArroba:'320', areas:[]};
      state.modal = {type:'lancamento'}; render();
    }""")
    page.wait_for_timeout(300)
    conf(page.locator("#f-lotevenda").count() == 1, "o bloco de venda aparece")
    travado = page.evaluate("() => document.getElementById('f-valorlanc')?.readOnly")
    conf(travado is True, "o campo Valor fica travado", str(travado))
    valor_tela = page.evaluate("() => document.getElementById('f-valorlanc')?.value")
    conf(abs(float(valor_tela) - 172800) < 0.01,
         "e mostra o valor calculado (540 @ x R$ 320 = R$ 172.800)", str(valor_tela))

    page.click("[data-save='lancamento']")
    page.wait_for_timeout(700)
    esc = page.evaluate("() => window.__ESCRITAS__")
    abates = [e for e in esc if e["tabela"] == "abates" and e["op"] == "insert"]
    lancs  = [e for e in esc if e["tabela"] == "lancamentos_financeiros" and e["op"] == "insert"]
    lotes  = [e for e in esc if e["tabela"] == "lotes" and e["op"] == "update"]
    conf(len(abates) == 1, "grava o abate", str(len(abates)))
    conf(len(lancs) == 1, "grava a receita", str(len(lancs)))
    conf(len(lotes) == 1, "atualiza o lote", str(len(lotes)))
    if abates:
        a = abates[0]["v"]
        conf(a.get("tipo_venda") == "arroba" and float(a.get("peso_medio_kg")) == 270
             and float(a.get("valor_arroba")) == 320,
             "o abate guarda peso e valor da arroba", str(a))
    if lancs:
        l = lancs[0]["v"]
        conf(abs(float(l.get("valor")) - 172800) < 0.01,
             "a receita vai com o valor calculado", str(l.get("valor")))
        conf(l.get("tipo") == "receita" and l.get("atividade") == "pecuaria",
             "e vai como receita da pecuaria", str(l))
        conf(abs(float(l.get("arrobas") or 0) - 540) < 0.01,
             "guarda as arrobas produzidas", str(l.get("arrobas")))
    if lotes:
        conf(lotes[0]["v"].get("numero_animais") == 70,
             "o lote cai de 100 para 70 cabecas", str(lotes[0]["v"]))
        conf("data_fim" not in lotes[0]["v"],
             "e NAO encerra, porque ainda sobraram animais", str(lotes[0]["v"]))

    # ---- venda que zera o lote encerra ele ----
    print("\n  -- venda que zera o lote --")
    # O stub grava de verdade agora (update() persiste em window.__DB__), e
    # a venda anterior deixou o lote 1 com 70 animais. Este cenario testa
    # "zerar o lote" isoladamente, entao repoe o lote pro estado original
    # antes de vender de novo -- sem isso a venda de 100 cabecas bateria
    # sozinha na trava de "nao vender mais do que existe" (so sobrou 70).
    page.evaluate("""async () => {
      window.__DB__.lotes[0].numero_animais = 100;
      delete window.__DB__.lotes[0].data_fim;
      await loadAll();
    }""")
    page.wait_for_timeout(300)
    page.evaluate("""() => {
      window.__ESCRITAS__ = [];
      editDraft = {tipo:'receita', atividade:'pecuaria', fazendaId:'', centroCustoId:92,
                   descricao:'Venda total', valor:'', data:'2026-09-20',
                   ehVenda:true, tipoVenda:'cabeca', loteId:1, qtdAnimais:100,
                   valorPorAnimal:'2800', areas:[]};
      state.modal = {type:'lancamento'}; render();
    }""")
    page.wait_for_timeout(250)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(700)
    lotes2 = [e for e in page.evaluate("() => window.__ESCRITAS__")
              if e["tabela"] == "lotes" and e["op"] == "update"]
    if lotes2:
        conf(lotes2[0]["v"].get("numero_animais") == 0, "zera o lote", str(lotes2[0]["v"]))
        conf(lotes2[0]["v"].get("data_fim") == "2026-09-20",
             "e encerra ele na data da venda", str(lotes2[0]["v"]))
    else:
        conf(False, "zera o lote", "nenhum update de lote")

    # ---- nao vender mais do que existe ----
    print("\n  -- o que barra a venda --")
    # O cenario anterior zerou o lote 1 de verdade. Este aqui quer testar
    # a trava de "vender mais do que existe" contra um lote de 100 -- repoe
    # de novo, mesmo motivo do reset acima.
    page.evaluate("""async () => {
      window.__DB__.lotes[0].numero_animais = 100;
      delete window.__DB__.lotes[0].data_fim;
      await loadAll();
    }""")
    page.wait_for_timeout(300)
    page.evaluate("""() => {
      window.__ESCRITAS__ = []; state.erroLancamento='';
      editDraft = {tipo:'receita', atividade:'pecuaria', fazendaId:'', centroCustoId:92,
                   descricao:'Venda demais', valor:'', data:'2026-09-20',
                   ehVenda:true, tipoVenda:'cabeca', loteId:1, qtdAnimais:150,
                   valorPorAnimal:'2800', areas:[]};
      state.modal = {type:'lancamento'}; render();
    }""")
    page.wait_for_timeout(250)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(500)
    conf(len([e for e in page.evaluate("() => window.__ESCRITAS__")
              if e["tabela"] == "abates"]) == 0,
         "vender 150 de um lote de 100 nao salva")
    erro = page.evaluate("() => state.erroLancamento")
    conf("100 cabeças" in erro, "e o erro diz quantas cabecas o lote tem", erro)

    # ---- receita normal da pecuaria continua funcionando ----
    page.evaluate("""() => {
      window.__ESCRITAS__ = []; state.erroLancamento='';
      editDraft = {tipo:'receita', atividade:'pecuaria', fazendaId:'', centroCustoId:92,
                   descricao:'Arrendamento de pasto', valor:'5000', data:'2026-09-20',
                   ehVenda:false, areas:[]};
      state.modal = {type:'lancamento'}; render();
    }""")
    page.wait_for_timeout(250)
    conf(page.locator("#f-lotevenda").count() == 0, "sem marcar venda, o bloco nao aparece")
    conf(page.evaluate("() => document.getElementById('f-valorlanc')?.readOnly") is False,
         "e o campo Valor volta a ser editavel")
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(600)
    esc3 = page.evaluate("() => window.__ESCRITAS__")
    conf(len([e for e in esc3 if e["tabela"] == "abates"]) == 0,
         "receita comum nao grava abate")
    conf(len([e for e in esc3 if e["tabela"] == "lancamentos_financeiros"]) == 1,
         "e grava so o lancamento")

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
