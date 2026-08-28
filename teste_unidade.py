"""
Quantidade e unidade por atividade, e centro de custo do lado certo.

Dois pedidos do Eduardo:

  "cada venda deve ser especifica: se for cana deve ser em toneladas, se
   for cereais deve ser sacas e gado @"
  "la na venda estao os custos de compra"

O segundo era o formulario de receita oferecendo centro de custo de SAIDA -
dava para lancar uma venda de boi contra AQUISICAO DE MAQUINAS.

Unidades conferidas: saca de 60 kg (soja, milho, cafe, trigo, feijao,
sorgo), arroz 50 kg, arroba de 15 kg de carcaca bovina.
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
        {"id": 92, "nome": "VENDAS", "frente": None, "ativo": True,
         "tipo": "entrada", "subcategoria": "ATIVIDADES OPERACIONAIS"},
        {"id": 95, "nome": "AQUISICAO DE MAQUINAS", "frente": None, "ativo": True,
         "tipo": "saida", "subcategoria": "INVESTIMENTOS | MAQUINAS"},
        {"id": 90, "nome": "ADUBOS", "frente": None, "ativo": True,
         "tipo": "saida", "subcategoria": "OPERACIONAL | INSUMOS"},
        {"id": 99, "nome": "SEM CLASSIFICAR", "frente": None, "ativo": True,
         "tipo": None, "subcategoria": None},
    ],
    "lancamentos_financeiros": [],
    "lotes": [{"id": 1, "nome": "Curral 1", "numero_animais": 100,
               "destino": "confinamento", "data_fim": None}],
    "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [],
    "culturas": [
        {"id": 7, "nome": "Soja",   "frente": "graos", "ativo": True},
        {"id": 8, "nome": "Milho",  "frente": "graos", "ativo": True},
        {"id": 9, "nome": "Sorgo",  "frente": "graos", "ativo": False},
        {"id": 1, "nome": "Cana",   "frente": "cana",  "ativo": True},
    ],
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

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1000)

    print("\n  UNIDADE POR ATIVIDADE E CENTRO DO LADO CERTO")

    # ---- a unidade certa para cada atividade ----
    print("\n  -- unidade padrao --")
    for ativ, esperado in [("cana", "t"), ("graos", "sc"), ("pecuaria", "@")]:
        got = page.evaluate("(a) => unidadePadrao(a)", ativ)
        conf(got == esperado, f"{ativ} sugere '{esperado}'", f"deu '{got}'")
    conf(page.evaluate("() => unidadesPara('graos')") == ["sc", "sc50", "t", "kg"],
         "graos oferece saca de 60, saca de 50 (arroz), tonelada e kg")
    conf(page.evaluate("() => unidadesPara('cana').includes('sc')") is False,
         "cana nao oferece saca")
    conf("15 kg" in page.evaluate("() => UNIDADES['@'].rotulo"),
         "a arroba diz que sao 15 kg de carcaca")
    conf("60 kg" in page.evaluate("() => UNIDADES['sc'].rotulo"),
         "a saca diz que sao 60 kg")

    # ---- preco por unidade ----
    print("\n  -- preco por unidade --")
    conf(page.evaluate("() => precoUnitario(180000, 1500)") == 120.0,
         "R$ 180.000 por 1.500 t = R$ 120,00/t")
    conf(page.evaluate("() => precoUnitario(1000, 0)") is None,
         "sem quantidade nao inventa preco")

    # ---- na venda, a quantidade sai da forma de venda ----
    print("\n  -- quantidade da venda de animais --")
    casos = [
        ({"tipoVenda": "arroba", "qtdAnimais": 30, "pesoMedioKg": "270"}, 540.0, "@",
         "abate: 30 x 270 kg de carcaca = 540 @"),
        ({"tipoVenda": "cabeca", "qtdAnimais": 25}, 25.0, "cab",
         "por cabeca: 25 cabecas"),
        ({"tipoVenda": "kg", "qtdAnimais": 40, "pesoMedioKg": "420"}, 16800.0, "kg",
         "por kg: 40 x 420 = 16.800 kg"),
    ]
    for entrada, qtd_esp, un_esp, rotulo in casos:
        r = page.evaluate("(d) => quantidadeDaVenda(d)", entrada)
        conf(abs(r["quantidade"] - qtd_esp) < 0.01 and r["unidade"] == un_esp,
             rotulo, str(r))

    # ---- centro de custo do lado certo ----
    print("\n  -- centro de custo (o defeito dos custos de compra) --")
    def centros(tipo, atividade="pecuaria"):
        page.evaluate("""(a) => { state.page='financeiro'; state.erroLancamento='';
          editDraft={tipo:a.tipo, atividade:a.ativ, fazendaId:'', centroCustoId:'',
            descricao:'X', valor:'100', data:'2026-09-10', areas:[], ehVenda:false};
          state.modal={type:'lancamento'}; render(); }""",
          {"tipo": tipo, "ativ": atividade})
        page.wait_for_timeout(200)
        return page.evaluate(
            "() => [...document.querySelectorAll('#f-centrocustolanc option')]"
            ".map(o => o.textContent.trim()).filter(x => x && !x.startsWith('—'))")

    rec = centros("receita")
    conf("VENDAS" in rec, "receita oferece centro de entrada", str(rec))
    conf("AQUISICAO DE MAQUINAS" not in rec,
         "receita NAO oferece mais centro de compra", str(rec))
    conf("ADUBOS" not in rec, "nem centro de despesa", str(rec))

    desp = centros("despesa")
    conf("ADUBOS" in desp, "despesa oferece centro de saida", str(desp))
    conf("VENDAS" not in desp, "despesa NAO oferece centro de entrada", str(desp))

    inv = centros("investimento")
    conf("AQUISICAO DE MAQUINAS" in inv, "investimento oferece centro de saida", str(inv))

    conf("SEM CLASSIFICAR" in rec and "SEM CLASSIFICAR" in desp,
         "centro sem classificacao aparece nos dois")

    # ---- o bloco de quantidade na tela, e o que e salvo ----
    print("\n  -- lancar receita de cana com tonelada --")
    # A quantidade saiu do lancamento comum: quem lanca tonelada de cana e
    # saca de cereal e o app da frente, na colheita. No Matriz sobra o
    # valor - e a quantidade da venda de animais, que sai sozinha.
    page.evaluate("""() => { state.page='financeiro'; state.erroLancamento='';
      editDraft={tipo:'receita', atividade:'cana', fazendaId:1, centroCustoId:92,
        descricao:'Venda de cana', valor:'180000', data:'2026-09-10',
        areas:[], ehVenda:false};
      state.modal={type:'lancamento'}; render(); }""")
    page.wait_for_timeout(250)
    conf(page.locator("#f-qtdlanc").count() == 0,
         "receita de cana nao pede quantidade (isso e do AE Cana)")
    conf(page.locator("#f-culturalanc").count() == 0,
         "e nem cultura, porque cana e uma so")

    # Sorgo esta inativo no cadastro: nao pode aparecer para lancamento novo,
    # senao a lista cresce com o que a fazenda parou de plantar.
    page.evaluate("""() => { editDraft={tipo:'despesa', atividade:'graos', fazendaId:1,
        centroCustoId:90, descricao:'X', valor:'1', data:'2026-09-10',
        culturaId:'', areas:[], ehVenda:false};
      state.modal={type:'lancamento'}; render(); }""")
    page.wait_for_timeout(200)
    op_sorgo = page.evaluate(
        "() => [...document.querySelectorAll('#f-culturalanc option')].map(o => o.textContent.trim())")
    conf("Sorgo" not in op_sorgo, "cultura inativa nao aparece", str(op_sorgo))

    # ---- a venda de animais grava @ ----
    print("\n  -- venda de animais grava arrobas --")
    page.evaluate("""() => { window.__ESCRITAS__=[];
      editDraft={tipo:'receita', atividade:'pecuaria', fazendaId:'', centroCustoId:92,
        descricao:'Venda de boi', valor:'', data:'2026-09-10',
        ehVenda:true, tipoVenda:'arroba', loteId:1, qtdAnimais:30,
        pesoMedioKg:'270', valorArroba:'320', areas:[]};
      state.modal={type:'lancamento'}; render(); }""")
    page.wait_for_timeout(250)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(700)
    lancs2 = [e["v"] for e in page.evaluate("() => window.__ESCRITAS__")
              if e["tabela"] == "lancamentos_financeiros" and e["op"] == "insert"]
    if lancs2:
        conf(abs(float(lancs2[0].get("quantidade")) - 540) < 0.01,
             "a venda grava 540 @ sem ninguem digitar", str(lancs2[0].get("quantidade")))
        conf(lancs2[0].get("unidade") == "@", "com unidade @", str(lancs2[0].get("unidade")))
    else:
        conf(False, "a venda grava 540 @", "nao salvou")

    # ---- editar lancamento sem os campos preserva o que existia ----
    # ---- qual cereal ----
    print("\n  -- qual cereal (cereais) --")
    page.evaluate("""() => { window.__ESCRITAS__=[]; state.erroLancamento='';
      editDraft={tipo:'despesa', atividade:'graos', fazendaId:1, centroCustoId:90,
        descricao:'Adubo de plantio', valor:'50000', data:'2026-09-10',
        culturaId:'', areas:[], ehVenda:false};
      state.modal={type:'lancamento'}; render(); }""")
    page.wait_for_timeout(250)
    opcoes = page.evaluate(
        "() => [...document.querySelectorAll('#f-culturalanc option')]"
        ".map(o => o.textContent.trim())")
    conf("Soja" in opcoes and "Milho" in opcoes,
         "despesa de cereais oferece as culturas de graos", str(opcoes))
    conf("Cana" not in opcoes, "e nao oferece a cana", str(opcoes))
    conf(any("Todas" in o for o in opcoes),
         "com opcao de nao especificar (custo que serve a todas)", str(opcoes))

    page.select_option("#f-culturalanc", label="Soja")
    page.wait_for_timeout(120)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(600)
    gravados = [e["v"] for e in page.evaluate("() => window.__ESCRITAS__")
                if e["tabela"] == "lancamentos_financeiros" and e["op"] == "insert"]
    conf(len(gravados) == 1 and gravados[0].get("cultura_id") == 7,
         "grava qual cereal no lancamento",
         str(gravados[0] if gravados else "nao salvou"))

    # centro de custo NAO se multiplica por cultura
    rec_graos = centros("despesa", "graos")
    conf(not any("SOJA" in c.upper() or "MILHO" in c.upper() for c in rec_graos),
         "o plano de contas nao ganhou uma conta por cultura", str(rec_graos))

    print("\n  -- preservacao ao editar --")
    # O que importa e o que o Supabase ENVIA, e ele serializa com
    # JSON.stringify - que descarta chave de valor undefined. Ler as chaves
    # do objeto em JS nao serve: {a: undefined} tem a chave 'a'.
    enviado = page.evaluate("""() => JSON.parse(JSON.stringify(
      lancamentoToRow({tipo:'despesa', atividade:'cana', centroCustoId:90,
                       descricao:'X', valor:100, data:'2026-09-01', areas:[]})))""")
    conf("quantidade" not in enviado and "unidade" not in enviado,
         "lancamento sem esses campos nao envia a chave (o banco preserva)",
         str(sorted(enviado.keys())))
    enviado2 = page.evaluate("""() => JSON.parse(JSON.stringify(
      lancamentoToRow({tipo:'receita', atividade:'cana', centroCustoId:92,
                       descricao:'X', valor:100, data:'2026-09-01', areas:[],
                       quantidade:'1500', unidade:'t'})))""")
    conf(enviado2.get("quantidade") == 1500 and enviado2.get("unidade") == "t",
         "mas quando a tela mostra os campos, eles vao", str(enviado2))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
