"""
Custo dos animais por lote (resultado economico da Pecuaria, 07/11/2026). A compra de animais ganhou lote e no de cabecas (colunas
lote_id e quantidade, que ja existiam), e Resultados > Operacional > Pecuaria mostra, por lote: comprados, custo da compra, R$ por
cabeca, vendidos, receita das vendas, custo dos vendidos e a margem sobre o animal. Contas feitas a mao:
  Curral 2: 50 cab por R$ 100.000 + 30 cab por R$ 60.000 = 80 cab, R$ 160.000, R$ 2.000 por cabeca; vendidas 60 + 30 = 90 cab; receita
    R$ 120.000 + R$ 90.000 = R$ 210.000; custo dos vendidos = R$ 2.000 x 80 (so as compradas tem custo) = R$ 160.000; margem R$ 50.000;
    10 animais vendidos sem compra (cria da fazenda) -> aviso.
  Lote em andamento: 10 cab por R$ 25.000 = R$ 2.500 por cabeca, nada vendido, em estoque 10 cab a custo R$ 25.000.
  Matrizes (R$ 30.000, 10 cab) ficam a parte (ativo: so vira resultado no descarte). Compra sem lote (R$ 80.000) e compra com lote mas sem
  cabecas (R$ 5.000) vao para a lista "sem lote" (R$ 85.000), com Editar.
Prova tambem o formulario: lote e cabecas aparecem na compra de animais (e some ao trocar para outro centro), vao juntos, cabeca e
numero inteiro, a unidade grava 'cab', e a compra antiga pode ser editada para ligar a um lote.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}


def centro(i, nome, tipo):
    return {"id": i, "fazenda_id": None, "nome": nome, "frente": None, "ativo": True, "tipo": tipo, "subcategoria": nome}


def lanc(i, tipo, ativ, centro_id, valor, data, desc, **extra):
    return {"id": i, "tipo": tipo, "atividade": ativ, "fazenda_id": None, "centro_custo_id": centro_id, "descricao": desc,
            "valor": valor, "data": data, "mes": data[:7], "fornecedor": "Vendedor X", "areas": [], **extra}


def lote(i, nome):
    return {"id": i, "nome": nome, "destino": "confinamento", "sexo": "macho", "numero_animais": 10, "data_fim": None}


CENTROS = [centro(1, "VENDAS DE GADO", "entrada"), centro(2, "ENERGIA", "saida"),
           centro(3, "COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE", "saida"), centro(4, "COMPRA DE MATRIZES PARA REPRODUÇÃO", "saida"),
           centro(7, "MAQUINAS E IMPLEMENTOS", "saida")]
L = [
    lanc(1, "investimento", "pecuaria", 3, 100000, "2026-03-10", "Compra de bezerros A", lote_id=31, quantidade=50, unidade="cab"),
    lanc(2, "investimento", "pecuaria", 3, 60000, "2026-04-10", "Compra de bezerros B", lote_id=31, quantidade=30, unidade="cab"),
    lanc(3, "investimento", "pecuaria", 3, 25000, "2026-05-10", "Compra do lote novo", lote_id=5, quantidade=10, unidade="cab"),
    lanc(4, "investimento", "pecuaria", 3, 80000, "2024-02-01", "Compra antiga sem lote"),
    lanc(5, "investimento", "pecuaria", 3, 5000, "2026-06-01", "Compra com lote e sem cabecas", lote_id=31),
    lanc(6, "investimento", "pecuaria", 4, 30000, "2026-02-01", "Compra de matrizes", lote_id=6, quantidade=10, unidade="cab"),
    lanc(7, "receita", "pecuaria", 1, 120000, "2026-07-15", "Venda do Curral 2 (1)", lote_id=31),
    lanc(8, "receita", "pecuaria", 1, 90000, "2026-08-20", "Venda do Curral 2 (2)", lote_id=31),
    lanc(9, "receita", "pecuaria", 1, 777, "2026-08-21", "Receita sem lote"),
    lanc(10, "investimento", "pecuaria", 7, 1111, "2026-03-01", "Equipamento"),
]
ABATES = [{"id": 1, "data": "2026-07-15", "quantidade": 60, "tipo_venda": "arroba", "peso_medio_kg": 500, "categoria": "venda_viva", "sexo": "macho", "lote_id": 31},
          {"id": 2, "data": "2026-08-20", "quantidade": 30, "tipo_venda": "arroba", "peso_medio_kg": 500, "categoria": "venda_viva", "sexo": "macho", "lote_id": 31}]
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [],
    "lotes": [lote(31, "Curral 2"), lote(5, "Lote em andamento"), lote(6, "Vacas 07/08")], "abates": ABATES,
    "centros_custo": CENTROS, "lancamentos_financeiros": L, "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "profiles": [ADMIN],
}
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(browser, db, w=1280):
    page = browser.new_page(viewport={"width": w, "height": 900})
    page.erros = []
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lancamentos && state.lancamentos.length > 0", timeout=30000)
    page.wait_for_function("() => state.resultados.pecuaria && !state.resultados.pecuaria.loading && state.resultados.pecuaria.mensal && state.vendasPec.length > 0", timeout=30000)
    page.wait_for_timeout(400)
    return page


def linhas(page):
    return page.evaluate("""() => Object.fromEntries([...document.querySelectorAll('[data-lote-custo]')].map(tr =>
        [tr.children[0].innerText.trim(), [...tr.children].slice(1).map(td => td.innerText.replace(/\\s+/g, ' ').trim())]))""")


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = abre(browser, DB)
    ir = lambda periodo: (page.evaluate("(p) => { state.periodo = p; state.page = 'resultados'; state.subAbaResultados = 'operacional'; render(); }", periodo), page.wait_for_timeout(250))
    ir({"tipo": "ano", "ano": 2026, "mes": "2026-06", "safra": 2026})

    print("== custo dos animais por lote")
    L_ = linhas(page)
    c2 = L_.get("Curral 2")
    conf(c2 and c2[1] == "80" and c2[3] == "R$ 160.000,00" and c2[2] == "R$ 2.000,00", "Curral 2: 80 cabecas compradas, R$ 160.000 (a compra sem cabecas nao entra), R$ 2.000 por cabeca", str(c2))
    conf(c2 and c2[4] == "90" and c2[5] == "R$ 210.000,00" and c2[6] == "R$ 160.000,00", "Curral 2: 90 vendidas, receita R$ 210.000, custo dos vendidos R$ 160.000 (so 80 tem compra)", str(c2))
    conf(c2 and c2[0] == "R$ 50.000,00" and c2[7] == "—", "Curral 2: margem sobre o animal R$ 50.000, nada em estoque", str(c2))
    novo = L_.get("Lote em andamento")
    conf(novo and novo[1] == "10" and novo[2] == "R$ 2.500,00" and novo[4] == "0" and novo[5] == "—" and novo[0] == "—", "Lote em andamento: 10 cab a R$ 2.500, nada vendido, sem receita nem margem", str(novo))
    conf(novo and novo[7] == "10 cab · R$ 25.000,00", "Lote em andamento: 10 cabecas em estoque a custo de R$ 25.000", str(novo))
    conf("Vacas 07/08" not in L_, "matriz nao entra na tabela por lote")
    total = page.evaluate("() => [...document.querySelector('[data-lote-custo-total]').children].map(td => td.innerText.replace(/\\s+/g, ' ').trim())")
    conf(total[4] == "R$ 185.000,00" and total[5] == "90" and total[6] == "R$ 210.000,00" and total[7] == "R$ 160.000,00" and total[1] == "R$ 50.000,00" and total[8] == "R$ 25.000,00",
         "total: custo R$ 185.000, 90 vendidas, receita R$ 210.000, custo dos vendidos R$ 160.000, margem R$ 50.000, estoque R$ 25.000", str(total))
    bloco = page.inner_text("[data-bloco-custo-animais-lote]")
    conf("Curral 2: 10 animal(is) vendido(s) sem compra ligada" in bloco, "avisa os 10 animais vendidos sem compra (cria da fazenda)")
    conf("10 cabeça(s), R$ 30.000,00" in bloco and "so vira resultado no descarte" in bloco.replace("só", "so"), "matrizes ligadas ficam a parte, como ativo")
    conf("ANTES" in bloco.upper() and "ração, custo fixo e juros" in bloco, "explica que a margem e antes de racao, custo fixo e juros")
    conf("2 compra(s) de animais sem lote ou sem nº de cabeças" in bloco and "R$ 85.000,00" in bloco, "lista as compras sem lote (R$ 80.000 + R$ 5.000)", bloco[-420:])
    conf(page.locator("[data-compras-sem-lote] [data-edit-lancamento]").count() == 2, "com um Editar em cada uma")
    ir({"tipo": "mes", "mes": "2026-01", "ano": 2026, "safra": 2025})
    conf(linhas(page).get("Curral 2") == c2, "o bloco nao segue o filtro de periodo (outro mes: mesmos numeros)")

    print("== o formulario da compra de animais")
    def novo_invest():
        page.evaluate("() => { state.page = 'financeiro'; state.abaFinanceiro = 'investimento'; state.filtroAtividade = ''; state.erroLancamento = ''; state.modal = null; editDraft = null; render(); }")
        page.wait_for_timeout(250)
        page.locator("[data-novo-lancamento]").click()
        page.wait_for_timeout(250)
    escritas = lambda: page.evaluate("() => window.__ESCRITAS__.filter(e => e.tabela === 'lancamentos_financeiros').map(e => ({...e, v: JSON.parse(JSON.stringify(e.v))}))")
    limpa = lambda: page.evaluate("() => { window.__ESCRITAS__.length = 0; }")
    def basico(centro_id, desc="Compra nova", valor="3000"):
        page.select_option("#f-atividadelanc", "pecuaria")
        page.select_option("#f-centrocustolanc", str(centro_id))
        page.fill("#f-descricaolanc", desc)
        page.click("#f-valorlanc"); page.fill("#f-valorlanc", ""); page.keyboard.type(valor)
        page.fill("#f-datalanc", "2026-09-01")
    novo_invest()
    page.select_option("#f-atividadelanc", "pecuaria")
    conf(page.locator("[data-campos-compra-animais]").count() == 0, "sem centro de compra de animais os campos nao aparecem")
    page.select_option("#f-centrocustolanc", "3")
    page.wait_for_timeout(250)
    conf(page.locator("[data-campos-compra-animais]").count() == 1 and page.locator("#f-lotelanc").count() == 1 and page.locator("#f-qtdlanc").count() == 1,
         "escolher COMPRA DE ANIMAIS mostra o lote e as cabecas")
    page.select_option("#f-centrocustolanc", "7")
    page.wait_for_timeout(250)
    conf(page.locator("[data-campos-compra-animais]").count() == 0, "trocar para outro centro (maquinas) esconde")
    page.select_option("#f-centrocustolanc", "4")
    page.wait_for_timeout(250)
    conf(page.locator("[data-campos-compra-animais]").count() == 1, "compra de matrizes tambem mostra")

    print("== gravar")
    novo_invest(); basico(3); limpa()
    page.select_option("#f-lotelanc", "5"); page.fill("#f-qtdlanc", "12")
    page.locator('[data-save="lancamento"]').click(); page.wait_for_timeout(500)
    w = escritas()
    conf(len(w) == 1 and w[0]["v"].get("lote_id") in (5, "5") and w[0]["v"].get("quantidade") == 12 and w[0]["v"].get("unidade") == "cab", "lote 5 e 12 cabecas gravam lote_id, quantidade e unidade 'cab'", str(w)[:300])
    novo_invest(); basico(3); limpa()
    page.select_option("#f-lotelanc", "5")
    page.locator('[data-save="lancamento"]').click(); page.wait_for_timeout(400)
    conf(not escritas() and "juntos" in page.evaluate("() => state.erroLancamento"), "lote sem cabecas e barrado e nada e gravado", page.evaluate("() => state.erroLancamento"))
    page.fill("#f-qtdlanc", "2.5")
    page.locator('[data-save="lancamento"]').click(); page.wait_for_timeout(400)
    conf(not escritas() and "inteiro" in page.evaluate("() => state.erroLancamento"), "cabecas com virgula (2,5) e barrado", page.evaluate("() => state.erroLancamento"))
    novo_invest(); basico(3, "Compra sem ligar"); limpa()
    page.locator('[data-save="lancamento"]').click(); page.wait_for_timeout(500)
    w = escritas()
    conf(len(w) == 1 and not w[0]["v"].get("lote_id") and w[0]["v"].get("quantidade") in (None, ""), "sem lote e sem cabecas continua valendo (as compras antigas ficam como estao)", str(w)[:300])

    print("== ligar uma compra antiga")
    page.evaluate("() => { state.page = 'financeiro'; state.abaFinanceiro = 'investimento'; state.modal = null; editDraft = null; render(); }")
    page.wait_for_timeout(250)
    page.locator('[data-edit-lancamento="4"]').click(); page.wait_for_timeout(250)
    conf(page.locator("#f-lotelanc").count() == 1, "editar a compra antiga mostra o lote e as cabecas")
    limpa()
    page.select_option("#f-lotelanc", "5"); page.fill("#f-qtdlanc", "40")
    page.locator('[data-save="lancamento"]').click(); page.wait_for_timeout(500)
    w = escritas()
    conf(len(w) == 1 and w[0]["op"] == "update" and w[0]["v"].get("quantidade") == 40 and w[0]["v"].get("mes") == "2024-02", "gravou o lote e as 40 cabecas sem mexer no mes (2024-02)", str(w)[:300])
    ir({"tipo": "ano", "ano": 2026, "mes": "2026-06", "safra": 2026})
    novo = linhas(page).get("Lote em andamento")
    conf(novo and novo[1] == "62" and novo[3] == "R$ 108.000,00", "o bloco passa a contar: lote em andamento 10 + 12 + 40 = 62 cab, R$ 25.000 + 3.000 + 80.000", str(novo))
    page.evaluate("() => { state.page = 'financeiro'; state.abaFinanceiro = 'receita'; state.modal = null; editDraft = null; render(); }")
    page.wait_for_timeout(250)
    page.locator('[data-edit-lancamento="7"]').click(); page.wait_for_timeout(250)
    conf(page.locator("[data-campos-compra-animais]").count() == 0, "receita nao mostra os campos da compra")
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    page.close()

    print("== sem compras ligadas")
    db2 = dict(DB, lancamentos_financeiros=[x for x in L if x["id"] in (7, 8, 9, 10)])
    page = abre(browser, db2)
    ir({"tipo": "ano", "ano": 2026, "mes": "2026-06", "safra": 2026})
    conf(page.locator("[data-bloco-custo-animais-lote]").count() == 0, "sem nenhuma compra de animais o bloco nao aparece")
    page.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
