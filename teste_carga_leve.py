"""
A carga do AE Matriz ficou leve (achado da revisao geral de 05/11/2026: cada gravacao rodava loadAll(),
que baixava os lancamentos, a visao rateada inteira e mais 3 copias dela por atividade = 120 consultas
e ~75 mil linhas com 25 mil lancamentos, e redesenhava a tela 18 vezes).
Prova:
  - a carga completa le a visao rateada UMA vez (antes eram quatro leituras) e redesenha poucas vezes;
  - os resultados de Pecuaria, Cana e Cereais continuam batendo com a soma dos lancamentos;
  - loadAll(['contas']), ['financiamentos'] e ['cadastros'] nao tocam em lancamentos nem na visao rateada,
    e nao mexem no que nao foi pedido (a lista de lancamentos na memoria e a mesma);
  - atualizarLancamentos(ids) busca so os ids e deixa a memoria IGUAL a de um recarregamento completo:
    editar, incluir, incluir varios e apagar; uma exclusao que o banco nao fez nao some da tela;
  - a ordem usada na memoria e a das consultas (sem data primeiro, depois a data mais nova);
  - excluir uma despesa pela tela nao baixa os lancamentos de novo;
  - voltar para a aba depois de 10 minutos recarrega tudo (outra pessoa pode ter gravado); antes disso, nao.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
N = 2300  # passa de 1000 para exercitar a paginacao da carga
ATIVS = ["cana", "pecuaria", "graos"]
lancs = []
for i in range(1, N + 1):
    mes = 1 + ((i // 3) % 10)  # jan a out de 2026, em todas as atividades (a janela dos resultados vai ate o mes corrente)
    lancs.append({"id": i, "tipo": "despesa" if i % 7 else "receita", "atividade": ATIVS[i % 3], "fazenda_id": None,
                  "centro_custo_id": 9 if i % 7 else 10, "descricao": f"Lancamento {i}", "valor": 10 + (i % 5),
                  "data": f"2026-{mes:02d}-{1 + (i % 27):02d}", "mes": f"2026-{mes:02d}", "fornecedor": f"FORN {i % 10}", "areas": []})
for k in range(1, 4):  # recorrentes (sem data), para a ordem
    lancs.append({"id": N + k, "tipo": "despesa", "atividade": "cana", "fazenda_id": None, "centro_custo_id": 9,
                  "descricao": f"Recorrente {k}", "valor": 50, "data": None, "mes": None, "fornecedor": "", "areas": []})
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
    "financiamentos": [], "parcelas_financiamento": [], "movimentos_financiamento": [],
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


# conta as consultas (tabela e linhas devolvidas) e os desenhos
INSTR = """() => {
  window.__CH__ = []; window.__RENDERS__ = 0;
  if(window.__orig_from) return;
  window.__orig_from = db.from.bind(db);
  db.from = (t) => { const q = window.__orig_from(t);
    const oR = q.range.bind(q); q.range = (a, b) => oR(a, b).then(r => { window.__CH__.push({t, n: (r.data||[]).length}); return r; });
    const oT = q.then.bind(q); q.then = (res, rej) => oT(r => { if(r && r.data) window.__CH__.push({t, n: (r.data||[]).length}); return res ? res(r) : r; }, rej);
    return q; };
  const oRender = window.render; window.render = function(){ window.__RENDERS__++; return oRender.apply(this, arguments); };
}"""
ZERA = "() => { window.__CH__ = []; window.__RENDERS__ = 0; }"


def linhas_de(page, tabela):
    return page.evaluate("(t) => window.__CH__.filter(c => c.t === t).reduce((s, c) => s + c.n, 0)", tabela)


def consultas_de(page, tabela):
    return page.evaluate("(t) => window.__CH__.filter(c => c.t === t).length", tabela)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: d.accept())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.lancamentos && state.lancamentos.length > 0", timeout=30000)
    page.wait_for_timeout(1500)
    page.evaluate(INSTR)

    print("== carga completa")
    page.evaluate(ZERA)
    page.evaluate("async () => { await loadAll(); }")
    page.wait_for_timeout(1500)
    conf(linhas_de(page, "lancamentos_financeiros") == N + 3, "lancamentos lidos uma vez (%d)" % (N + 3),
         str(linhas_de(page, "lancamentos_financeiros")))
    conf(linhas_de(page, "lancamentos_rateados") == N + 3, "visao rateada lida UMA vez, nao quatro (%d linhas)" % (N + 3),
         str(linhas_de(page, "lancamentos_rateados")))
    conf(consultas_de(page, "lancamentos_rateados") == 5, "visao rateada: 1a pagina e depois uma onda de 4 em paralelo (fetchAllRows em ondas, 13/11/2026)",
         str(consultas_de(page, "lancamentos_rateados")))
    desenhos = page.evaluate("() => window.__RENDERS__")
    conf(desenhos <= 4, "a carga completa redesenha ate 4 vezes (eram 18)", str(desenhos))
    conf(page.evaluate("() => state.lancamentosRateados.length") == N + 3, "Relatorios recebem todas as linhas da visao")

    print("== resultados por atividade batem com a soma dos lancamentos")
    for ativ, chave in (("pecuaria", "pecuaria"), ("cana", "cana"), ("graos", "cereais")):
        esperado_desp = sum(l["valor"] for l in lancs if l["atividade"] == ativ and l["tipo"] == "despesa" and l["data"]
                            and l["data"].startswith("2026"))
        esperado_rec = sum(l["valor"] for l in lancs if l["atividade"] == ativ and l["tipo"] == "receita" and l["data"]
                           and l["data"].startswith("2026"))
        got = page.evaluate("""(c) => { const m = state.resultados[c].mensal.filter(x => x.mes.startsWith('2026'));
            return {desp: m.reduce((s, x) => s + x.despesa, 0), rec: m.reduce((s, x) => s + x.receita, 0)}; }""", chave)
        # recorrentes (sem data) so existem em cana e valem 50 por mes de 2026 ate o mes corrente (vigentesNoMes); aqui
        # conferimos so a parte datada: a diferenca para cana e exatamente a dos recorrentes.
        dif_desp = round(got["desp"] - esperado_desp, 2)
        conf(abs(got["rec"] - esperado_rec) < 0.01, f"{ativ}: receita do resultado = soma dos lancamentos (R$ {esperado_rec:.2f})", str(got))
        if ativ == "cana":
            conf(dif_desp >= 0 and dif_desp % 150 < 0.01, f"{ativ}: despesa = soma + os 3 recorrentes (diferenca R$ {dif_desp:.2f})", str(got))
        else:
            conf(abs(dif_desp) < 0.01, f"{ativ}: despesa do resultado = soma dos lancamentos (R$ {esperado_desp:.2f})", str(got))

    print("== grupos: so o que mudou e recarregado")
    marca = page.evaluate("() => { window.__lancAntes = state.lancamentos; window.__titAntes = state.titulos; return true; }")
    page.evaluate("() => { window.__DB__.titulos.push({id: 1, tipo: 'pagar', descricao: 'Conta nova', valor: 100, vencimento: '2026-12-01', cancelado: false}); }")
    page.evaluate(ZERA)
    page.evaluate("async () => { await loadAll(['contas']); }")
    page.wait_for_timeout(500)
    tabelas = page.evaluate("() => [...new Set(window.__CH__.map(c => c.t))].sort()")
    conf("lancamentos_financeiros" not in tabelas and "lancamentos_rateados" not in tabelas and "lotes" not in tabelas,
         "['contas'] nao toca em lancamentos, visao rateada nem lotes", str(tabelas))
    conf("titulos" in tabelas and "titulo_baixas" in tabelas and "entidades" in tabelas, "['contas'] le titulos, baixas e entidades", str(tabelas))
    conf(page.evaluate("() => state.titulos.length") == 1 and page.evaluate("() => state.titulos[0].descricao") == "Conta nova",
         "a conta nova apareceu")
    conf(page.evaluate("() => state.lancamentos === window.__lancAntes"), "['contas'] nao reatribuiu a lista de lancamentos")
    conf(page.evaluate("() => window.__RENDERS__") <= 2, "['contas'] redesenha no maximo 2 vezes", str(page.evaluate("() => window.__RENDERS__")))

    page.evaluate(ZERA)
    page.evaluate("async () => { await loadAll(['financiamentos']); }")
    page.wait_for_timeout(500)
    tabelas = page.evaluate("() => [...new Set(window.__CH__.map(c => c.t))].sort()")
    conf(tabelas == ["financiamentos", "movimentos_financiamento", "parcelas_financiamento"],
         "['financiamentos'] le so contratos, parcelas e movimentos", str(tabelas))

    page.evaluate(ZERA)
    page.evaluate("async () => { await loadAll(['cadastros']); }")
    page.wait_for_timeout(500)
    tabelas = page.evaluate("() => [...new Set(window.__CH__.map(c => c.t))].sort()")
    conf("lancamentos_financeiros" not in tabelas and "lancamentos_rateados" not in tabelas and "titulos" not in tabelas,
         "['cadastros'] nao toca em lancamentos nem em contas", str(tabelas))
    conf("fazendas" in tabelas and "centros_custo" in tabelas and "profiles" in tabelas, "['cadastros'] le fazendas, centros e perfis", str(tabelas))
    conf(page.evaluate("() => state.lancamentos === window.__lancAntes"), "['cadastros'] nao reatribuiu a lista de lancamentos")

    print("== atualizarLancamentos: so os ids, e a memoria fica igual a de um recarregamento completo")

    def foto():
        return page.evaluate("""() => JSON.stringify({
            l: state.lancamentos.map(x => [x.id, x.tipo, x.atividade, x.valor, x.data, x.descricao]).sort((a, b) => a[0] - b[0]),
            r: state.lancamentosRateados.map(x => [x.id, x.tipo, x.atividade, x.valor, x.data, x.descricao]).sort((a, b) => a[0] - b[0]),
            res: ['pecuaria', 'cana', 'cereais'].map(c => state.resultados[c].mensal.map(m => [m.mes, m.despesa, m.receita]))
        })""")

    def recarrega_completo():
        page.evaluate("async () => { await loadAll(['lancamentos']); }")
        page.wait_for_timeout(1200)

    # 1) editar
    page.evaluate("() => { const l = window.__DB__.lancamentos_financeiros.find(x => x.id === 5); l.valor = 777; l.descricao = 'Editado'; }")
    page.evaluate(ZERA)
    page.evaluate("async () => { await atualizarLancamentos([5]); }")
    page.wait_for_timeout(1200)
    conf(linhas_de(page, "lancamentos_financeiros") == 1 and linhas_de(page, "lancamentos_rateados") == 1,
         "editar 1 lancamento busca 1 linha de cada, nao os %d" % (N + 3),
         f"{linhas_de(page, 'lancamentos_financeiros')} / {linhas_de(page, 'lancamentos_rateados')}")
    conf(page.evaluate("() => state.lancamentos.find(x => x.id === 5).valor") == 777, "o valor novo aparece na lista")
    f_inc = foto(); recarrega_completo(); f_full = foto()
    conf(f_inc == f_full, "memoria depois de editar = memoria de um recarregamento completo")

    # 2) incluir (id novo)
    page.evaluate("""() => window.__DB__.lancamentos_financeiros.push({id: 9001, tipo: 'despesa', atividade: 'pecuaria', fazenda_id: null,
        centro_custo_id: 9, descricao: 'Novo', valor: 321, data: '2026-05-05', mes: '2026-05', fornecedor: 'X', areas: []})""")
    page.evaluate("async () => { await atualizarLancamentos([9001]); }")
    page.wait_for_timeout(1200)
    conf(page.evaluate("() => state.lancamentos.some(x => x.id === 9001)"), "o lancamento novo aparece na lista")
    f_inc = foto(); recarrega_completo(); f_full = foto()
    conf(f_inc == f_full, "memoria depois de incluir = recarregamento completo (inclusive os resultados)")

    # 3) incluir varios (dividir) + apagar um, na mesma chamada
    page.evaluate("""() => { const d = window.__DB__.lancamentos_financeiros;
        d.push({id: 9002, tipo: 'despesa', atividade: 'cana', fazenda_id: null, centro_custo_id: 9, descricao: 'Parte 1', valor: 50, data: '2026-06-06', mes: '2026-06', areas: []});
        d.push({id: 9003, tipo: 'despesa', atividade: 'graos', fazenda_id: null, centro_custo_id: 9, descricao: 'Parte 2', valor: 50, data: '2026-06-06', mes: '2026-06', areas: []});
        window.__DB__.lancamentos_financeiros = d.filter(x => x.id !== 7); }""")
    page.evaluate(ZERA)
    page.evaluate("async () => { await atualizarLancamentos([9002, 9003, 7]); }")
    page.wait_for_timeout(1200)
    conf(linhas_de(page, "lancamentos_financeiros") == 2, "3 ids (2 novos e 1 apagado) = 2 linhas de volta", str(linhas_de(page, "lancamentos_financeiros")))
    conf(not page.evaluate("() => state.lancamentos.some(x => x.id === 7)"), "o apagado saiu da lista")
    conf(not page.evaluate("() => state.lancamentosRateados.some(x => x.id === 7)"), "o apagado saiu da visao dos Relatorios")
    f_inc = foto(); recarrega_completo(); f_full = foto()
    conf(f_inc == f_full, "memoria depois de incluir varios e apagar = recarregamento completo")

    # 4) exclusao que o banco NAO fez (permissao): continua na tela
    page.evaluate("async () => { await atualizarLancamentos([12]); }")
    page.wait_for_timeout(800)
    conf(page.evaluate("() => state.lancamentos.some(x => x.id === 12)"), "id que o banco ainda tem continua na lista")

    # 5) a ordem da memoria e a das consultas
    ordem = page.evaluate("""() => [
        {id: 4, data: '2026-03-01'}, {id: 2, data: null}, {id: 9, data: '2026-05-01'}, {id: 1, data: null}, {id: 3, data: '2026-05-01'}
      ].sort(ordemDosLancamentos).map(x => x.id)""")
    conf(ordem == [1, 2, 3, 9, 4], "sem data primeiro (por id), depois a data mais nova (por id)", str(ordem))
    ordem = page.evaluate("""() => [
        {lancamento_id: 5, rateio_id: null}, {lancamento_id: 2, rateio_id: 8}, {lancamento_id: 2, rateio_id: 3}, {lancamento_id: 2, rateio_id: null}
      ].sort(ordemDaVisaoRateada).map(x => x.lancamento_id + ':' + x.rateio_id)""")
    conf(ordem == ["2:3", "2:8", "2:null", "5:null"], "visao rateada: lancamento_id, rateio_id, sem rateio por ultimo", str(ordem))

    print("== vigentesNoMes: mesma resposta e mesma ordem da versao antiga (fuzz com 400 listas)")
    dif = page.evaluate("""() => {
      function antiga(despesas, mesStr){
        const grupos = new Map();
        despesas.forEach(l=>{
          const areas = (l.areas||[]).slice().sort().join(',');
          const chave = `${l.descricao}||${l.centroCustoId}||${l.atividade}||${l.fazendaId ?? ''}||${areas}`;
          if(!grupos.has(chave)) grupos.set(chave, []);
          grupos.get(chave).push(l);
        });
        const out = [];
        grupos.forEach(rows=>{
          const doMes = rows.filter(l=>l.mes===mesStr);
          out.push(...(doMes.length>0 ? doMes : rows.filter(l=>!l.mes)));
        });
        return out;
      }
      let seed = 12345; const rnd = n => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
      const MESES = ['2026-01', '2026-02', '2026-03', '2026-04', null, '', undefined];
      let diferentes = 0, comparacoes = 0;
      for(let k = 0; k < 400; k++){
        const n = rnd(60);
        const lista = [];
        for(let i = 0; i < n; i++){
          lista.push({id: i, descricao: 'D' + rnd(4), centroCustoId: rnd(3), atividade: ['cana', 'pecuaria'][rnd(2)],
                      fazendaId: rnd(3) ? rnd(2) : null, areas: rnd(3) ? [] : ['cria', 'pasto'].slice(0, 1 + rnd(2)).reverse(),
                      mes: MESES[rnd(7)] || null, valor: 1 + rnd(9)});
        }
        for(const m of ['2026-01', '2026-02', '2026-03', '2026-05', null, '', undefined]){
          comparacoes++;
          const a = antiga(lista, m).map(x => x.id).join(','), b = vigentesNoMes(lista, m).map(x => x.id).join(',');
          if(a !== b) diferentes++;
        }
        // a lista cresceu depois de consultada: o guardado nao pode valer
        lista.push({id: 999, descricao: 'NOVA', centroCustoId: 1, atividade: 'cana', fazendaId: null, areas: [], mes: null, valor: 5});
        if(antiga(lista, '2026-01').map(x => x.id).join(',') !== vigentesNoMes(lista, '2026-01').map(x => x.id).join(',')) diferentes++;
      }
      return {diferentes, comparacoes};
    }""")
    conf(dif["diferentes"] == 0, "vigentesNoMes = versao antiga em %d comparacoes (resultado e ordem)" % dif["comparacoes"], str(dif))

    print("== excluir pela tela nao baixa tudo de novo")
    page.evaluate("() => { state.page = 'financeiro'; state.abaFinanceiro = 'despesa'; render(); }")
    page.wait_for_timeout(500)
    alvo = page.evaluate("() => Number(document.querySelector('[data-del-lancamento]').dataset.delLancamento)")
    page.evaluate(ZERA)
    page.click(f"[data-del-lancamento='{alvo}']")
    page.wait_for_timeout(1500)
    conf(not page.evaluate("(id) => window.__DB__.lancamentos_financeiros.some(x => x.id === id)", alvo), "a despesa foi apagada do banco")
    conf(not page.evaluate("(id) => state.lancamentos.some(x => x.id === id)", alvo), "e saiu da lista na tela")
    conf(linhas_de(page, "lancamentos_financeiros") <= 1, "sem baixar os lancamentos de novo (%d linhas)" % linhas_de(page, "lancamentos_financeiros"),
         str(linhas_de(page, "lancamentos_financeiros")))

    print("== voltar para a aba")
    page.evaluate("""() => { window.__cargas = 0; const orig = window.loadAll; window.loadAll = function(){ window.__cargas++; return orig.apply(this, arguments); };
                              state.modal = null; ultimaCargaCompleta = Date.now(); }""")
    page.evaluate("() => document.dispatchEvent(new Event('visibilitychange'))")
    page.wait_for_timeout(300)
    conf(page.evaluate("() => window.__cargas") == 0, "voltou antes de 10 minutos: nao recarrega")
    page.evaluate("() => { ultimaCargaCompleta = Date.now() - 11 * 60000; state.modal = {type: 'lancamento'}; }")
    page.evaluate("() => document.dispatchEvent(new Event('visibilitychange'))")
    page.wait_for_timeout(300)
    conf(page.evaluate("() => window.__cargas") == 0, "com um formulario aberto nao recarrega por baixo dele")
    page.evaluate("() => { state.modal = null; }")
    page.evaluate("() => document.dispatchEvent(new Event('visibilitychange'))")
    page.wait_for_timeout(1500)
    conf(page.evaluate("() => window.__cargas") == 1, "voltou depois de 11 minutos: recarrega tudo uma vez")
    conf(page.evaluate("() => Date.now() - ultimaCargaCompleta < 5000"), "e a hora da ultima carga foi atualizada")

    conf(not erros, "sem erro de JS", "; ".join(erros[:3]))
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
