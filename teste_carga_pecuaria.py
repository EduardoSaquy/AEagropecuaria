"""
AE Pecuaria: dado que nao carregou nao pode parecer "nenhum lote cadastrado".

Caso do Joilson (22/10/2026): no celular dele a tela de Cria mostrava "Nenhum
lote de cria cadastrado" e a saida de racao dizia "Nao ha lote de Cria ativo",
com 6 lotes de Cria ativos no banco, permissao de Cria e as dietas visiveis.
Consulta que falha (login vencido, rede ruim) voltava vazia sem aviso. Prova:
  - enquanto carrega, aviso "Carregando" e lancamento bloqueado com explicacao;
  - consulta de lotes com erro: aviso vermelho com "tente de novo" e o
    lancamento explica que os dados nao carregaram (nao culpa o lote);
  - login vencido (JWT expired): renova a sessao uma vez e carrega sozinho;
  - "tente de novo" carrega quando a consulta volta a funcionar;
  - sem rede, o lancamento continua liberado (fila offline como antes).
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

DB = {
    "lotes": [{"id": 6, "nome": "Vacas 09", "destino": "cria", "numero_animais": 70,
               "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1}],
    "dietas": [{"id": 1, "nome": "Dieta Cria", "tipo": "confinamento", "itens": []}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg"}],
    "fazendas": [], "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
    "animais": [], "pesagens": [], "manejos": [], "movimentos": [], "saidas_racao": [],
    "leituras_cocho": [], "pasto": [], "producoes_racao": [], "reproducao_custos": [],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [], "abates": [],
    "precos_arroba": [], "config_financeiro": [], "funcionarios": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

# envolve db.from: a tabela pedida responde com erro enquanto window.__FALHA__ disser
FALHAR = """(() => {
  const orig = db.from.bind(db);
  db.from = (t) => {
    if (window.__FALHA__ && window.__FALHA__[t]) {
      const msg = window.__FALHA__[t];
      const q = { select(){return q;}, order(){return q;}, eq(){return q;},
                  range(){ return Promise.resolve({data:null, error:{message:msg}}); } };
      return q;
    }
    return orig(t);
  };
  db.auth.refreshSession = () => {
    window.__RENOVOU__ = (window.__RENOVOU__||0) + 1;
    if (window.__RENOVA_OK__) { delete window.__FALHA__.lotes; return Promise.resolve({data:{session:window.__SESSAO__}, error:null}); }
    return Promise.resolve({data:{session:null}, error:{message:'refresh falhou'}});
  };
})()"""

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    avisos = []
    page.on("dialog", lambda d: (avisos.append(d.message), d.accept()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_timeout(1000)
    page.evaluate(FALHAR)

    print("\n  PECUARIA: DADOS QUE NAO CARREGARAM")
    conf(page.evaluate("() => state.carregouDados === true && !state.erroCarga"), "carga normal: sem aviso")

    # ---- ainda carregando ----
    avisos.clear()
    r = page.evaluate("() => { state.carregouDados = false; render(); const r = openNewModal('saidaRacaoCria'); return r; }")
    conf("Carregando os dados" in page.inner_text("body"), "enquanto carrega mostra 'Carregando os dados'")
    conf(r is False and avisos and "carregando" in avisos[0], "lancar enquanto carrega: avisa que esta carregando", str(avisos))

    # ---- lotes com erro (rede/permissao), sem ser login vencido ----
    avisos.clear()
    page.evaluate("async () => { window.__FALHA__ = {lotes: 'Failed to fetch'}; await loadAll(); state.page='lotesReproducao'; render(); }")
    page.wait_for_timeout(200)
    corpo = page.inner_text("body")
    conf("Os dados não carregaram" in corpo and "lotes" in corpo, "consulta de lotes com erro: aviso vermelho na tela", corpo[:300])
    page.evaluate("() => openNewModal('saidaRacaoCria')")
    conf(avisos and "não carregaram" in avisos[0] and "Não há lote" not in avisos[0],
         "saida de racao explica que os dados nao carregaram (nao culpa o lote)", str(avisos))

    # ---- tente de novo ----
    page.evaluate("() => { delete window.__FALHA__.lotes; }")
    page.locator('[data-recarregar-dados]').click()
    page.wait_for_timeout(500)
    conf(page.evaluate("() => !state.erroCarga && state.lotes.length === 1"), "'tente de novo' carrega quando a consulta volta")
    conf("Os dados não carregaram" not in page.inner_text("body"), "e o aviso some")

    # ---- login vencido: renova e carrega sozinho ----
    page.evaluate("async () => { window.__FALHA__ = {lotes: 'JWT expired'}; window.__RENOVA_OK__ = true; window.__RENOVOU__ = 0; await loadAll(); }")
    conf(page.evaluate("() => window.__RENOVOU__ === 1 && !state.erroCarga && state.lotes.length === 1"),
         "login vencido: renova a sessao uma vez e carrega os lotes", page.evaluate("() => [window.__RENOVOU__, state.erroCarga, state.lotes.length]"))
    page.evaluate("async () => { window.__FALHA__ = {lotes: 'JWT expired'}; window.__RENOVA_OK__ = false; window.__RENOVOU__ = 0; await loadAll(); }")
    conf(page.evaluate("() => window.__RENOVOU__ === 1 && !!state.erroCarga"),
         "renovacao que falha: tenta so uma vez e mostra o aviso", page.evaluate("() => [window.__RENOVOU__, state.erroCarga]"))

    # ---- sem rede: fila offline continua liberada ----
    page.context.set_offline(True)
    liberado = page.evaluate("() => dadosProntosParaLancar()")
    page.context.set_offline(False)
    conf(liberado is True, "sem rede o lancamento continua liberado (fila offline)")

    # ---- tudo certo de novo: saida de racao abre ----
    page.evaluate("async () => { window.__FALHA__ = {}; await loadAll(); }")
    avisos.clear()
    r = page.evaluate("() => { const r = openNewModal('saidaRacaoCria'); render(); return r; }")
    conf(r is not False and not avisos and page.locator('#f-lote').count() == 1, "com os dados carregados a saida de racao abre", str(avisos))
    conf(not erros, "nenhum erro de JavaScript", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
