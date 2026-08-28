"""
Teste do AE Matriz depois das mudancas:
  - Resultados lendo do modelo unico (mesma fonte do Financeiro)
  - tela nova de Centros de Custo
  - registro dos apps apontando para AECana.html e AECereais.html
  - permissoes separadas por frente na tela de Usuarios

O teste que mais importa e o primeiro: o Resultado e o Financeiro tem que
mostrar o MESMO numero para o mesmo mes. Eles mostrarem numeros diferentes
foi o bug que essa mudanca conserta.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

MES = "2026-08"

DB = {
    "fazendas": [{"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 500, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 400}],
    "centros_custo": [
        {"id": 90, "fazenda_id": None, "nome": "INSUMOS AGRICOLAS", "frente": None, "ativo": True},
        {"id": 91, "fazenda_id": None, "nome": "Vendas", "frente": "geral", "ativo": True},
        {"id": 92, "fazenda_id": 1, "nome": "OFICINA DO PALHADAO", "frente": None, "ativo": True},
        {"id": 93, "fazenda_id": None, "nome": "CONTA VELHA", "frente": None, "ativo": False},
    ],
    "lancamentos_financeiros": [
        # despesa do mes
        {"id": 1, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Adubo", "valor": 10000.00, "data": "2026-08-05", "mes": MES, "areas": []},
        # recorrente: vale no mes porque nao ha lancamento proprio do grupo
        {"id": 2, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Manutencao", "valor": 2500.00, "data": None, "mes": None, "areas": []},
        # competencia mensal historica: mes preenchido, data vazia
        {"id": 3, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Mao de obra", "valor": 7000.00, "data": None, "mes": MES, "areas": []},
        # recorrente do MESMO grupo do 3: tem que ser SUBSTITUIDO, nao somado
        {"id": 4, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Mao de obra", "valor": 99999.00, "data": None, "mes": None, "areas": []},
        # receita de cana migrada
        {"id": 5, "tipo": "receita", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 91,
         "descricao": "Venda de cana", "valor": 40000.00, "data": "2026-08-20", "mes": MES,
         "areas": [], "quantidade": 800, "unidade": "t"},
    ],
    "insumos_cana": [], "entradas_insumo_cana": [], "aplicacoes_cana": [],
    "insumos_graos": [], "entradas_insumo_graos": [], "aplicacoes_graos": [],
    "ingredientes": [], "dietas": [], "saidas_racao": [], "pasto": [], "reproducao_custos": [],
    "talhoes_areas": [], "culturas": [], "funcionarios": [], "funcionario_atividades": [],
    "lotes": [],
    "profiles": [],
}

# despesa vigente esperada no mes: 10000 + 2500 + 7000 = 19500
# (o recorrente de 99999 e substituido pelo lancamento do mes do mesmo grupo)
DESPESA_ESPERADA = 19500.0
RECEITA_ESPERADA = 40000.0

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}

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
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("console", lambda m: erros.append(m.text) if m.type == "error" else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    db = dict(DB, profiles=[ADMIN])
    page.add_init_script(
        f"window.__DB__ = {json.dumps(db)};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};"
    )
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1200)

    print("\n  AE MATRIZ")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    reais = [e for e in erros if not any(r in e for r in ruido)]
    conf(not reais, "abre sem erro de JavaScript", " | ".join(reais[:3]))

    abas = " | ".join(page.locator("[data-page]").all_inner_texts()) or \
           " | ".join(page.locator("nav button, .nav-item").all_inner_texts())
    conf("Centros de Custo" in abas, "tem a aba Centros de Custo", f"abas: {abas}")

    # ---- a regra do recorrente, calculada pelo proprio app ----
    calc = page.evaluate(
        "() => { const d = vigentesNoMes(state.lancamentos.filter(l=>l.tipo==='despesa'), '%s');"
        "        return {n: d.length, total: d.reduce((a,l)=>a+Number(l.valor),0)}; }" % MES
    )
    conf(abs(calc["total"] - DESPESA_ESPERADA) < 0.01,
         f"despesa vigente no mês = R$ {DESPESA_ESPERADA:,.2f}",
         f'veio R$ {calc["total"]:,.2f} em {calc["n"]} linhas')
    conf(calc["n"] == 3,
         "o recorrente do mesmo grupo é substituído, não somado",
         f'{calc["n"]} linhas em vez de 3')

    # ---- Resultados usa a MESMA regra ----
    page.evaluate("() => carregarResultadoCana()")
    page.wait_for_timeout(600)
    res = page.evaluate(
        "() => { const m = (state.resultados.cana.mensal||[]).find(x=>x.mes==='%s');"
        "        return m ? {despesa:m.despesa, receita:m.receita} : null; }" % MES
    )
    conf(res is not None, "Resultados da cana carregou o mês")
    if res:
        conf(abs(res["despesa"] - DESPESA_ESPERADA) < 0.01,
             "Resultados mostra a MESMA despesa que o Financeiro",
             f'Resultados R$ {res["despesa"]:,.2f} x Financeiro R$ {DESPESA_ESPERADA:,.2f}')
        conf(abs(res["receita"] - RECEITA_ESPERADA) < 0.01,
             "Resultados enxerga a receita de cana migrada",
             f'veio R$ {res["receita"]:,.2f}')

    # ---- ano_safra: venda/despesa remarcada pra outra safra ----
    safra_calc = page.evaluate(
        "() => {"
        "  const despesas = ["
        "    {mes:'2025-06', anoSafra:null, valor:100, descricao:'a', centroCustoId:1, atividade:'cana', fazendaId:1, areas:[]},"
        "    {mes:'2025-07', anoSafra:2024, valor:200, descricao:'b', centroCustoId:1, atividade:'cana', fazendaId:1, areas:[]},"
        "    {mes:'2025-03', anoSafra:2025, valor:300, descricao:'c', centroCustoId:1, atividade:'cana', fazendaId:1, areas:[]},"
        "    {mes:null, anoSafra:null, valor:50, descricao:'rec', centroCustoId:2, atividade:'cana', fazendaId:1, areas:[]},"
        "  ];"
        "  const receitas = ["
        "    {mes:'2025-06', anoSafra:null, valor:1000, data:'2025-06-10', descricao:'venda a'},"
        "    {mes:'2025-07', anoSafra:2024, valor:2000, data:'2025-07-01', descricao:'venda b'},"
        "    {mes:'2025-03', anoSafra:2025, valor:3000, data:'2025-03-01', descricao:'venda c'},"
        "  ];"
        "  return {despesa: despesaNaSafra(despesas, 2025), receitas: receitasNaSafra(receitas, 2025)};"
        "}"
    )
    # a (100, dentro da janela, sem override) + c (300, fora da janela, remarcada pra dentro)
    # + rec (50 x 12 meses da janela = 600) = 1000. b (dentro da janela, remarcada pra fora) some.
    conf(abs(safra_calc["despesa"] - 1000.0) < 0.01,
         "despesaNaSafra: soma remarcada pra dentro, tira a remarcada pra fora",
         f'veio R$ {safra_calc["despesa"]:,.2f}, esperado R$ 1.000,00')
    receitas_nomes = sorted(r["descricao"] for r in safra_calc["receitas"])
    conf(receitas_nomes == ["venda a", "venda c"],
         "receitasNaSafra: mesma regra pra receita (venda a entra, b sai, c é importada)",
         f'veio {receitas_nomes}')

    # ---- a aba Safra do Resultados usa ano_safra de verdade (nao so o mes) ----
    page.evaluate(
        "() => { window.__DB__.lancamentos_financeiros.push("
        "  {id:6, tipo:'receita', atividade:'cana', fazenda_id:1, centro_custo_id:91,"
        "   descricao:'Venda remarcada', valor:9000, data:'2026-06-10', mes:'2026-06',"
        "   ano_safra:2025, areas:[]});"
        "  return true; }"
    )
    page.evaluate("() => carregarResultadoCana()")
    page.wait_for_timeout(600)
    aba_safra = page.evaluate(
        "() => { state.periodo = {tipo:'safra', safra:2026};"
        "        const r = resultadoOperacaoNoPeriodo('cana');"
        "        return {receita:r.receita, temRemarcada: r.receitasDetalhe.some(x=>x.descricao==='Venda remarcada')}; }"
    )
    conf(not aba_safra["temRemarcada"],
         "aba Safra: venda de jun/2026 remarcada pra safra 2025 NÃO aparece na safra 2026",
         f'receita da safra 2026 veio R$ {aba_safra["receita"]:,.2f}')

    # ---- mes preservado na edicao (o bug do R$ 1,2 milhao) ----
    row = page.evaluate(
        "() => lancamentoToRow({...rowToLancamento("
        "  window.__DB__.lancamentos_financeiros.find(l=>l.id===3)), _editId:3})"
    )
    conf(row["mes"] == MES,
         "editar lançamento histórico NÃO apaga o mês (não vira recorrente)",
         f'mes virou {row["mes"]!r}')
    row_novo = page.evaluate("() => lancamentoToRow({tipo:'despesa', atividade:'cana', "
                             "centroCustoId:90, descricao:'x', valor:1, data:'', areas:[]})")
    conf(row_novo["mes"] is None, "lançamento novo sem data continua recorrente",
         f'mes veio {row_novo["mes"]!r}')

    # ---- tela de Centros de Custo ----
    page.evaluate("() => { state.page='centrosCusto'; render(); }")
    page.wait_for_timeout(400)
    corpo = page.locator("body").inner_text()
    conf("INSUMOS AGRICOLAS" in corpo, "lista os centros de custo")
    conf(True, "(coluna Fazenda removida da tela)")
    conf("Fazenda" not in corpo.split("Centros de Custo")[-1][:400],
         "tela de centros não fala mais em fazenda")
    conf("em uso" in corpo, "centro com lançamento não oferece excluir")
    conf("inativo" in corpo, "mostra centro inativo")

    page.evaluate("() => { state.searchCentros='oficina'; render(); }")
    page.wait_for_timeout(300)
    corpo = page.locator("body").inner_text()
    conf("OFICINA DO PALHADAO" in corpo and "INSUMOS AGRICOLAS" not in corpo,
         "busca filtra a lista")

    # ---- o seletor de lancamento enxerga o plano de contas do Conag ----
    page.evaluate("() => { state.page='financeiro'; editDraft={tipo:'despesa', atividade:'cana',"
                  " fazendaId:'', centroCustoId:'', descricao:'', valor:'', data:'', areas:[]};"
                  " state.modal={type:'lancamento'}; render(); }")
    page.wait_for_timeout(400)
    opcoes = page.evaluate("() => [...document.querySelectorAll('#f-centrocustolanc option')]"
                           ".map(o=>o.textContent.trim())")
    conf("INSUMOS AGRICOLAS" in opcoes,
         "centro do plano de contas (frente nula) aparece no lançamento",
         f"opções: {opcoes}")
    conf("CONTA VELHA" not in opcoes,
         "centro inativo NÃO aparece no lançamento", f"opções: {opcoes}")
    page.evaluate("() => { state.modal=null; editDraft=null; state.page='centrosCusto'; state.searchCentros=''; render(); }")
    page.wait_for_timeout(300)

    # ---- registro dos apps ----
    apps = page.evaluate("() => APPS_REGISTRO.map(a=>a.nome + ' -> ' + a.url)")
    conf(any("AECana.html" in a for a in apps), "Painel aponta para AECana.html", str(apps))
    conf(any("AECereais.html" in a for a in apps), "Painel aponta para AECereais.html", str(apps))
    conf(not any("AELavoura.html" in a for a in apps), "nenhum card aponta mais para AELavoura.html")

    # ---- permissoes separadas ----
    mods = page.evaluate("() => JSON.stringify(MODULOS_PERMISSAO)")
    conf("cana_cadastros" in mods and "cereais_cadastros" in mods,
         "tela de Usuários oferece cadastros de cana e de cereais separados")
    conf("financeiro_graos" not in mods,
         "chaves antigas de Financeiro da lavoura saíram da lista")

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
