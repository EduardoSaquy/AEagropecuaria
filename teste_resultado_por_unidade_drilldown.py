"""
Duas features novas em Resultados (AEMatriz.html), pedidas pelo Eduardo em
03/09/2026:

  1. Tabela "Resultado por unidade produzida" em Resultados > Operacional --
     uma linha por cultura (Cereais: soja/milho separados) e por categoria
     de venda (Pecuaria: bezerro/abate/venda_viva), nao um numero so pra
     "Cereais"/"Pecuaria" inteira.
  2. Clique numa fatia do donut de Receita (Resultados > Geral) mostra o
     detalhamento: Cana por fazenda, Cereais por cultura, Pecuaria por
     categoria de venda (bezerro/abate/venda viva -- novo campo na venda).
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

MES = "2026-09"

DB = {
    "fazendas": [
        {"id": 1, "nome": "Faz. Palhadao", "estado": "SP", "area_ha": 500, "ativo": True},
        {"id": 2, "nome": "Faz. Palmito", "estado": "SP", "area_ha": 300, "ativo": True},
    ],
    "fazenda_atividades": [
        {"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 100},
        {"id": 2, "fazenda_id": 1, "atividade": "graos", "area_ha": 200},
        {"id": 3, "fazenda_id": 1, "atividade": "pecuaria", "area_ha": 150},
    ],
    "culturas": [
        {"id": 1, "nome": "Soja", "frente": "graos", "ativo": True},
        {"id": 2, "nome": "Milho", "frente": "graos", "ativo": True},
        {"id": 3, "nome": "Cana-de-acucar", "frente": "cana", "ativo": True},
    ],
    "talhoes_areas": [
        {"id": 1, "fazenda_id": 1, "nome": "T-Cana-1", "tipo": "talhao", "area_ha": 40, "cultura_id": 3, "ativo": True},
        {"id": 2, "fazenda_id": 1, "nome": "T-Soja-1", "tipo": "talhao", "area_ha": 60, "cultura_id": 1, "ativo": True},
        {"id": 3, "fazenda_id": 1, "nome": "T-Milho-1", "tipo": "talhao", "area_ha": 50, "cultura_id": 2, "ativo": True},
    ],
    "centros_custo": [
        {"id": 90, "fazenda_id": None, "nome": "DESPESA GERAL", "frente": None, "ativo": True,
         "tipo": "saida", "subcategoria": "OPERACIONAL | X"},
        {"id": 92, "fazenda_id": None, "nome": "VENDAS", "frente": None, "ativo": True,
         "tipo": "entrada", "subcategoria": "ATIVIDADES OPERACIONAIS"},
    ],
    "lancamentos_financeiros": [
        # ---- Cana: despesa + receita em 2 fazendas (drill-down por fazenda) ----
        {"id": 1, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Adubo cana", "valor": 6000.00, "data": f"{MES}-05", "mes": MES, "areas": []},
        {"id": 2, "tipo": "receita", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda cana Palhadao", "valor": 9000.00, "data": f"{MES}-15", "mes": MES, "areas": []},
        {"id": 3, "tipo": "receita", "atividade": "cana", "fazenda_id": 2, "centro_custo_id": 92,
         "descricao": "Venda cana Palmito", "valor": 3000.00, "data": f"{MES}-16", "mes": MES, "areas": []},
        # ---- Cereais: soja e milho separados (drill-down por cultura) ----
        {"id": 4, "tipo": "despesa", "atividade": "graos", "fazenda_id": 1, "centro_custo_id": 90,
         "cultura_id": 1, "descricao": "Semente soja", "valor": 4000.00, "data": f"{MES}-03", "mes": MES, "areas": []},
        {"id": 5, "tipo": "receita", "atividade": "graos", "fazenda_id": 1, "centro_custo_id": 92,
         "cultura_id": 1, "descricao": "Venda soja", "valor": 7000.00, "data": f"{MES}-20", "mes": MES, "areas": []},
        {"id": 6, "tipo": "despesa", "atividade": "graos", "fazenda_id": 1, "centro_custo_id": 90,
         "cultura_id": 2, "descricao": "Semente milho", "valor": 3000.00, "data": f"{MES}-03", "mes": MES, "areas": []},
        {"id": 7, "tipo": "receita", "atividade": "graos", "fazenda_id": 1, "centro_custo_id": 92,
         "cultura_id": 2, "descricao": "Venda milho", "valor": 4500.00, "data": f"{MES}-22", "mes": MES, "areas": []},
        # ---- Pecuaria: despesa geral + receita ligada ao abate (categoria) ----
        {"id": 8, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Racao", "valor": 5000.00, "data": f"{MES}-02", "mes": MES, "areas": []},
        {"id": 9, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda de abate", "valor": 12000.00, "data": f"{MES}-10", "mes": MES, "areas": [],
         "abate_id": 501},
    ],
    "colheitas_cana": [
        {"id": 1, "talhao_id": 1, "safra_id": None, "data": f"{MES}-18", "corte": 1, "toneladas": 3600.00, "observacao": ""},
    ],
    "colheitas_graos": [
        {"id": 1, "talhao_id": 2, "cultura_id": 1, "safra_id": None, "data": f"{MES}-19", "sacas": 700.00, "observacao": ""},
        {"id": 2, "talhao_id": 3, "cultura_id": 2, "safra_id": None, "data": f"{MES}-21", "sacas": 900.00, "observacao": ""},
    ],
    "abates": [
        {"id": 501, "data": f"{MES}-10", "lote_id": None, "quantidade": 20, "tipo_venda": "arroba",
         "peso_medio_kg": 270, "categoria": "abate", "sexo": "macho", "observacao": ""},
    ],
    "lotes": [], "funcionarios": [], "funcionario_atividades": [],
    "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEMatriz.html"))
    page.wait_for_timeout(1800)

    print("\n  RESULTADO POR UNIDADE + DRILL-DOWN DA ROSQUINHA")
    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2026-09'}; }")

    # ---- 1. tabela por unidade ----
    linhas = page.evaluate("() => linhasResultadoPorUnidade(state.periodo)")
    nomes = sorted(l["nome"] for l in linhas)
    conf(nomes == sorted(["Cana", "Soja", "Milho", "Abate"]),
         "uma linha por Cana + Soja + Milho + Abate (categoria), nao 'Cereais'/'Pecuaria' genericos",
         str(nomes))

    cana = next((l for l in linhas if l["nome"]=="Cana"), None)
    conf(cana is not None, "achou a linha da Cana")
    if cana:
        conf(cana["produzido"] == 3600, "Cana produzido = 3600t (soma das colheitas do periodo)", str(cana))
        conf(abs(cana["custo"] - 6000/3600) < 0.01, "Cana custo/t = despesa/toneladas", str(cana))
        conf(abs(cana["receita"] - 12000/3600) < 0.01, "Cana receita/t = (9000+3000 das 2 fazendas)/toneladas", str(cana))

    soja = next((l for l in linhas if l["nome"]=="Soja"), None)
    conf(soja is not None, "achou a linha da Soja (separada do Milho)")
    if soja:
        conf(soja["produzido"] == 700, "Soja produzido = 700sc", str(soja))
        conf(abs(soja["custo"] - 4000/700) < 0.01, "Soja custo/sc so conta a despesa da propria cultura (4000, nao 7000)", str(soja))
        conf(abs(soja["receita"] - 7000/700) < 0.01, "Soja receita/sc so conta a receita dela", str(soja))

    milho = next((l for l in linhas if l["nome"]=="Milho"), None)
    conf(milho is not None, "achou a linha do Milho (separada da Soja)")
    if milho:
        conf(milho["produzido"] == 900, "Milho produzido = 900sc", str(milho))
        conf(abs(milho["custo"] - 3000/900) < 0.01, "Milho custo/sc so conta a despesa dele (3000, nao 4000 da soja)", str(milho))

    abate = next((l for l in linhas if l["nome"]=="Abate"), None)
    conf(abate is not None, "achou a linha 'Abate' (categoria da venda, nao 'Pecuaria' generico)")
    if abate:
        arrobas_esperadas = (270/15)*20  # peso carcaca / 15 * qtd
        conf(abs(abate["produzido"] - arrobas_esperadas) < 0.01, f"Abate produzido = {arrobas_esperadas}@ (peso carcaca/15 x 20 animais)", str(abate))
        conf(abs(abate["receita"] - 12000/arrobas_esperadas) < 0.01, "Abate receita/@ vem do lancamento ligado ao abate_id", str(abate))

    # ---- 2. drill-down da receita ----
    porFazenda = page.evaluate("() => receitaDetalheAgrupado('cana', state.periodo)")
    porFazendaMap = {x["label"]: x["valor"] for x in porFazenda}
    conf(porFazendaMap.get("Faz. Palhadao") == 9000 and porFazendaMap.get("Faz. Palmito") == 3000,
         "Cana: receita por fazenda (Palhadao 9000, Palmito 3000)", str(porFazendaMap))

    porCultura = page.evaluate("() => receitaDetalheAgrupado('cereais', state.periodo)")
    porCulturaMap = {x["label"]: x["valor"] for x in porCultura}
    conf(porCulturaMap.get("Soja") == 7000 and porCulturaMap.get("Milho") == 4500,
         "Cereais: receita por cultura (Soja 7000, Milho 4500)", str(porCulturaMap))

    porCategoria = page.evaluate("() => receitaDetalheAgrupado('pecuaria', state.periodo)")
    porCategoriaMap = {x["label"]: x["valor"] for x in porCategoria}
    conf(porCategoriaMap.get("Abate") == 12000,
         "Pecuaria: receita por categoria de venda (Abate 12000, via abate_id)", str(porCategoriaMap))

    # ---- 2b. comparativo de safra dentro de cada quadrado ----
    safras = page.evaluate("() => safrasRecentes(3)")
    conf(safras == [2024, 2025, 2026], "safrasRecentes(3) traz as 3 ultimas, a atual (2026) por ultimo", str(safras))

    page.evaluate("""() => {
      state.page = 'resultados'; state.subAbaResultados = 'operacional';
      render();
    }""")
    page.wait_for_timeout(300)
    pagina_html = page.evaluate("() => document.querySelector('.donuts-row:last-of-type')?.innerHTML || document.body.innerHTML")
    conf("Lucro/t" in pagina_html or "por safra" in pagina_html,
         "cada quadrado mostra 'Lucro/... por safra'")

    # ---- 2c. margem (%) ao lado do Lucro do periodo + tabela por safra com Producao ----
    # Pedido do Eduardo em 03/09/2026: % pequena do lucro so no card do
    # periodo atual (nao repetir em cada linha da tabela de safras, polui).
    canaCardHtml = page.evaluate("""() => {
      const cards = document.querySelectorAll('.donuts-row-larga > .card');
      return cards[0] ? cards[0].innerHTML : '';
    }""")
    # Cana: sobra/t = (12000-6000)/3600, receita/t = 12000/3600 -> margem = 6000/12000 = 50%
    conf("50,0%" in canaCardHtml, "card da Cana mostra a margem (50,0%) ao lado do Lucro do periodo", canaCardHtml[:400])
    conf("Produção" in canaCardHtml, "tabela de safras tem coluna Produção", canaCardHtml[:400])
    linhasTabelaSafra = page.evaluate("""() => {
      const cards = document.querySelectorAll('.donuts-row-larga > .card');
      const tbody = cards[0]?.querySelector('table tbody');
      return tbody ? [...tbody.querySelectorAll('tr')].map(tr=>tr.innerHTML) : [];
    }""")
    conf(len(linhasTabelaSafra)==3 and all('%' not in tr for tr in linhasTabelaSafra),
         "linhas da tabela de safras NAO repetem a porcentagem (so o card do topo tem)", str(linhasTabelaSafra))

    # safra 2026 (maio/2026-abril/2027) cobre setembro/2026, onde esta toda
    # a producao do fixture -- a sobra da Cana nessa safra tem que bater com
    # a do periodo do mes (mesmos dados, mesma janela).
    linhasSafraAtual = page.evaluate("() => linhasResultadoPorUnidade({tipo:'safra', safra:2026})")
    canaSafra = next((l for l in linhasSafraAtual if l["nome"]=="Cana"), None)
    conf(canaSafra is not None and abs((canaSafra["receita"]-canaSafra["custo"]) - (cana["receita"]-cana["custo"])) < 0.01,
         "safra 2026 (atual) da Cana bate com o periodo do mes -- mesma janela, mesmos dados",
         str(canaSafra))

    # safra 2024 nao tem dado nenhum no fixture -- sobra tem que vir null,
    # nao quebrar dividindo por zero.
    linhasSafra2024 = page.evaluate("() => linhasResultadoPorUnidade({tipo:'safra', safra:2024})")
    conf(linhasSafra2024 == [], "safra 2024 (sem nenhum dado) nao gera linha nenhuma", str(linhasSafra2024))

    # ---- 3. o modal de detalhe da receita mostra o agrupamento ----
    page.evaluate("""() => {
      state.modal = {type:'detalheOperacao', panelId:'donut-receita', slug:'cereais'};
      render();
    }""")
    page.wait_for_timeout(300)
    corpo_html = page.evaluate("() => document.querySelector('.modal-body')?.innerHTML || ''")
    conf("Soja" in corpo_html and "Milho" in corpo_html and "Por cultura" in corpo_html,
         "modal de detalhe (receita de Cereais) mostra 'Por cultura' com Soja e Milho")

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
