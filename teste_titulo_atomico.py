"""
Salvar uma conta a pagar/receber grava a conta e as partes do rateio numa operacao so, no banco
(achado da revisao geral de 05/11/2026: lancar em N parcelas fazia 2 chamadas por parcela e editar
apagava e regravava as partes em chamadas separadas; uma falha no meio deixava parcelas soltas ou
a conta sem rateio, e foi assim que a conta #107 ficou com as partes em dobro).
O SQL esta em titulos_atomico_01.sql (ensaiado num Postgres descartavel). Aqui se prova o lado do app:
  - com a funcao no banco, o app faz UMA chamada (salvar_titulos) com todas as parcelas e as partes de
    cada uma, e NAO grava titulos nem rateios em chamadas separadas;
  - cada parcela leva partes que somam o valor dela (a ultima absorve o arredondamento) e as parcelas
    somam o total;
  - editar manda o id da conta e as partes novas (com uma parte so, ela vale o total);
  - se o banco recusar, o app mostra a mensagem, nao grava mais nada e deixa o formulario aberto;
  - se a funcao ainda nao existir no banco (o SQL nao rodou), o app usa o caminho antigo.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

DB = {
    "fazendas": [], "fazenda_atividades": [],
    "centros_custo": [
        {"id": 90, "fazenda_id": None, "nome": "ADUBOS", "frente": None, "ativo": True, "tipo": "saida", "subcategoria": "OPERACIONAL | X"},
    ],
    "lancamentos_financeiros": [], "lotes": [],
    "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "abates": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

# o que a funcao do banco faz, em JS (a de verdade esta no SQL e foi ensaiada la)
EMULA_BANCO = """
window.__RPC__ = {
  salvar_titulos: (args) => {
    if (window.__RECUSAR__) return { data: null, error: { code: 'P0001', message: window.__RECUSAR__ } };
    const ids = [];
    for (const it of args.p_itens) {
      let id = it.id;
      if (id) {
        const t = window.__DB__.titulos.find(x => x.id === id);
        Object.assign(t, it.titulo);
        window.__DB__.titulo_rateios = window.__DB__.titulo_rateios.filter(r => r.titulo_id !== id);
      } else {
        id = window.__DB__.titulos.reduce((m, x) => Math.max(m, x.id), 0) + 1;
        window.__DB__.titulos.push({ id, cancelado: false, valor_baixado: 0, situacao: 'aberto', ...it.titulo });
      }
      for (const r of it.rateios) {
        const rid = window.__DB__.titulo_rateios.reduce((m, x) => Math.max(m, x.id), 0) + 1;
        window.__DB__.titulo_rateios.push({ id: rid, titulo_id: id, ...r });
      }
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


def abre_conta(page, draft_js):
    page.evaluate("""(draft) => {
      window.__ESCRITAS__ = []; window.__CHAMADAS_RPC__ = []; state.erroTitulo = '';
      state.page = 'contas'; editDraft = draft; state.modal = {type:'titulo'}; render(); }""", draft_js)
    page.wait_for_timeout(300)


def escreveu(page, tabela):
    return page.evaluate("(t) => window.__ESCRITAS__.filter(e => e.tabela === t)", tabela)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    dialogos = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: (dialogos.append(d.message), d.accept()))
    page.on("console", lambda m: dialogos.append(m.text[len("[aviso] "):]) if m.text.startswith("[aviso] ") else None)   # o alert() virou aviso na tela (07/11/2026)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.add_init_script(EMULA_BANCO)
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.centrosCusto && state.centrosCusto.length > 0", timeout=30000)
    page.wait_for_timeout(600)

    print("== conta nova em 3 parcelas, com a funcao no banco")
    abre_conta(page, {"tipo": "pagar", "descricao": "Trator", "valor": "10000", "vencimento": "2026-12-31", "parcelas": 3,
                      "intervaloTipo": "mensal", "previsao": False,
                      "rateios": [{"fazendaId": "", "atividade": "cana", "centroCustoId": 90, "competencia": "2026-12", "valor": 7000},
                                  {"fazendaId": "", "atividade": "pecuaria", "centroCustoId": 90, "competencia": "2026-12", "valor": 3000}]})
    page.click("[data-save='titulo']")
    page.wait_for_timeout(1200)
    chamadas = page.evaluate("() => window.__CHAMADAS_RPC__")
    conf(len(chamadas) == 1 and chamadas[0]["nome"] == "salvar_titulos", "uma chamada a salvar_titulos", str(chamadas)[:160])
    conf(not escreveu(page, "titulos") and not escreveu(page, "titulo_rateios"), "nao grava conta nem partes em chamadas separadas",
         str(page.evaluate("() => window.__ESCRITAS__"))[:200])
    itens = chamadas[0]["args"]["p_itens"] if chamadas else []
    conf(len(itens) == 3, "as 3 parcelas vao juntas", str(len(itens)))
    if itens:
        conf(abs(sum(i["titulo"]["valor"] for i in itens) - 10000) < 0.005, "as parcelas somam o total (R$ 10.000,00)")
        conf(all(abs(sum(r["valor"] for r in i["rateios"]) - i["titulo"]["valor"]) < 0.005 for i in itens), "as partes de cada parcela somam o valor dela")
        conf([i["titulo"]["parcela"] for i in itens] == [1, 2, 3] and all(i["titulo"]["parcelas"] == 3 for i in itens), "numero da parcela e total certos")
        conf(len({i["titulo"]["grupo"] for i in itens}) == 1 and itens[0]["titulo"]["grupo"], "todas no mesmo grupo")
        conf(all("id" not in i for i in itens) and all("titulo_id" not in r for i in itens for r in i["rateios"]), "contas novas: sem id, e as partes sem titulo_id (o banco liga)")
    conf(page.evaluate("() => state.titulos.length") == 3, "as 3 contas aparecem na lista", str(page.evaluate("() => state.titulos.length")))
    conf(page.evaluate("() => state.modal") is None, "o formulario fecha")

    print("== editar uma conta")
    abre_conta(page, {"_editId": 1, "tipo": "pagar", "descricao": "Trator editado", "valor": "4000", "vencimento": "2027-01-15", "parcelas": 1,
                      "intervaloTipo": "mensal", "previsao": False,
                      "rateios": [{"fazendaId": "", "atividade": "cana", "centroCustoId": 90, "competencia": "2027-01", "valor": 1}]})
    page.click("[data-save='titulo']")
    page.wait_for_timeout(1000)
    chamadas = page.evaluate("() => window.__CHAMADAS_RPC__")
    conf(len(chamadas) == 1 and chamadas[0]["args"]["p_itens"][0].get("id") == 1, "uma chamada, com o id da conta", str(chamadas)[:160])
    it = chamadas[0]["args"]["p_itens"][0] if chamadas else {}
    conf(it.get("titulo", {}).get("valor") == 4000 and it.get("titulo", {}).get("descricao") == "Trator editado", "valor e descricao novos")
    conf(len(it.get("rateios", [])) == 1 and it["rateios"][0]["valor"] == 4000, "com uma parte so, ela vale o total da conta (4.000)", str(it.get("rateios")))
    conf(not escreveu(page, "titulos") and not escreveu(page, "titulo_rateios"), "sem chamadas separadas")
    conf(page.evaluate("() => state.titulos.find(t => t.id === 1).valor") == 4000, "a conta na tela tem o valor novo")

    print("== o banco recusa")
    page.evaluate("() => { window.__RECUSAR__ = 'A soma dos rateios (60) nao fecha com o valor do titulo (100).'; }")
    abre_conta(page, {"tipo": "pagar", "descricao": "Recusada", "valor": "100", "vencimento": "2027-02-01", "parcelas": 1, "intervaloTipo": "mensal",
                      "previsao": False, "rateios": [{"fazendaId": "", "atividade": "cana", "centroCustoId": 90, "competencia": "2027-02", "valor": 100}]})
    dialogos.clear()
    n_antes = page.evaluate("() => window.__DB__.titulos.length")
    page.click("[data-save='titulo']")
    page.wait_for_timeout(800)
    conf(any("nao fecha com o valor do titulo" in d for d in dialogos), "mostra a mensagem do banco", str(dialogos))
    conf(not escreveu(page, "titulos") and not escreveu(page, "titulo_rateios"), "e nao grava mais nada por conta propria")
    conf(page.evaluate("() => state.modal") is not None, "o formulario continua aberto")
    conf(page.evaluate("() => window.__DB__.titulos.length") == n_antes, "nenhuma conta nova")

    print("== a funcao ainda nao existe no banco: caminho antigo")
    page.evaluate("() => { window.__RECUSAR__ = null; window.__RPC__ = {}; state.modal = null; editDraft = null; render(); }")
    abre_conta(page, {"tipo": "pagar", "descricao": "Pelo caminho antigo", "valor": "600", "vencimento": "2027-03-01", "parcelas": 2, "intervaloTipo": "mensal",
                      "previsao": False, "rateios": [{"fazendaId": "", "atividade": "cana", "centroCustoId": 90, "competencia": "2027-03", "valor": 600}]})
    page.click("[data-save='titulo']")
    page.wait_for_timeout(1200)
    conf(len([e for e in escreveu(page, "titulos") if e["op"] == "insert"]) == 2, "grava as 2 contas pelo caminho antigo")
    conf(len([e for e in escreveu(page, "titulo_rateios") if e["op"] == "insert"]) == 2, "e as partes de cada uma")
    conf(page.evaluate("() => state.titulos.filter(t => t.descricao === 'Pelo caminho antigo').length") == 2, "e elas aparecem na lista")

    conf(not erros, "sem erro de JS", "; ".join(erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
