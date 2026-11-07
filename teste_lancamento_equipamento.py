"""
Despesa ligada a um equipamento (07/11/2026): peca, servico ou reparo de uma maquina especifica. O AE Matriz ganhou o campo opcional
"Equipamento" na despesa, gravado em lancamentos_financeiros.equipamento_id (lancamentos_equipamento_01.sql); o AE Combustivel soma essas
despesas ao custo por hora. Prova:
  - despesa mostra a lista de equipamentos ativos (e o inativo que ja estava ligado ao lancamento); receita nao mostra; sem
    equipamentos cadastrados (ou sem acesso a tabela) o campo nao aparece;
  - lancamento NOVO sem equipamento nao manda a coluna (o app funciona antes do SQL); com equipamento manda o numero;
  - editar um lancamento ligado a uma maquina mostra a maquina escolhida; tirar a maquina manda null; mexer so na descricao nao
    perde a maquina; editar um lancamento sem maquina e nao escolher nenhuma nao manda a coluna;
  - dividir entre atividades leva o equipamento para cada parte;
  - o resto do lancamento nao muda (mes preservado em competencia sem data).
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [{"id": 9, "fazenda_id": None, "nome": "Manutencao de maquinas", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "DESPESAS | Manutencao"}],
    "equipamentos": [
        {"id": 1, "nome": "Trator A", "tipo": "trator", "ativo": True, "fazenda_id": 1},
        {"id": 2, "nome": "Colhedora B", "tipo": "colhedora_cana", "ativo": True, "fazenda_id": 1},
        {"id": 3, "nome": "Moto velha", "tipo": "moto", "ativo": False, "fazenda_id": 1},
    ],
    "lancamentos_financeiros": [
        {"id": 1, "tipo": "despesa", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 9, "descricao": "Filtro do trator", "valor": 200, "data": "2026-10-10", "mes": "2026-10", "areas": [], "equipamento_id": 1},
        {"id": 2, "tipo": "despesa", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 9, "descricao": "Conta sem maquina", "valor": 300, "data": None, "mes": "2026-09", "areas": []},
        {"id": 3, "tipo": "despesa", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 9, "descricao": "Reparo da moto", "valor": 80, "data": "2026-10-11", "mes": "2026-10", "areas": [], "equipamento_id": 3},
    ],
    "financiamentos": [], "parcelas_financiamento": [], "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "profiles": [ADMIN],
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


def abre(browser, db):
    page = browser.new_page()
    page.erros = []
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(db)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.lancamentos.length > 0", timeout=30000)
    page.wait_for_timeout(400)
    return page


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = abre(browser, DB)
    # o que iria PELA REDE: a biblioteca real descarta chave com valor undefined (JSON.stringify), o banco falso guarda o objeto cru
    escritas = lambda: page.evaluate("() => window.__ESCRITAS__.filter(e => e.tabela === 'lancamentos_financeiros').map(e => ({...e, v: JSON.parse(JSON.stringify(e.v))}))")
    limpa = lambda: page.evaluate("() => { window.__ESCRITAS__.length = 0; }")

    def novo(aba="despesa"):
        page.evaluate("(a) => { state.page = 'financeiro'; state.abaFinanceiro = a; state.filtroAtividade = ''; state.erroLancamento = ''; state.modal = null; editDraft = null; render(); }", aba)
        page.wait_for_timeout(250)
        page.locator("[data-novo-lancamento]").click()
        page.wait_for_timeout(250)

    def edita(id_):
        page.evaluate("() => { state.page = 'financeiro'; state.abaFinanceiro = 'despesa'; state.filtroAtividade = ''; state.modal = null; editDraft = null; render(); }")
        page.wait_for_timeout(250)
        page.locator(f'[data-edit-lancamento="{id_}"]').click()
        page.wait_for_timeout(250)

    def basico(descricao="Peca de teste", valor="150"):
        page.select_option("#f-atividadelanc", "cana")
        page.select_option("#f-centrocustolanc", "9")
        page.fill("#f-descricaolanc", descricao)
        page.click("#f-valorlanc")
        page.fill("#f-valorlanc", "")
        page.keyboard.type(valor)

    def salva():
        page.locator('[data-save="lancamento"]').click()
        page.wait_for_timeout(500)

    print("== o campo na despesa")
    novo("despesa")
    ops = page.eval_on_selector("#f-equipamentolanc", "e => [...e.options].map(o => o.value)")
    conf(ops == ["", "1", "2"], "despesa mostra os equipamentos ativos (o inativo nao aparece)", str(ops))
    conf("Equipamento (opcional)" in page.inner_text(".modal"), "com o rotulo e a explicacao")
    novo("receita")
    conf(page.locator("#f-equipamentolanc").count() == 0, "receita nao mostra o campo")

    print("== lancamento novo")
    novo("despesa")
    limpa()
    basico("Sem maquina nenhuma")
    salva()
    w = escritas()
    conf(len(w) == 1 and w[0]["op"] == "insert" and "equipamento_id" not in w[0]["v"], "sem equipamento: a coluna nem e enviada (funciona antes do SQL)", str(w))
    novo("despesa")
    limpa()
    basico("Peca do trator")
    page.select_option("#f-equipamentolanc", "1")
    salva()
    w = escritas()
    conf(len(w) == 1 and w[0]["v"].get("equipamento_id") == 1, "com equipamento: envia o numero", str(w))
    gravado = page.evaluate("() => window.__DB__.lancamentos_financeiros.filter(l => l.descricao === 'Peca do trator')")
    conf(len(gravado) == 1 and gravado[0]["equipamento_id"] == 1, "e fica gravado no lancamento")
    conf(page.evaluate("() => state.lancamentos.filter(l => l.descricao === 'Peca do trator').map(l => l.equipamentoId)") == [1], "a tela recarrega o lancamento ja com o equipamento")

    print("== editar")
    edita(1)
    conf(page.eval_on_selector("#f-equipamentolanc", "e => e.value") == "1", "lancamento ligado: a edicao mostra o Trator A escolhido")
    limpa()
    page.fill("#f-descricaolanc", "Filtro do trator (editado)")
    salva()
    w = escritas()
    conf(len(w) == 1 and w[0]["op"] == "update" and w[0]["v"].get("equipamento_id") == 1 and w[0]["v"]["descricao"].endswith("(editado)"), "mexer so na descricao nao perde o equipamento", str(w))
    edita(1)
    limpa()
    page.select_option("#f-equipamentolanc", "")
    salva()
    w = escritas()
    conf(len(w) == 1 and w[0]["op"] == "update" and "equipamento_id" in w[0]["v"] and w[0]["v"]["equipamento_id"] is None, "tirar o equipamento manda null", str(w))
    edita(2)
    limpa()
    page.fill("#f-descricaolanc", "Conta sem maquina (editada)")
    salva()
    w = escritas()
    conf(len(w) == 1 and w[0]["op"] == "update" and "equipamento_id" not in w[0]["v"], "lancamento que nunca teve maquina: editar nao manda a coluna", str(w))
    conf(bool(w) and w[0]["v"].get("mes") == "2026-09" and w[0]["v"].get("data") is None, "a competencia so com o mes continua intacta (mes 2026-09, sem data)", str(w[0]["v"]) if w else "")
    edita(3)
    ops = page.eval_on_selector("#f-equipamentolanc", "e => [...e.options].map(o => o.value)")
    conf(ops == ["", "1", "2", "3"] and page.eval_on_selector("#f-equipamentolanc", "e => e.value") == "3", "equipamento inativo que ja estava ligado continua aparecendo e escolhido", str(ops))

    print("== dividir entre atividades")
    novo("despesa")
    limpa()
    page.select_option("#f-atividadelanc", "dividir")
    page.wait_for_timeout(250)
    page.select_option("#f-centrocustolanc", "9")
    page.fill("#f-descricaolanc", "Revisao geral")
    page.click("#f-valorlanc")
    page.fill("#f-valorlanc", "")
    page.keyboard.type("900")
    page.select_option("#f-equipamentolanc", "2")
    salva()
    w = escritas()
    linhas = w[0]["v"] if w and isinstance(w[0]["v"], list) else []
    conf(len(linhas) == 3 and all(x.get("equipamento_id") == 2 for x in linhas) and round(sum(x["valor"] for x in linhas), 2) == 900.0,
         "as 3 partes levam o equipamento e somam R$ 900", str(w)[:300])

    print("== sem equipamentos")
    page.close()
    page = abre(browser, dict(DB, equipamentos=[]))
    novo("despesa")
    conf(page.locator("#f-equipamentolanc").count() == 0, "sem equipamentos cadastrados (ou sem acesso a tabela) o campo nao aparece")
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
