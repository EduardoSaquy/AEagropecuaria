"""
AE Combustivel: custo por hora (ou km) de cada equipamento (07/11/2026). Rateio > Por Equipamento passou a mostrar horas/km,
combustivel, manutencao (com o custo preenchido na aba Manutencao), custo total e R$ por hora/km. Contas feitas a mao:
  Trator A (horimetro): 300 L em 3 abastecimentos de outubro, leituras 1000 a 1030 -> 30 h, consumo 10 L/h; combustivel a R$ 6,00/L =
    R$ 1.800; manutencao de outubro R$ 600 (a de agosto, R$ 400, e de outro periodo); total R$ 2.400; R$ 80,00 por hora.
  Caminhao B (hodometro): 500 L, leituras 5000 a 5500 -> 500 km; R$ 3.000; sem manutencao com custo; R$ 6,00 por km.
  Gerador (sem medidor): 50 L, R$ 300; sem horas -> sem custo por hora.
  Colhedora C: sem abastecimento no periodo e manutencao de R$ 1.500 -> aparece so com a manutencao.
  Pecas e servicos do Financeiro (despesas ligadas a um equipamento, lancamentos_equipamento_01.sql): Trator A R$ 250 (pneu) + R$ 100
    (so com o mes, conta no dia 1) = R$ 350 e custo total R$ 2.750 (R$ 91,67 por hora); a de agosto, a receita e o gasto sem maquina nao
    entram; Moto D so com uma correia de R$ 120 aparece; consulta que falha deixa a coluna vazia sem erro.
Prova tambem:
  - o abastecimento de setembro (fora do periodo) nao entra; o total da tabela soma combustivel e manutencao;
  - o campo de custo da manutencao e opcional e so vai ao banco quando tem valor (o app segue funcionando antes do SQL
    combustivel_manutencao_02_custo.sql); limpar um custo que ja existia manda null; erro de coluna faltando vira instrucao;
  - o historico de manutencao mostra o custo; a tela nao rola de lado em 1280 e 390 px.
"""
import json
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {}}


def ab(id_, equip, dia, litros, leitura):
    return {"id": id_, "fazenda_id": 1, "client_uuid": f"00000000-0000-4000-8000-{id_:012d}", "tanque_id": 1, "equipamento_id": equip, "operador_id": 1,
            "data_hora": f"{dia}T15:00:00Z", "volume_litros": litros, "leitura_medidor": leitura, "talhao_area_id": None, "centro_custo_id": 1, "operacao_id": None}


DB = {
    "fazendas": [{"id": 1, "nome": "Mata Verde", "estado": "GO", "area_ha": 100, "ativo": True}],
    "tanques": [{"id": 1, "fazenda_id": 1, "nome": "Tanque 1", "produto_id": 1, "capacidade_litros": 10000, "tipo": "fixo", "ativo": True}],
    "entradas_estoque": [{"id": 1, "tanque_id": 1, "fornecedor_id": 1, "data": "2026-09-01", "volume_litros": 10000, "valor_total": 60000}],     # R$ 6,00/L
    "equipamentos": [
        {"id": 1, "fazenda_id": 1, "nome": "Trator A", "tipo": "trator", "tipo_medidor": "horimetro", "frente_principal": "cana", "ativo": True},
        {"id": 2, "fazenda_id": 1, "nome": "Caminhao B", "tipo": "caminhao_canavieiro", "tipo_medidor": "hodometro", "frente_principal": "cana", "ativo": True},
        {"id": 3, "fazenda_id": 1, "nome": "Gerador", "tipo": "gerador", "tipo_medidor": "nenhum", "frente_principal": "geral", "ativo": True},
        {"id": 4, "fazenda_id": 1, "nome": "Colhedora C", "tipo": "colhedora_cana", "tipo_medidor": "horimetro", "frente_principal": "cana", "ativo": True},
        {"id": 5, "fazenda_id": 1, "nome": "Moto D", "tipo": "moto", "tipo_medidor": "hodometro", "frente_principal": "geral", "ativo": True},
    ],
    "abastecimentos": [
        ab(1, 1, "2026-10-05", 100, 1000), ab(2, 1, "2026-10-12", 120, 1015), ab(3, 1, "2026-10-20", 80, 1030),
        ab(4, 1, "2026-09-10", 1000, 900),                      # setembro: fora do periodo
        ab(5, 2, "2026-10-06", 200, 5000), ab(6, 2, "2026-10-25", 300, 5500),
        ab(7, 3, "2026-10-07", 50, None),
    ],
    "manutencoes": [
        {"id": 1, "fazenda_id": 1, "equipamento_id": 1, "tipo": "troca_oleo", "data": "2026-10-15", "leitura": 1015, "intervalo": 250, "custo": 600},
        {"id": 2, "fazenda_id": 1, "equipamento_id": 1, "tipo": "troca_filtro", "data": "2026-08-01", "leitura": 800, "intervalo": 500, "custo": 400},
        {"id": 3, "fazenda_id": 1, "equipamento_id": 4, "tipo": "troca_oleo", "data": "2026-10-20", "leitura": 50, "intervalo": 250, "custo": 1500},
        {"id": 4, "fazenda_id": 1, "equipamento_id": 5, "tipo": "troca_oleo", "data": "2026-10-21", "leitura": 10, "intervalo": 250},          # sem custo
    ],
    # despesas do Financeiro ligadas a um equipamento (lancamentos_equipamento_01.sql): pecas e servicos
    "lancamentos_financeiros": [
        {"id": 1, "tipo": "despesa", "atividade": "cana", "centro_custo_id": 1, "descricao": "Pneu", "valor": 250, "data": "2026-10-18", "mes": "2026-10", "equipamento_id": 1},
        {"id": 2, "tipo": "despesa", "atividade": "cana", "centro_custo_id": 1, "descricao": "Servico de solda (so competencia)", "valor": 100, "data": None, "mes": "2026-10", "equipamento_id": 1},
        {"id": 3, "tipo": "despesa", "atividade": "cana", "centro_custo_id": 1, "descricao": "Pneu de agosto", "valor": 900, "data": "2026-08-10", "mes": "2026-08", "equipamento_id": 1},
        {"id": 4, "tipo": "receita", "atividade": "cana", "centro_custo_id": 1, "descricao": "Nao e despesa", "valor": 5000, "data": "2026-10-10", "mes": "2026-10", "equipamento_id": 1},
        {"id": 5, "tipo": "despesa", "atividade": "geral", "centro_custo_id": 1, "descricao": "Correia da moto", "valor": 120, "data": "2026-10-22", "mes": "2026-10", "equipamento_id": 5},
        {"id": 6, "tipo": "despesa", "atividade": "cana", "centro_custo_id": 1, "descricao": "Sem maquina", "valor": 7777, "data": "2026-10-10", "mes": "2026-10", "equipamento_id": None},
    ],
    "produtos": [{"id": 1, "nome": "Diesel S10", "unidade": "L", "ativo": True}], "fornecedores": [{"id": 1, "nome": "Posto", "ativo": True}],
    "operadores": [], "profiles": [ADMIN],
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
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(DB)}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AECombustivel.html"))
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.equipamentos.length > 0 && state.abastecimentos.length > 0", timeout=30000)
    page.wait_for_function("() => state.pecasEquipamento.length > 0", timeout=30000)
    page.wait_for_timeout(400)
    return page


def linhas(page):
    return page.evaluate("""() => Object.fromEntries([...document.querySelectorAll('[data-equipamento-linha]')].map(tr =>
        [tr.children[0].querySelector('strong').innerText.trim(), [...tr.children].slice(1).map(td => td.innerText.replace(/\\s+/g, ' ').trim())]))""")


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = abre(browser)
    page.evaluate("() => { state.rateioFiltro = {dataInicio: '2026-10-01', dataFim: '2026-10-31'}; state.page = 'rateioEquipamento'; render(); }")
    page.wait_for_timeout(300)

    print("== custo por hora / km por equipamento (outubro/2026)")
    L = linhas(page)
    # colunas apos o nome: R$ por hora/km, Custo total, Combustivel, Manutencao, Pecas e servicos, Horas/km, Consumo, Volume
    trator = L.get("Trator A")
    conf(trator and trator[7] == "300 L" and trator[6].startswith("10,00 L/h") and trator[5].startswith("30,0 h"),
         "Trator A: 300 L, 10 L/h e 30 h", str(trator))
    conf(trator and trator[2] == "1.800,00" and trator[3] == "600,00" and trator[4] == "350,00" and trator[1] == "2.750,00", "Trator A: combustivel R$ 1.800 + manutencao R$ 600 + pecas R$ 350 (pneu 250 + solda 100 so com o mes; agosto, receita e gasto sem maquina ficam de fora) = R$ 2.750", str(trator))
    conf(trator and trator[0].startswith("R$ 91,67 /h"), "Trator A: R$ 91,67 por hora (2.750 / 30 h)", str(trator))
    cam = L.get("Caminhao B")
    conf(cam and cam[6].startswith("1,00 L/km") and cam[5].startswith("500,0 km") and cam[2] == "3.000,00" and cam[3] == "—" and cam[4] == "—" and cam[0].startswith("R$ 6,00 /km"),
         "Caminhao B: 500 km, R$ 3.000, sem manutencao, R$ 6,00 por km", str(cam))
    ger = L.get("Gerador")
    conf(ger and ger[2] == "300,00" and ger[5] == "—" and ger[0] == "—", "Gerador (sem medidor): custo do combustivel e sem custo por hora", str(ger))
    col = L.get("Colhedora C")
    conf(col and col[7] == "0 L" and col[2] == "0,00" and col[3] == "1.500,00" and col[4] == "—" and col[1] == "1.500,00" and col[0] == "—",
         "Colhedora C: sem abastecimento mas com manutencao R$ 1.500 aparece", str(col))
    moto = L.get("Moto D")
    conf(moto and moto[2] == "0,00" and moto[3] == "—" and moto[4] == "120,00" and moto[1] == "120,00", "Moto D: a manutencao sem custo nao conta, e a correia de R$ 120 do Financeiro aparece", str(moto))
    ordem = page.evaluate("() => [...document.querySelectorAll('[data-equipamento-linha] td:first-child strong')].map(e => e.innerText.trim())")
    conf(ordem == ["Caminhao B", "Trator A", "Colhedora C", "Gerador", "Moto D"], "ordenado pelo custo total (maior primeiro)", str(ordem))
    total = page.evaluate("() => [...document.querySelector('[data-rateio-equipamento] tbody tr:last-child').children].map(td => td.innerText.replace(/\\s+/g, ' ').trim())")
    conf(total[3] == "5.100,00" and total[4] == "2.100,00" and total[5] == "470,00" and total[2] == "7.670,00", "total: combustivel R$ 5.100 + manutencao R$ 2.100 + pecas R$ 470 = R$ 7.670", str(total))
    conf("Custo por hora (ou km)" in page.inner_text("body") and "Não inclui depreciação" in page.inner_text("body"), "a tela explica a conta e o que nao entra")
    page.evaluate("() => { state.rateioFiltro = {dataInicio: '2026-09-01', dataFim: '2026-09-30'}; render(); }")
    page.wait_for_timeout(200)
    L = linhas(page)
    conf(list(L.keys()) == ["Trator A"] and L["Trator A"][7] == "1.000 L" and L["Trator A"][5] == "—", "em setembro so o abastecimento de setembro (1 leitura: sem horas)", str(L))

    print("== sem acesso ao Financeiro ou antes do SQL: a coluna fica vazia, sem erro")
    page.evaluate("""() => { state.rateioFiltro = {dataInicio: '2026-10-01', dataFim: '2026-10-31'}; state.page = 'rateioEquipamento';
        const orig = db.from.bind(db);
        db.from = (t) => { if (t === 'lancamentos_financeiros') { const q = { select(){return q;}, in(){return q;}, order(){return q;},
            range(){ return Promise.resolve({data: null, error: {code: '42703', message: 'column lancamentos_financeiros.equipamento_id does not exist'}}); } }; return q; }
            return orig(t); }; }""")
    page.evaluate("async () => { await carregarPecasEquipamento(); render(); }")
    page.wait_for_timeout(300)
    L = linhas(page)
    conf(page.evaluate("() => state.pecasEquipamento.length") == 0 and L["Trator A"][4] == "—" and L["Trator A"][1] == "2.400,00",
         "consulta que falha: pecas e servicos ficam vazias e o resto da conta segue (R$ 2.400)", str(L.get("Trator A")))
    print("== custo da manutencao e opcional e so vai ao banco quando tem valor")
    page.evaluate("() => { state.page = 'manutencoes'; render(); }")
    page.wait_for_timeout(200)
    corpo = page.inner_text("body")
    conf("CUSTO" in corpo.upper() and "R$ 600,00" in corpo and "R$ 400,00" in corpo, "o historico de manutencao mostra o custo")

    def salva(abrir, preencher):
        page.evaluate("() => { window.__ESCRITAS__.length = 0; }")
        page.evaluate(abrir)
        page.wait_for_timeout(200)
        page.evaluate(preencher)
        page.click("[data-save-cadastro]")
        page.wait_for_timeout(500)
        return page.evaluate("() => window.__ESCRITAS__.filter(e => e.tabela === 'manutencoes')")

    campos = "() => { const s = (id, v) => { document.getElementById(id).value = v; }; s('f-fazendaId', '1'); s('f-equipamentoId', '1'); s('f-tipo', 'troca_oleo'); s('f-data', '2026-11-01'); s('f-leitura', '1100'); s('f-intervalo', '250'); %s }"
    w = salva("() => abrirNovoCadastro('manutencoes'); render();".replace("() => ", "() => { ", 1).replace("render();", "render(); }"), campos % "")
    conf(len(w) == 1 and w[0]["op"] == "insert" and "custo" not in w[0]["v"], "nova manutencao SEM custo: a coluna nem e enviada (funciona antes do SQL)", str(w))
    w = salva("() => { abrirNovoCadastro('manutencoes'); render(); }", campos % "s('f-custo', '350.5');")
    conf(len(w) == 1 and w[0]["v"].get("custo") == 350.5, "nova manutencao COM custo: envia o valor", str(w))
    w = salva("() => { abrirEditarCadastro('manutencoes', 1); render(); }", "() => { document.getElementById('f-custo').value = ''; }")
    conf(len(w) == 1 and w[0]["op"] == "update" and w[0]["v"].get("custo", 'AUSENTE') is None, "limpar um custo que ja existia manda null", str(w))
    w = salva("() => { abrirEditarCadastro('manutencoes', 4); render(); }", "() => { document.getElementById('f-observacao').value = 'so uma observacao'; }")
    conf(len(w) == 1 and w[0]["op"] == "update" and "custo" not in w[0]["v"], "editar uma manutencao que nunca teve custo nao manda a coluna", str(w))
    msg = page.evaluate("() => mensagemErroSupabase({message: \"Could not find the 'custo' column of 'manutencoes' in the schema cache\"})")
    conf("combustivel_manutencao_02_custo.sql" in msg, "coluna faltando no banco vira instrucao com o nome do arquivo", msg)
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    page.context.close()

    print("== sem rolar de lado")
    for w_ in (1280, 390):
        page = abre(browser, w_, 900)
        page.evaluate("() => { state.rateioFiltro = {dataInicio: '2026-10-01', dataFim: '2026-10-31'}; state.page = 'rateioEquipamento'; render(); }")
        page.wait_for_timeout(300)
        lat = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(lat <= 1, f"{w_} px: a pagina nao rola de lado ({lat} px)")
        page.context.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
