"""
Curva ABC das despesas (Resultados > Relatorios, 07/11/2026; o Inttegra tem "curva ABC / perfil ABC de desembolso").
Conta feita a mao com um mes de despesas conhecidas. Prova:
  - por centro de custo, da maior para a menor, com % e % acumulado; classe A = ate 80% (o item e A se o acumulado ANTES
    dele ainda e menor que 80%), B = ate 95%, C = o resto; o resumo diz quantos itens e quanto do gasto em cada classe;
  - so despesa: receita e investimento nao entram; o total bate com o das despesas do periodo;
  - por fornecedor: nomes iguais com maiuscula/acento/espaco diferentes somam juntos; sem fornecedor vira "Sem fornecedor";
    mostra os 25 maiores e diz quantos itens existem;
  - segue o periodo e o filtro de atividade da aba;
  - sem despesa no filtro mostra o aviso; nao rola de lado em 1280 e em 390 px.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo Saquy", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}


def d(id_, centro, valor, forn="", ativ="pecuaria", tipo="despesa", mes="2026-03"):
    return {"id": id_, "tipo": tipo, "atividade": ativ, "fazenda_id": None, "centro_custo_id": centro, "descricao": f"L{id_}", "valor": valor,
            "data": mes + "-10", "mes": mes, "fornecedor": forn, "observacao": ""}


lanc = [
    d(1, 1, 600, "Casa Alfa"), d(2, 2, 250, "casa alfa "), d(3, 3, 100, "Casa Alfa"), d(4, 4, 30, "Fábrica Beta"), d(5, 5, 20, ""),
    d(6, 6, 7000, "Cliente", tipo="receita"),            # receita: fora
    d(7, 1, 9000, "Concessionaria", tipo="investimento"),  # investimento: fora
    d(8, 2, 500, "Outra", ativ="cana"),                    # outra atividade: so entra sem filtro
    d(9, 1, 700, "Mes Seguinte", mes="2026-04"),           # outro mes: fora
]
# muitos fornecedores pequenos para o limite de 25
lanc += [d(100 + i, 5, 1, f"Forn {i:02d}", ativ="graos", mes="2026-05") for i in range(40)]
DB = {
    "fazendas": [], "fazenda_atividades": [], "culturas": [], "talhoes_areas": [], "funcionarios": [], "funcionario_atividades": [], "lotes": [],
    "centros_custo": [{"id": i, "nome": n, "tipo": "saida", "subcategoria": f"GRUPO | {n}"} for i, n in
                      ((1, "Nutricao"), (2, "Manutencao"), (3, "Energia"), (4, "Cercas"), (5, "Diversos"), (6, "Vendas"))],
    "lancamentos_financeiros": lanc, "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
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


def abre(browser, w=1280, h=900):
    ctx = browser.new_context(viewport={"width": w, "height": h})
    page = ctx.new_page()
    page.erros = []
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.lancamentosRateados.length > 0", timeout=30000)
    page.wait_for_timeout(500)
    return page


def vai(page, periodo, ativs=None):
    page.evaluate("(a) => { state.periodo = a[0]; state.filtroAtividadesRelatorio = a[1]; state.page = 'resultados'; state.subAbaResultados = 'relatorios'; render(); }", [periodo, ativs or []])
    page.wait_for_timeout(300)


def tabela(page, qual):
    return page.evaluate("""(q) => [...document.querySelectorAll(`[data-abc="${q}"] tbody tr[data-abc-classe]`)].map(tr => {
        const c = [...tr.children].map(td => td.innerText.replace(/\\s+/g, ' ').trim());
        return {n: c[1], valor: c[2], pct: c[3], acum: c[4].split(' ')[0], classe: tr.dataset.abcClasse}; })""", qual)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = abre(browser)

    print("== por centro de custo, marco/2026, todas as atividades")
    vai(page, {"tipo": "mes", "mes": "2026-03"})
    t = tabela(page, "centro")
    # despesas de marco: Nutricao 600, Manutencao 250 + 500 (cana) = 750, Energia 100, Cercas 30, Diversos 20 -> total 1500
    conf([r["n"] for r in t] == ["Manutencao", "Nutricao", "Energia", "Cercas", "Diversos"], "da maior para a menor (receita, investimento e outro mes fora)", str([r["n"] for r in t]))
    conf([r["valor"] for r in t] == ["R$ 750,00", "R$ 600,00", "R$ 100,00", "R$ 30,00", "R$ 20,00"], "valores somados por centro", str([r["valor"] for r in t]))
    conf([r["pct"] for r in t] == ["50,0%", "40,0%", "6,7%", "2,0%", "1,3%"], "percentual de cada um", str([r["pct"] for r in t]))
    conf([r["acum"] for r in t] == ["50,0%", "90,0%", "96,7%", "98,7%", "100,0%"], "percentual acumulado", str([r["acum"] for r in t]))
    conf([r["classe"] for r in t] == ["A", "A", "B", "C", "C"], "classes: A ate 80% (o 2o item e A porque antes dele o acumulado era 50%), B ate 95%, C o resto", str([r["classe"] for r in t]))
    resumo = page.inner_text('[data-abc="centro"] p.hint')
    conf("Classe A: 2 itens, 90,0% do gasto" in resumo and "Classe B: 1 item, 6,7% do gasto" in resumo and "Classe C: 2 itens, 3,3% do gasto" in resumo, "o resumo conta itens e % de cada classe", resumo)
    conf("R$ 1.500,00" in page.inner_text('[data-abc="centro"]'), "o total e o das despesas do periodo (R$ 1.500,00)")

    print("== por fornecedor")
    f = tabela(page, "fornecedor")
    # Casa Alfa: 600 + 250 + 100 = 950 ("casa alfa " com espaco e minuscula soma junto); Outra 500; Fabrica Beta 30; Sem fornecedor 20
    conf([r["n"] for r in f][:4] == ["Casa Alfa", "Outra", "Fábrica Beta", "Sem fornecedor"], "nomes iguais com maiuscula/espaco diferentes somam juntos; vazio vira 'Sem fornecedor'", str([r["n"] for r in f]))
    conf(f[0]["valor"] == "R$ 950,00" and f[1]["valor"] == "R$ 500,00", "valores por fornecedor", str(f[:2]))

    print("== filtro de atividade e periodo")
    vai(page, {"tipo": "mes", "mes": "2026-03"}, ["pecuaria"])
    t = tabela(page, "centro")
    conf([r["n"] for r in t] == ["Nutricao", "Manutencao", "Energia", "Cercas", "Diversos"] and t[1]["valor"] == "R$ 250,00",
         "com o filtro Pecuaria a despesa da cana sai", str([(r["n"], r["valor"]) for r in t]))
    vai(page, {"tipo": "mes", "mes": "2026-04"})
    t = tabela(page, "centro")
    conf(len(t) == 1 and t[0]["n"] == "Nutricao" and t[0]["valor"] == "R$ 700,00" and t[0]["classe"] == "A", "em abril so a despesa de abril", str(t))
    vai(page, {"tipo": "mes", "mes": "2026-01"})
    conf("Sem despesa neste filtro" in page.inner_text('[data-abc="centro"]'), "sem despesa no filtro mostra o aviso")

    print("== limite de fornecedores")
    vai(page, {"tipo": "mes", "mes": "2026-05"})
    f = tabela(page, "fornecedor")
    conf(len(f) == 25, "mostra os 25 maiores", str(len(f)))
    conf("40 itens; mostrando os 25 maiores" in page.inner_text('[data-abc="fornecedor"]'), "e diz que existem 40")

    print("== sem rolar de lado")
    vai(page, {"tipo": "mes", "mes": "2026-03"})
    lat = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(lat <= 1, "1280 px: a pagina nao rola de lado (%d px)" % lat)
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    page.context.close()
    page = abre(browser, 390, 800)
    vai(page, {"tipo": "mes", "mes": "2026-03"})
    lat = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    conf(lat <= 1, "390 px: a pagina nao rola de lado (%d px)" % lat)
    caixa = page.evaluate("""() => [...document.querySelectorAll('[data-abc]')].map(e => e.scrollWidth - e.clientWidth)""")
    conf(all(x <= 1 for x in caixa), "390 px: nenhum cartao da curva rola de lado", str(caixa))
    page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
