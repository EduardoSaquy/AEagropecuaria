"""
A venda de animais grava abate, receita e baixa do lote numa operacao so, no banco
(achado da revisao geral de 05/11/2026: eram tres chamadas separadas do navegador, com o saldo do
lote vindo da memoria da tela; duas pessoas vendendo do mesmo lote perdiam uma venda).
O SQL esta em venda_animais_atomica_01.sql (ensaiado num Postgres descartavel, inclusive com duas
vendas ao mesmo tempo). Aqui se prova o lado do app:
  - com a funcao no banco, o app faz UMA chamada (registrar_venda_animais) com o abate e a receita
    e NAO grava abate, receita nem lote em chamadas separadas;
  - depois de vender, o lote na tela ja mostra o saldo novo;
  - se o banco recusar (outra venda passou na frente), o app mostra a mensagem do banco, nao grava
    mais nada e deixa o formulario aberto;
  - se a funcao ainda nao existir no banco (o SQL nao rodou), o app usa o caminho antigo e a venda
    continua funcionando.
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
        {"id": 92, "fazenda_id": None, "nome": "VENDAS", "frente": None, "ativo": True, "tipo": "entrada", "subcategoria": "ATIVIDADES OPERACIONAIS"},
    ],
    "lancamentos_financeiros": [],
    "lotes": [{"id": 1, "nome": "Curral 1", "numero_animais": 100, "destino": "confinamento", "data_fim": None}],
    "funcionarios": [], "funcionario_atividades": [], "talhoes_areas": [], "culturas": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [], "abates": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

# o que a funcao do banco faz, em JS (a de verdade esta no SQL e foi ensaiada la)
EMULA_BANCO = """
window.__RPC__ = {
  registrar_venda_animais: (args) => {
    const lote = window.__DB__.lotes.find(l => l.id === args.p_abate.lote_id);
    if (window.__RECUSAR__) return { data: null, error: { code: 'P0001', message: window.__RECUSAR__ } };
    const abateId = (window.__DB__.abates.reduce((m, a) => Math.max(m, a.id), 0)) + 1;
    window.__DB__.abates.push({ id: abateId, ...args.p_abate });
    const lancId = (window.__DB__.lancamentos_financeiros.reduce((m, a) => Math.max(m, a.id), 0)) + 1;
    window.__DB__.lancamentos_financeiros.push({ id: lancId, ...args.p_lancamento, abate_id: abateId });
    lote.numero_animais -= args.p_abate.quantidade;
    return { data: { abate_id: abateId, lancamento_id: lancId, restante: lote.numero_animais }, error: null };
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


def abre_venda(page, qtd):
    page.evaluate("""(qtd) => {
      window.__ESCRITAS__ = []; window.__CHAMADAS_RPC__ = [];
      state.page = 'financeiro'; state.abaFinanceiro = 'receita'; state.erroLancamento = '';
      editDraft = {tipo:'receita', atividade:'pecuaria', fazendaId:'', centroCustoId:92, descricao:'Venda de boi gordo', valor:'',
                   data:'2026-09-10', ehVenda:true, tipoVenda:'arroba', categoria:'abate', sexo:'macho', loteId:1, qtdAnimais:qtd,
                   arrobasTotais:String(qtd * 18), valorArroba:'320', areas:[]};
      state.modal = {type:'lancamento'}; render();
    }""", qtd)
    page.wait_for_timeout(300)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    dialogos = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: (dialogos.append(d.message), d.accept()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.add_init_script(EMULA_BANCO)
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lotesPec && state.lotesPec.length > 0", timeout=30000)
    page.wait_for_timeout(800)

    print("== com a funcao no banco: uma chamada so")
    abre_venda(page, 30)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(1200)
    chamadas = page.evaluate("() => window.__CHAMADAS_RPC__")
    conf(len(chamadas) == 1 and chamadas[0]["nome"] == "registrar_venda_animais", "uma chamada a registrar_venda_animais", str(chamadas)[:200])
    esc = page.evaluate("() => window.__ESCRITAS__")
    conf(not [e for e in esc if e["tabela"] == "abates"], "nao grava abate em chamada separada", str(esc)[:200])
    conf(not [e for e in esc if e["tabela"] == "lancamentos_financeiros" and e["op"] == "insert"], "nao grava a receita em chamada separada")
    conf(not [e for e in esc if e["tabela"] == "lotes"], "nao mexe no lote em chamada separada")
    if chamadas:
        a, l = chamadas[0]["args"]["p_abate"], chamadas[0]["args"]["p_lancamento"]
        conf(a["lote_id"] == 1 and a["quantidade"] == 30 and a["tipo_venda"] == "arroba" and abs(a["valor_arroba"] - 320) < 0.001,
             "o abate vai com lote, quantidade, forma e valor da arroba", str(a))
        conf(l["tipo"] == "receita" and l["atividade"] == "pecuaria" and abs(float(l["valor"]) - 540 * 320) < 0.01 and abs(l["arrobas"] - 540) < 0.001,
             "a receita vai com o valor calculado (540 @ x R$ 320) e as arrobas", str(l)[:300])
        conf("abate_id" not in l and "id" not in l, "e sem id nem abate_id (quem da isso e o banco)")
    conf(page.evaluate("() => state.lotesPec.find(l => l.id === 1).numeroAnimais") == 70, "o lote na tela mostra o saldo novo (70)")
    conf(page.evaluate("() => state.modal") is None, "o formulario fecha")
    conf(page.evaluate("() => state.lancamentos.some(l => l.descricao === 'Venda de boi gordo')"), "a receita aparece na lista")

    print("== o banco recusa (outra venda passou na frente)")
    page.evaluate("() => { window.__RECUSAR__ = 'O lote \"Curral 1\" tem 10 animal(is); nao da para vender 30. Outra venda pode ter passado na frente.'; }")
    abre_venda(page, 30)
    dialogos.clear()
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(900)
    conf(any("tem 10 animal(is)" in d for d in dialogos), "mostra a mensagem do banco", str(dialogos))
    esc = page.evaluate("() => window.__ESCRITAS__")
    conf(not [e for e in esc if e["tabela"] in ("abates", "lancamentos_financeiros", "lotes")], "e nao grava mais nada por conta propria", str(esc)[:200])
    conf(page.evaluate("() => state.modal") is not None, "o formulario continua aberto")
    conf(page.evaluate("() => window.__DB__.abates.length") == 1, "nenhum abate novo")

    print("== a funcao ainda nao existe no banco: caminho antigo")
    page.evaluate("() => { window.__RECUSAR__ = null; window.__RPC__ = {}; state.modal = null; editDraft = null; render(); }")
    abre_venda(page, 5)
    page.click("[data-save='lancamento']")
    page.wait_for_timeout(1200)
    esc = page.evaluate("() => window.__ESCRITAS__")
    conf(len([e for e in esc if e["tabela"] == "abates" and e["op"] == "insert"]) == 1, "grava o abate pelo caminho antigo")
    conf(len([e for e in esc if e["tabela"] == "lancamentos_financeiros" and e["op"] == "insert"]) == 1, "grava a receita pelo caminho antigo")
    conf(len([e for e in esc if e["tabela"] == "lotes" and e["op"] == "update"]) == 1, "baixa o lote pelo caminho antigo")
    conf(page.evaluate("() => state.lotesPec.find(l => l.id === 1).numeroAnimais") == 65, "e o lote fica com 65")

    conf(not erros, "sem erro de JS", "; ".join(erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
