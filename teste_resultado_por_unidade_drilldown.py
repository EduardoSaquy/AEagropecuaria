"""
Duas features novas em Resultados (AEMatriz.html), pedidas pelo Eduardo em
03/09/2026:

  1. Tabela "Resultado por unidade produzida" em Resultados > Operacional --
     uma linha por cultura (Cereais: soja/milho separados), nao um numero so
     pra "Cereais" inteiro. A Pecuaria aparece como ATIVIDADE TODA (card
     proprio, resumoPecuariaNoPeriodo): o custo e do rebanho inteiro e nao
     e dividido entre bezerro e frigorifico -- dividir a despesa total pelas
     @ de uma categoria so mostrava -400% de lucro/@ num ano de +24% de
     margem (bug relatado pelo Eduardo em 14/10/2026). Venda por cabeca (sem
     peso) entra em cabecas.
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
        # ---- safra 2025 (maio/2025-abril/2026) -- valores DIFERENTES do
        # periodo corrente (setembro/2026), pra pegar o bug de 03/09/2026:
        # o comparativo por safra usava resultadoOperacaoNoPeriodo(slug) sem
        # passar a safra pedida, entao Cana e Pecuaria sempre traziam a
        # despesa/receita do FILTRO GLOBAL da tela, nao da safra da linha.
        {"id": 10, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Adubo cana 25", "valor": 3000.00, "data": "2025-08-05", "mes": "2025-08", "areas": []},
        {"id": 11, "tipo": "receita", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda cana 25", "valor": 5000.00, "data": "2025-09-15", "mes": "2025-09", "areas": []},
        {"id": 12, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Racao 25", "valor": 2000.00, "data": "2025-08-02", "mes": "2025-08", "areas": []},
        {"id": 13, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda de abate 25", "valor": 6600.00, "data": "2025-09-10", "mes": "2025-09", "areas": [],
         "abate_id": 502},
        # ---- Pecuaria, agosto/2026: bezerros vendidos POR CABECA (sem peso).
        # Toda a receita do mes tem venda registrada -> custo/receita por
        # cabeca aparecem. A atividade lucra (270000 - 100000).
        {"id": 14, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Racao ago", "valor": 100000.00, "data": "2026-08-02", "mes": "2026-08", "areas": []},
        {"id": 15, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda de bezerros por cabeca", "valor": 270000.00, "data": "2026-08-12", "mes": "2026-08",
         "areas": [], "abate_id": 503},
        # ---- Pecuaria, julho/2026: so 10 de 68.000 de receita tem animais
        # registrados (venda de gado antiga sem registro + excedente de milho
        # revendido) -> cobertura baixa, nada de custo por cabeca.
        {"id": 16, "tipo": "despesa", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Racao jul", "valor": 20000.00, "data": "2026-07-02", "mes": "2026-07", "areas": []},
        {"id": 17, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda de bezerros por kg", "valor": 10000.00, "data": "2026-07-10", "mes": "2026-07",
         "areas": [], "abate_id": 504},
        {"id": 18, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda de gado - 50 bois (frigorifico)", "valor": 50000.00, "data": "2026-07-20",
         "mes": "2026-07", "areas": []},
        {"id": 19, "tipo": "receita", "atividade": "pecuaria", "fazenda_id": 1, "centro_custo_id": 92,
         "descricao": "Venda de milho - excedente da pecuaria", "valor": 8000.00, "data": "2026-07-25",
         "mes": "2026-07", "areas": []},
    ],
    "colheitas_cana": [
        {"id": 1, "talhao_id": 1, "safra_id": None, "data": f"{MES}-18", "corte": 1, "toneladas": 3600.00, "observacao": ""},
        {"id": 2, "talhao_id": 1, "safra_id": None, "data": "2025-09-18", "corte": 1, "toneladas": 2000.00, "observacao": ""},
    ],
    "colheitas_graos": [
        {"id": 1, "talhao_id": 2, "cultura_id": 1, "safra_id": None, "data": f"{MES}-19", "sacas": 700.00, "observacao": ""},
        {"id": 2, "talhao_id": 3, "cultura_id": 2, "safra_id": None, "data": f"{MES}-21", "sacas": 900.00, "observacao": ""},
    ],
    "abates": [
        {"id": 501, "data": f"{MES}-10", "lote_id": None, "quantidade": 20, "tipo_venda": "arroba",
         "peso_medio_kg": 270, "categoria": "abate", "sexo": "macho", "observacao": ""},
        {"id": 502, "data": "2025-09-10", "lote_id": None, "quantidade": 10, "tipo_venda": "arroba",
         "peso_medio_kg": 270, "categoria": "abate", "sexo": "macho", "observacao": ""},
        # venda por cabeca: valor fechado por animal, SEM peso registrado
        {"id": 503, "data": "2026-08-12", "lote_id": None, "quantidade": 90, "tipo_venda": "cabeca",
         "peso_medio_kg": None, "categoria": "bezerro", "sexo": "macho", "observacao": ""},
        # venda por kg de peso vivo: 10 animais x 200 kg / 30 = 66,67 @
        {"id": 504, "data": "2026-07-10", "lote_id": None, "quantidade": 10, "tipo_venda": "kg",
         "peso_medio_kg": 200, "categoria": "bezerro", "sexo": "macho", "observacao": ""},
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
    conf(nomes == sorted(["Cana", "Soja", "Milho"]),
         "uma linha por Cana + Soja + Milho; Pecuaria NAO gera linha por categoria (nao 'Cereais' generico)",
         str(nomes))
    conf("Abate" not in nomes and "Venda de bezerro" not in nomes,
         "o custo da Pecuaria inteira nao e cobrado de cada categoria de venda (bug dos -400%)",
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

    # ---- 1b. Pecuaria como atividade toda (setembro/2026: um abate, 20 animais) ----
    pec = page.evaluate("() => resumoPecuariaNoPeriodo(state.periodo)")
    conf(pec is not None, "resumoPecuariaNoPeriodo devolve o resumo da atividade")
    if pec:
        arrobas_esperadas = (270/15)*20  # peso carcaca / 15 * qtd
        conf(pec["cabecas"] == 20 and abs(pec["arrobas"] - arrobas_esperadas) < 0.01,
             f"Pecuaria vendeu 20 cab = {arrobas_esperadas}@ (peso carcaca/15 x 20 animais)", str(pec))
        conf(pec["despesa"] == 5000 and pec["receita"] == 12000 and pec["resultado"] == 7000,
             "Pecuaria: custo 5000, receita 12000, resultado 7000 -- a atividade toda, sem dividir", str(pec))
        conf(abs(pec["margem"] - 7000/12000*100) < 0.01,
             "Pecuaria: margem = resultado / receita (a mesma do card de cima)", str(pec["margem"]))
        conf(pec["porCabecaOk"] and abs(pec["custoPorCabeca"] - 250) < 0.01 and abs(pec["receitaPorCabeca"] - 600) < 0.01,
             "Pecuaria: toda a receita tem venda registrada -> custo/cab 250 e receita/cab 600", str(pec))
        cat = pec["categorias"][0] if pec["categorias"] else {}
        conf(len(pec["categorias"]) == 1 and cat.get("nome") == "Abate" and cat.get("cabecas") == 20
             and abs(cat.get("receitaPorArroba", 0) - 12000/arrobas_esperadas) < 0.01 and "custo" not in cat,
             "categoria Abate traz cabecas, @ e receita (R$/@ do lancamento ligado ao abate_id) e NENHUM custo", str(cat))

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

    # ---- 2d. regressao do bug relatado pelo Eduardo em 03/09/2026: "quando
    # eu mudo o ano esta alterando os valores" -- resultadoOperacaoNoPeriodo
    # era chamado sem o periodo, entao Cana/Pecuaria no comparativo por
    # safra sempre traziam a despesa/receita do FILTRO GLOBAL da tela
    # (state.periodo), nao da safra de cada linha. safra 2025 tem despesa/
    # receita propria e diferente da do periodo corrente (setembro/2026) --
    # tem que bater com os dados DELA, e nao mudar quando o filtro global
    # muda de ano.
    linhasSafra2025_a = page.evaluate("() => linhasResultadoPorUnidade({tipo:'safra', safra:2025})")
    cana2025_a = next((l for l in linhasSafra2025_a if l["nome"]=="Cana"), None)
    pec2025_a = page.evaluate("() => resumoPecuariaNoPeriodo({tipo:'safra', safra:2025})")
    conf(cana2025_a is not None and abs(cana2025_a["custo"] - 3000/2000) < 0.01 and abs(cana2025_a["receita"] - 5000/2000) < 0.01,
         "safra 2025 da Cana usa a despesa/receita PROPRIA dela (3000/5000), nao a do periodo corrente (6000/12000)",
         str(cana2025_a))
    conf(pec2025_a is not None and pec2025_a["despesa"] == 2000 and pec2025_a["receita"] == 6600 and pec2025_a["cabecas"] == 10,
         "safra 2025 da Pecuaria usa a despesa/receita/cabecas PROPRIAS dela (2000/6600/10), nao as do periodo corrente",
         str(pec2025_a))

    # muda o filtro global (o "ano" que o Eduardo troca na tela) e pede a
    # MESMA safra 2025 de novo -- tem que dar exatamente o mesmo resultado.
    page.evaluate("() => { state.periodo = {tipo:'ano', ano:2024}; }")
    linhasSafra2025_b = page.evaluate("() => linhasResultadoPorUnidade({tipo:'safra', safra:2025})")
    cana2025_b = next((l for l in linhasSafra2025_b if l["nome"]=="Cana"), None)
    conf(cana2025_b is not None and abs(cana2025_b["custo"] - cana2025_a["custo"]) < 0.01 and abs(cana2025_b["receita"] - cana2025_a["receita"]) < 0.01,
         "safra 2025 da Cana NAO muda quando o filtro global (ano/mes/safra da tela) muda",
         f"antes={cana2025_a}  depois de mudar o filtro global={cana2025_b}")
    page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2026-09'}; }")  # devolve o filtro global

    # ---- 2e. Pecuaria: venda POR CABECA (sem peso) entra por unidade ----
    # Relato do Eduardo em 14/10/2026: 90 bezerros vendidos por cabeca nao
    # entravam (sem peso) e a receita deles inflava o R$/@ das outras; o custo
    # da atividade toda era dividido so pelas @ de uma categoria e dava
    # prejuizo de -400% numa atividade com lucro.
    ago = page.evaluate("() => resumoPecuariaNoPeriodo({tipo:'mes', mes:'2026-08'})")
    conf(ago["cabecas"] == 90 and ago["cabecasSemPeso"] == 90 and ago["vendasSemPeso"] == 1 and ago["arrobas"] == 0,
         "venda por cabeca (90 animais, sem peso) ENTRA nas cabecas vendidas; nao entra em @", str(ago))
    conf(ago["resultado"] == 170000 and ago["receita"] == 270000 and ago["despesa"] == 100000,
         "agosto: a atividade lucra (270000 - 100000) -- o resumo nunca mostra prejuizo onde ha lucro", str(ago))
    conf(ago["porCabecaOk"] and abs(ago["receitaPorCabeca"] - 3000) < 0.01 and abs(ago["custoPorCabeca"] - 100000/90) < 0.01,
         "agosto: receita/cab = 3000 e custo/cab = 100000/90 (todas as 90 cab contam)", str(ago))
    bez = ago["categorias"][0]
    conf(bez["nome"] == "Venda de bezerro" and bez["cabecas"] == 90 and bez["receitaPorArroba"] is None,
         "categoria 'Venda de bezerro' mostra 90 cab e sem R$/@ (nao ha peso pra inventar)", str(bez))

    jul = page.evaluate("() => resumoPecuariaNoPeriodo({tipo:'mes', mes:'2026-07'})")
    conf(jul["receita"] == 68000 and jul["receitaRegistrada"] == 10000 and jul["receitaSemRegistro"] == 58000,
         "julho: so 10000 de 68000 da receita tem venda registrada (o resto: gado antigo sem registro + milho)", str(jul))
    conf(not jul["porCabecaOk"] and jul["custoPorCabeca"] is None and jul["receitaPorCabeca"] is None,
         "julho: cobertura baixa -> sem custo/receita por cabeca (ficariam inflados); total da atividade segue certo", str(jul))
    conf(jul["resultado"] == 68000 - 20000,
         "julho: o resultado da atividade inclui o milho excedente (receita da Pecuaria, nao some)", str(jul))
    bezJul = jul["categorias"][0]
    conf(abs(bezJul["arrobas"] - 200/30*10) < 0.01 and abs(bezJul["receitaPorArroba"] - 10000/(200/30*10)) < 0.01,
         "venda por kg: 10 animais x 200 kg / 30 = 66,67 @, R$/@ so do que tem peso (150)", str(bezJul))

    # a mesma conta na tela: o card unico da atividade e os numeros por cabeca
    page.evaluate("""() => {
      state.periodo = {tipo:'mes', mes:'2026-08'};
      state.page = 'resultados'; state.subAbaResultados = 'operacional';
      render();
    }""")
    page.wait_for_timeout(300)
    # innerText respeita o text-transform do CSS (rotulos saem em MAIUSCULAS),
    # entao compara em minusculas -- senao os "nao aparece" passariam de graca.
    texto_ago = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("pecuária — atividade toda" in texto_ago and "90 cab" in texto_ago,
         "tela (agosto): card 'Pecuária — atividade toda' com as 90 cab vendidas")
    conf("custo por cabeça vendida" in texto_ago and "r$ 1.111,11" in texto_ago,
         "tela (agosto): card do AE Pecuária mostra custo por cabeça vendida (R$ 1.111,11 = 100000/90)")
    conf("r$ 3.000,00 por cabeça" in texto_ago and "r$ 1.111,11 por cabeça" in texto_ago,
         "tela (agosto): card unico mostra receita e custo por cabeça (3000 e 1111,11)")
    conf("custo por @" not in texto_ago,
         "tela: acabou o 'Custo por @' da Pecuaria (dividia a despesa de tudo so pelas @ com peso)")
    conf("lucro/@" not in texto_ago,
         "tela: acabou o 'Lucro/@' por categoria de venda")
    conf("venda(s) por cabeça (90 animais), sem peso: entram nas cabeças vendidas" in texto_ago,
         "tela (agosto): aviso diz que as 90 vendidas por cabeça ENTRAM nas cabeças (nao 'nao entraram')")

    page.evaluate("""() => {
      state.periodo = {tipo:'mes', mes:'2026-07'};
      render();
    }""")
    page.wait_for_timeout(300)
    texto_jul = page.evaluate("() => document.body.innerText.toLowerCase()")
    conf("só 15% da receita" in texto_jul,
         "tela (julho): avisa que so 15% da receita tem venda com animais registrados")
    conf("custo por cabeça vendida" in texto_jul and "sem custo por cabeça" in texto_jul,
         "tela (julho): card do AE Pecuaria nao mostra custo por cabeça (cobertura baixa) e explica por que")
    page.evaluate("() => { state.periodo = {tipo:'mes', mes:'2026-09'}; }")  # devolve o filtro global

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
