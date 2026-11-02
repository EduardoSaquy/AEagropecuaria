"""
AE Pecuaria: fila offline sem duplicar (Eduardo, 02/11/2026).
Simula o caso do sinal fraco: o banco GRAVA o lancamento e a resposta se
perde no caminho. Antes o app enfileirava e reenviava, e o lancamento (e a
baixa de estoque) ficava em dobro. Agora cada lancamento leva uma chave do
aparelho (client_uuid); o stub imita o indice unico do banco
(pecuaria_fila_offline_sem_duplicar.sql) e o reenvio so completa o que
faltou. Sem a coluna no banco (antes do SQL), grava como antes.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}
DB = {
    "lotes": [{"id": 1, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 50, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1, "sexo": "macho"},
              {"id": 6, "nome": "Vacas 07/08", "destino": "cria", "numero_animais": 80, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1}],
    "dietas": [{"id": 1, "nome": "Dieta", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}], "consumo_direto": True}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1.5}],
    "centros_custo": [{"id": 9, "nome": "Vendas"}],
    "animais": [], "partos": [], "desmamas": [], "diagnosticos_gestacionais": [], "reproducao_custos": [],
    "fazendas": [], "fazenda_atividades": [], "lancamentos_financeiros": [],
    "pesagens": [], "manejos": [], "movimentos": [], "saidas_racao": [], "leituras_cocho": [], "pasto": [],
    "producoes_racao": [], "abates": [], "precos_arroba": [], "config_financeiro": [],
    "funcionarios": [], "pesagens_animais": [], "protocolos_inseminacao": [],
}
# imita o indice unico de client_uuid e a resposta que se perde depois de gravar
EMBRULHO = """(() => {
  const orig = db.from.bind(db);
  window.__PERDER__ = {};
  window.__SEM_COLUNA__ = false;
  const cadeia = r => ({ select(){ return { single: () => Promise.resolve(r), then: (a,b) => Promise.resolve(r).then(a,b) }; },
                         then: (a,b) => Promise.resolve(r).then(a,b) });
  db.from = (t) => {
    const q = orig(t);
    const ins = q.insert.bind(q);
    q.insert = (v) => {
      const linhas = Array.isArray(v) ? v : [v];
      if (window.__SEM_COLUNA__ && linhas.some(r => 'client_uuid' in r))
        return cadeia({data:null, error:{code:'PGRST204', message:"Could not find the 'client_uuid' column of '"+t+"' in the schema cache"}});
      if (linhas.some(r => r.client_uuid && (window.__DB__[t]||[]).some(x => x.client_uuid === r.client_uuid)))
        return cadeia({data:null, error:{code:'23505', message:'duplicate key value violates unique constraint "'+t+'_client_uuid_key"'}});
      const real = ins(v);
      if ((window.__PERDER__[t]||0) > 0) { window.__PERDER__[t]--; return cadeia({data:null, error:{message:'Failed to fetch'}}); }
      return real;
    };
    return q;
  };
})()"""

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def conta(page, tabela):
    return page.evaluate(f"() => (window.__DB__['{tabela}']||[]).length")

def sincroniza(page):
    page.evaluate("async () => { await tentarSincronizarFila(); }")
    page.wait_for_timeout(300)

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.accept())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto((REPO / "AEpecuaria.html").as_uri()); page.wait_for_timeout(1500)
    page.evaluate(EMBRULHO)
    print("\n  AE PECUARIA: FILA OFFLINE SEM DUPLICAR")
    conf(not erros, "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # 1. saida de racao: grava, a resposta se perde, vai para a fila, reenvia
    page.evaluate("() => { window.__PERDER__.saidas_racao = 1; }")
    r = page.evaluate("async () => await salvarOuEnfileirar('saidaRacao', {dietaId:1, loteId:1, data:'2026-11-01', quantidadeKg:100})")
    conf(r.get("enfileirado") is True, "resposta perdida: o lancamento vai para a fila", str(r))
    conf(conta(page, "saidas_racao") == 1 and conta(page, "movimentos") == 0, "o banco ja tem a saida (sem a baixa de estoque)")
    chave = page.evaluate("() => lerFilaOffline()[0]?.campos?._chave")
    conf(bool(chave) and page.evaluate("() => window.__DB__.saidas_racao[0].client_uuid") == chave,
         "a fila guarda a mesma chave que foi gravada no banco")
    sincroniza(page)
    conf(conta(page, "saidas_racao") == 1, "reenvio: continua 1 saida de racao (antes ficava 2)", str(conta(page, "saidas_racao")))
    conf(conta(page, "movimentos") == 1, "reenvio: a baixa de estoque que faltava entrou, uma vez", str(conta(page, "movimentos")))
    conf(page.evaluate("() => lerFilaOffline().length") == 0, "a fila esvaziou")

    # 2. a baixa de estoque grava e a resposta se perde: nao pode baixar duas vezes
    page.evaluate("() => { window.__PERDER__.movimentos = 1; }")
    r = page.evaluate("async () => await salvarOuEnfileirar('saidaRacao', {dietaId:1, loteId:1, data:'2026-11-02', quantidadeKg:50})")
    conf(r.get("enfileirado") is True, "baixa de estoque com resposta perdida: vai para a fila", str(r))
    sincroniza(page)
    conf(conta(page, "saidas_racao") == 2 and conta(page, "movimentos") == 2,
         "depois do reenvio: 2 saidas e 2 baixas no total (sem baixa orfa nem em dobro)",
         f"saidas={conta(page,'saidas_racao')} movimentos={conta(page,'movimentos')}")
    orfas = page.evaluate("() => window.__DB__.movimentos.filter(m => !window.__DB__.saidas_racao.some(s => s.id === m.saida_racao_id)).length")
    conf(orfas == 0, "nenhuma baixa de estoque ligada a saida apagada", str(orfas))

    # 3. parto, inseminacao, diagnostico, cocho, desmama: uma linha so
    for tipo, tabela, campos in (
        ("parto", "partos", "{loteId:6, data:'2026-10-01', numeroMae:'500', racaMae:'nelore', sexoBezerro:'macho', racaBezerro:'nelore'}"),
        ("reproducaoCusto", "reproducao_custos", "{loteId:6, data:'2026-10-19', numeroVaca:'501', racaVaca:'nelore', racaTouro:'nelore', qualInseminacao:'1', custo:46.3}"),
        ("diagnosticoGestacional", "diagnosticos_gestacionais", "{loteId:6, data:'2026-11-01', numeroVaca:'502', racaVaca:'nelore', resultado:'prenha'}"),
        ("cocho", "leituras_cocho", "{loteId:1, data:'2026-11-01', nota:2, observacao:''}"),
    ):
        page.evaluate(f"() => {{ window.__PERDER__['{tabela}'] = 1; }}")
        r = page.evaluate(f"async () => await salvarOuEnfileirar('{tipo}', {campos})")
        sincroniza(page)
        conf(r.get("enfileirado") is True and conta(page, tabela) == 1, f"{tipo}: resposta perdida + reenvio = 1 linha so", f"{r} linhas={conta(page, tabela)}")

    # 4. venda: abate, receita e baixa do lote uma vez so
    page.evaluate("() => { window.__PERDER__.abates = 1; }")
    r = page.evaluate("""async () => await salvarOuEnfileirar('venda', {loteId:1, data:'2026-11-01', quantidade:2, tipoVenda:'cabeca',
        pesoMedioKg:0, arrobasTotais:'', valorArroba:0, valorPorAnimal:3000, valorKg:0, categoria:'abate', sexo:'macho', observacao:''})""")
    sincroniza(page)
    receitas = page.evaluate("() => window.__DB__.lancamentos_financeiros.filter(l => l.abate_id).length")
    conf(r.get("enfileirado") is True and conta(page, "abates") == 1 and receitas == 1,
         "venda: resposta perdida + reenvio = 1 venda e 1 receita", f"abates={conta(page,'abates')} receitas={receitas}")

    # 5. pesagem com peso por animal
    page.evaluate("() => { window.__PERDER__.pesagens = 1; }")
    r = page.evaluate("""async () => await salvarOuEnfileirar('pesagem', {loteId:1, data:'2026-11-01', pesoMedioKg:450, observacao:'',
        entradasPesagem:[{numero:'700', pesoKg:440}, {numero:'701', pesoKg:460}]})""")
    sincroniza(page)
    conf(conta(page, "pesagens") == 1 and conta(page, "pesagens_animais") == 2,
         "pesagem: resposta perdida + reenvio = 1 pesagem e os 2 pesos por animal",
         f"pesagens={conta(page,'pesagens')} animais={conta(page,'pesagens_animais')}")

    # 6. sem a coluna no banco (SQL ainda nao rodou): grava como antes
    page.evaluate("() => { window.__SEM_COLUNA__ = true; tabelasSemChave.clear(); }")
    antes = conta(page, "desmamas")
    r = page.evaluate("async () => await salvarOuEnfileirar('desmama', {partoId:1, data:'2026-11-01', raca:'nelore', pesoKg:200})")
    ultima = page.evaluate("() => window.__DB__.desmamas.at(-1)")
    conf(r.get("ok") is True and conta(page, "desmamas") == antes + 1 and "client_uuid" not in ultima,
         "banco sem a coluna client_uuid: grava normalmente, sem a chave", f"{r} {ultima}")

    conf(not erros, "nenhum erro de JavaScript no caminho", " | ".join(erros[:3]))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
