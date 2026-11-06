"""
Financeiro nao desenha as 21 mil linhas de uma vez (achado da revisao geral de
05/11/2026: a lista de despesas criava 287 mil elementos, 2,6 s no PC e ~23 s num
tablet de entrada; cada tecla da busca refazia tudo, 1 s no PC e 6 s no tablet).
Prova:
  - a lista desenha 100 linhas e diz "Mostrando 100 de N";
  - o total continua sendo o do filtro inteiro (nao so das linhas desenhadas);
  - "Mostrar mais" soma 200 por vez e some quando acaba;
  - a busca espera a pessoa parar de digitar: varias teclas seguidas = 1 redesenho,
    o foco volta ao campo e o texto digitado nao se perde;
  - trocar de aba, de atividade ou de mes volta para 100 linhas;
  - lista curta (cabe nas 100) nao mostra o rodape nem o "(N lancamentos)";
  - editar uma linha da lista continua abrindo o lancamento certo.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
N_DESPESAS = 450
lancs = []
for i in range(1, N_DESPESAS + 1):
    dia = 1 + (i % 28)
    mes = 1 + (i % 12)
    lancs.append({"id": i, "tipo": "despesa", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 9,
                  "descricao": f"Conta {i}", "valor": 10, "data": f"2026-{mes:02d}-{dia:02d}", "mes": f"2026-{mes:02d}",
                  "fornecedor": f"FORN {i % 10}", "areas": []})
for j in range(1, 31):
    lancs.append({"id": 1000 + j, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": None, "centro_custo_id": 10,
                  "descricao": f"Venda {j}", "valor": 100, "data": "2026-03-10", "mes": "2026-03", "areas": []})
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [],
    "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [
        {"id": 9, "fazenda_id": None, "nome": "Energia", "frente": None, "ativo": True, "tipo": "saida",
         "subcategoria": "DESPESAS OPERACIONAIS | Energia"},
        {"id": 10, "fazenda_id": None, "nome": "Vendas", "frente": None, "ativo": True, "tipo": "entrada",
         "subcategoria": "RECEITAS | Vendas"},
    ],
    "lancamentos_financeiros": lancs,
    "financiamentos": [], "parcelas_financiamento": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
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


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    linhas = lambda: page.evaluate("() => document.querySelectorAll('[data-edit-lancamento]').length")
    rodape = lambda: page.evaluate("() => (document.querySelector('[data-lista-financeiro-resumo]')||{}).textContent || ''")
    tem_mais = lambda: page.evaluate("() => !!document.querySelector('[data-mais-lancamentos]')")
    total_txt = lambda: page.evaluate("() => { const t=[...document.querySelectorAll('tbody tr')].pop(); return t ? t.textContent : ''; }")

    def abrir(aba="despesa"):
        page.evaluate(f"() => {{ state.page='financeiro'; state.abaFinanceiro='{aba}'; state.filtroAtividade=''; "
                      "state.filtroMesDespesas=''; state.searchDespesas=''; state.limiteListaFinanceiro=100; "
                      "state.modal=null; editDraft=null; render(); }")
        page.wait_for_timeout(300)

    print("\n  A LISTA DESENHA 100 LINHAS, NAO TODAS")
    abrir()
    conf(linhas() == 100, "450 despesas: so 100 linhas desenhadas", str(linhas()))
    conf("Mostrando 100 de 450" in rodape(), "o rodape diz quantas aparecem e quantas existem", rodape())
    conf("4.500,00" in total_txt() and "450 lançamentos" in total_txt(),
         "o total e o do filtro inteiro (450 x R$ 10), nao so das 100 linhas", total_txt())
    conf(page.evaluate("() => document.querySelectorAll('#root *').length") < 4000,
         "a pagina tem poucos elementos (nao os milhares de uma lista inteira)",
         str(page.evaluate("() => document.querySelectorAll('#root *').length")))

    print("\n  MOSTRAR MAIS")
    page.locator("[data-mais-lancamentos]").click(); page.wait_for_timeout(250)
    conf(linhas() == 300, "um clique soma 200 linhas (300)", str(linhas()))
    conf("Mostrando 300 de 450" in rodape(), "o rodape acompanha", rodape())
    conf("Mostrar mais 150" in page.locator("[data-mais-lancamentos]").inner_text(), "o botao oferece so o que falta (150)")
    page.locator("[data-mais-lancamentos]").click(); page.wait_for_timeout(250)
    conf(linhas() == 450, "o segundo clique mostra todas (450)", str(linhas()))
    conf(not tem_mais() and rodape() == "", "acabou: o botao e o rodape somem")
    conf("Total listado" in total_txt() and "lançamentos)" not in total_txt(),
         "com tudo na tela o total volta a ser 'Total listado'", total_txt())

    print("\n  BUSCA: ESPERA PARAR DE DIGITAR")
    abrir()
    page.evaluate("() => { window.__renders = 0; const r = render; render = function(){ window.__renders++; return r.apply(this, arguments); }; }")
    page.click("[data-search-despesas]")
    page.keyboard.type("FORN 3", delay=25)           # 6 teclas em ~150 ms, menos que a espera
    conf(page.evaluate("() => window.__renders") == 0, "digitando, nada e redesenhado a cada tecla",
         str(page.evaluate("() => window.__renders")))
    conf(page.evaluate("() => state.searchDespesas") == "FORN 3", "o texto digitado ja vale no estado")
    page.wait_for_timeout(600)
    conf(page.evaluate("() => window.__renders") == 1, "depois da pausa redesenha uma vez so",
         str(page.evaluate("() => window.__renders")))
    conf(linhas() == 45, "a busca achou as 45 contas do FORN 3 (450 / 10)", str(linhas()))
    conf(not tem_mais(), "45 cabem nas 100 linhas: sem 'Mostrar mais'")
    conf("450,00" in total_txt() and "lançamentos)" not in total_txt(),
         "total da busca = 45 x R$ 10, sem o '(N lancamentos)'", total_txt())
    foco = page.evaluate("() => { const a = document.activeElement; return a && a.hasAttribute('data-search-despesas') ? a.value : null; }")
    conf(foco == "FORN 3", "o foco volta ao campo, com o texto inteiro", str(foco))

    print("\n  TROCAR FILTRO VOLTA PARA 100 LINHAS")
    abrir()
    page.locator("[data-mais-lancamentos]").click(); page.wait_for_timeout(250)
    conf(linhas() == 300, "(preparo) 300 linhas abertas")
    page.select_option("[data-filtro-mes-despesas]", "2026-03")
    page.wait_for_timeout(250)
    conf(page.evaluate("() => state.limiteListaFinanceiro") == 100, "trocar o mes volta o limite para 100")
    abrir()
    page.locator("[data-mais-lancamentos]").click(); page.wait_for_timeout(250)
    page.select_option("[data-filtro-atividade]", "cana")
    page.wait_for_timeout(250)
    conf(page.evaluate("() => state.limiteListaFinanceiro") == 100, "trocar a atividade volta o limite para 100")
    abrir()
    page.locator("[data-mais-lancamentos]").click(); page.wait_for_timeout(250)
    page.locator('[data-aba-financeiro="receita"]').click(); page.wait_for_timeout(250)
    conf(page.evaluate("() => state.limiteListaFinanceiro") == 100 and linhas() == 30,
         "trocar de aba volta o limite e mostra as 30 receitas inteiras", str(linhas()))
    conf(not tem_mais(), "30 receitas: sem 'Mostrar mais'")

    print("\n  EDITAR CONTINUA NA LINHA CERTA")
    abrir()
    id_primeira = page.evaluate("() => document.querySelector('[data-edit-lancamento]').dataset.editLancamento")
    desc_primeira = page.evaluate("() => document.querySelector('tbody tr strong').textContent")
    page.locator("[data-edit-lancamento]").first.click(); page.wait_for_timeout(300)
    conf(page.evaluate("() => (document.getElementById('f-descricaolanc')||{}).value") == desc_primeira,
         "o Editar da primeira linha abre o lancamento dela", f"{id_primeira} / {desc_primeira}")

    conf(not erros, "nenhum erro de JavaScript", str(erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
