"""
Financeiro e R$ so para administrador e proprietario (decisao do Eduardo, 12/11/2026).

Regra: o financeiro e so dele e dos proprietarios. Nos apps da operacao e no Painel do Matriz, valor, custo, preco medio e resultado
aparecem so para quem tem acesso total; quem trabalha na operacao ve kg, litros, cabecas e ganho de peso. Excecoes decididas por ele:
quem registra uma compra (insumo, nota de diesel) ou o custo do protocolo digita o preco NO FORMULARIO de entrada (mas nao ve totais,
preco medio nem valor em estoque nas listas); quem tem Vendas ve o valor na tela de Vendas; o consultor ve o custo da dieta e o preco
dos ingredientes ("so nas dietas"). Prova, app por app, comparando administrador com quem nao tem acesso total:
  - Matriz: Resultados e Financiamentos somem do menu; o Financeiro avisa que mostra so os lancamentos da pessoa e perde "Custo por
    hectare" (tela e setinha do menu); o custo do diesel no Painel vira traco; a tela de acesso mostra Resultados, Financiamentos e o
    Financeiro/Resultados da Pecuaria como "So administrador e proprietarios".
  - Pecuaria: Financeiro e Resultados somem (mesmo com pec_financeiro); as acoes de dinheiro ficam so do acesso total; estoque, saida de
    racao, inseminacao e Custo/@ sem R$; Vendas com valor so para quem tem Vendas; dieta e ingrediente com preco para o consultor;
    o formulario de entrada de insumo e o de inseminacao continuam pedindo o preco.
  - Cana e Cereais: estoque sem valor nem preco medio; lista de entradas sem "Preco pago" e de aplicacoes sem "Custo", mas o formulario
    da entrada continua com o preco.
  - Combustivel: estoque sem valor; lista de notas sem valor (formulario com); manutencao sem custo; Rateio so com litros; Painel com
    traco no custo; relatorio e CSV sem as colunas de R$.
Falha no codigo anterior (as telas mostravam R$ para todos).
"""
import json
import sys
from datetime import date
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
HOJE = date.today().isoformat()
MES = HOJE[:7]
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def perfil(i, nome, papel, permissoes=None):
    return {"id": i, "nome": nome, "usuario": nome.lower(), "papel": papel, "ativo": True, "permissoes": permissoes or {}, "frentes": []}


ADMIN = perfil("u1", "Chefe", "admin")
DONA = perfil("u2", "Dona", "proprietario")
ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource", "net::ERR")


def abre(browser, arquivo, db, logado, largura=1280):
    ctx = browser.new_context(viewport={"width": largura, "height": 900})
    page = ctx.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.on("dialog", lambda d: d.dismiss())
    page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    perfis = db.get("profiles") or []
    if not any(p["id"] == logado["id"] for p in perfis):
        perfis = perfis + [logado]
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(db, profiles=perfis))};"
                         f"window.__SESSAO__ = {{user:{{id:{json.dumps(logado['id'])}}}, access_token:'x'}};")
    page.goto((REPO / arquivo).as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.perfil && state.perfil.id", timeout=30000)
    page.wait_for_timeout(1200)
    return ctx, page, erros


def sem_erro(erros):
    return [e for e in erros if not any(r in e for r in ruido)]


# ============================================================ MATRIZ
DB_MATRIZ = {
    "fazendas": [{"id": 1, "nome": "Mata Verde", "ativo": True}], "fazenda_atividades": [], "talhoes_areas": [], "culturas": [],
    "centros_custo": [{"id": 1, "nome": "Adubo", "tipo": "saida", "ativo": True}],
    "lancamentos_financeiros": [{"id": 10, "tipo": "despesa", "atividade": "cana", "valor": 100, "data": HOJE, "mes": MES,
                                 "centro_custo_id": 1, "descricao": "Adubo", "areas": []}],
    "lancamentos_rateados": [], "funcionarios": [], "funcionario_atividades": [], "financiamentos": [], "parcelas_financiamento": [],
    "movimentos_financiamento": [], "entidades": [], "contas_bancarias": [], "titulos": [], "titulo_rateios": [], "titulo_baixas": [],
    "tanques": [{"id": 1, "nome": "T1", "ativo": True, "fazenda_id": 1}], "entradas_estoque": [], "abastecimentos": [], "ajustes_estoque": [],
    "alertas": [], "lotes": [], "equipamentos": [],
}
SECRETARIA = perfil("u5", "Secretaria", "colaborador", {"matriz_financeiro": "editar", "contas": "editar",
                    "matriz_painel_combustivel": "visualizar", "combustivel_rateio": "visualizar", "combustivel_estoque": "visualizar",
                    "matriz_resultados": "visualizar", "matriz_financiamentos": "visualizar"})
JS_MATRIZ = """async () => {
  const paginas = paginasVisiveis().map(p=>p.key);
  state.page = 'financeiro'; state.abaFinanceiro = 'despesa'; render();
  const fin = PageFinanceiro();
  state.abaFinanceiro = 'custoha';
  const finCustoha = PageFinanceiro();
  const abaDepois = state.abaFinanceiro;
  state.abaFinanceiro = 'despesa'; render();
  const subMenu = document.querySelectorAll('[data-menu-sub="financeiro|custoha"]').length;
  await carregarIndicadoresCombustivel();
  const painelCusto = state.indicadores.combustivel.pode.custo;
  return {paginas, temAviso: fin.includes('data-aviso-so-os-seus'), temCustoha: fin.includes('data-aba-financeiro="custoha"'),
          custohaVirouDespesa: abaDepois==='despesa' && !finCustoha.includes('Hectares'), subMenu, painelCusto};
}"""

# ============================================================ PECUARIA
DB_PEC = {
    "lotes": [{"id": 30, "nome": "Curral 1", "destino": "confinamento", "numero_animais": 10, "data_inicio": "2026-01-01",
               "data_fim": None, "dieta_id": 1, "sexo": "macho"},
              {"id": 31, "nome": "Vacas", "destino": "reproducao", "numero_animais": 20, "data_inicio": "2026-01-01",
               "data_fim": None, "sexo": "femea"}],
    "dietas": [{"id": 1, "nome": "Dieta Engorda", "tipo": "confinamento", "kg_animal_dia": 10, "itens": [{"ingredienteId": 1, "pct": 100}]}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "ms": 88, "pb": 9, "ndt": 80, "preco_kg": 2.0, "estoque_min": 0}],
    "movimentos": [{"id": 1, "ingrediente_id": 1, "tipo": "entrada", "data": HOJE, "quantidade": 1000, "preco_kg": 2.0}],
    "saidas_racao": [{"id": 1, "data": HOJE, "lote_id": 30, "dieta_id": 1, "quantidade_kg": 100}],
    "reproducao_custos": [{"id": 1, "data": HOJE, "lote_id": 31, "numero_vaca": "12", "raca_touro": "angus", "qual_inseminacao": "1",
                           "item": "IATF", "custo": 150}],
    "pesagens": [{"id": 1, "lote_id": 30, "data": "2026-01-01", "peso_medio_kg": 300, "numero_animais": 10},
                 {"id": 2, "lote_id": 30, "data": HOJE, "peso_medio_kg": 400, "numero_animais": 10}],
    "abates": [{"id": 1, "data": HOJE, "lote_id": 30, "quantidade": 2, "tipo_venda": "cabeca", "valor_por_animal": 3000,
                "categoria": "boi", "sexo": "macho"}],
    "fazendas": [], "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [], "lancamentos_rateados": [],
    "animais": [], "pesagens_animais": [], "manejos": [], "leituras_cocho": [], "pasto": [], "producoes_racao": [],
    "diagnosticos_gestacionais": [], "partos": [], "desmamas": [], "custos_fixos": [], "precos_arroba": [], "investimentos": [],
    "receitas": [], "config_financeiro": [{"id": 1}], "config_fazenda": [], "funcionarios": [],
}
OPERADOR = perfil("u6", "Curral", "colaborador", {"confinamento": "editar", "cria": "editar", "insumos": "editar", "dietas": "visualizar"})
CONSULTOR = perfil("u7", "Consultor", "consultor", {"dietas": "editar", "insumos": "editar", "confinamento": "editar", "pec_financeiro": "visualizar"})
VENDEDORA = perfil("u8", "Vendedora", "colaborador", {"vendas": "editar", "confinamento": "visualizar", "insumos": "editar",
                   "pec_financeiro": "editar", "pec_resultados": "editar"})
JS_PEC = """() => {
  const estoque = PageEstoque(), ingr = PageIngredientes(), dietas = PageDietas(), racao = PageSaidaRacao('confinamento');
  state.subAbaReproducao = 'inseminacao';
  const insem = PageReproducao(), pesagem = PagePesagem('confinamento'), vendas = PageVendasGeral();
  editDraft = {ingredienteId: 1, tipo: 'entrada', data: '', quantidade: '', precoKg: ''};
  const movimento = ModalMovimento();
  editDraft = {loteId: '', data: '', numeroVaca: '', racaTouro: '', qualInseminacao: '1', custo: ''};
  const formInsem = ModalReproducaoCusto();
  return {
    financeiro: grupoVisivel('financeiro'), resultados: grupoVisivel('resultados'),
    acoes: ['receita','precoArroba','custoFixo','metaMargem','investimento'].map(podeEditarAcao),
    estoqueValor: estoque.includes('Valor total em estoque'), estoqueRkg: estoque.includes('R$/kg'),
    ingrPreco: ingr.includes('R$'), dietaCusto: dietas.includes('Custo/kg'),
    racaoCusto: racao.includes('Custo estimado'), insemCusto: insem.includes('Custo do protocolo'), insemTemLinha: insem.includes('angus') || insem.includes('Angus'),
    pesagemCusto: pesagem.includes('Custo/@'), pesagemTemGanho: pesagem.includes('@ produzidas'),
    vendasValor: vendas.includes('Receita total') && vendas.includes('R$ 6.000'), vendasQtd: vendas.includes('Animais vendidos'),
    movimentoPreco: movimento.includes('f-precoentrada'), movimentoPrecoAtual: movimento.includes('Preço atual'),
    formInsemCusto: formInsem.includes('f-custoreproducao'),
  };
}"""
JS_PEC_PERM = """() => {
  editDraft = {id: 'u6', nome: 'Curral', usuario: 'curral', papel: 'colaborador', ativo: true, permissoes: {pec_financeiro: 'editar'}};
  const m = ModalPermissoes();
  return {soDono: ['pec_financeiro','pec_resultados'].every(k=>m.includes(`data-perm-so-acesso-total="${k}"`)),
          semSelect: !m.includes('data-perm-modulo="pec_financeiro"') && !m.includes('data-perm-modulo="pec_resultados"'),
          vendasSelect: m.includes('data-perm-modulo="vendas"')};
}"""

# ============================================================ CANA / CEREAIS
def db_lavoura(frente):
    sufixo = "cana" if frente == "Cana" else "graos"
    return {
        "fazendas": [{"id": 1, "nome": "Palmito", "ativo": True}], "fazenda_atividades": [],
        "culturas": [{"id": 1, "nome": "Cana" if frente == "Cana" else "Soja", "frente": "cana" if frente == "Cana" else "graos", "ativo": True}],
        "talhoes_areas": [{"id": 1, "nome": "Talhão 1", "fazenda_id": 1, "cultura_id": 1, "area_ha": 10, "tipo": "talhao", "ativo": True}],
        "safras": [], "centros_custo": [],
        f"insumos_{sufixo}": [{"id": 1, "nome": "Ureia", "categoria": "fertilizante", "unidade": "kg", "estoque_minimo": 0, "ativo": True}],
        f"entradas_insumo_{sufixo}": [{"id": 1, "insumo_id": 1, "data": HOJE, "quantidade": 100, "preco_pago": 4.5, "fornecedor": "Agro"}],
        f"aplicacoes_{sufixo}": [{"id": 1, "talhao_id": 1, "insumo_id": 1, "data": HOJE, "tipo_operacao": "adubacao", "quantidade": 10}],
        "plantios_cana": [], "colheitas_cana": [], "plantios_graos": [], "colheitas_graos": [],
    }


OP_CANA = perfil("u9", "Operador", "operador", {"operacoes": "editar", "cana_cadastros": "editar", "operacoes_graos": "editar", "cereais_cadastros": "editar"})


def js_lavoura(frente):
    k = "Cana" if frente == "Cana" else "Graos"
    return f"""async () => {{
  const est = PageEstoqueInsumos('{frente}');
  const entradas = PageCadastro('entradasInsumo{k}'), aplic = PageCadastro('aplicacoes{k}');
  state.page = 'entradasInsumo{k}'; render();
  await new Promise(r=>setTimeout(r, 50));
  const btn = document.querySelector('[data-novo-cadastro="entradasInsumo{k}"]');
  if(btn) btn.click();
  await new Promise(r=>setTimeout(r, 100));
  const modal = document.querySelector('.modal');
  return {{valorEstoque: est.includes('Valor aprox. em estoque'), precoMedio: est.includes('Preço médio'),
          entradasPreco: entradas.includes('Preço pago'), entradasQtd: entradas.includes('Quantidade'),
          aplicCusto: aplic.includes('>Custo<'), formPreco: !!(modal && modal.textContent.includes('Preço pago')), abriuForm: !!modal}};
}}"""


# ============================================================ COMBUSTIVEL
DB_COMB = {
    "fazendas": [{"id": 1, "nome": "Mata Verde", "estado": "GO", "area_ha": 100, "ativo": True}],
    "produtos": [{"id": 1, "nome": "Diesel S10", "unidade": "L", "ativo": True}],
    "fornecedores": [{"id": 1, "nome": "Posto", "ativo": True}],
    "tanques": [{"id": 1, "fazenda_id": 1, "nome": "Tanque 1", "produto_id": 1, "capacidade_litros": 10000, "tipo": "fixo", "ativo": True}],
    "entradas_estoque": [{"id": 1, "tanque_id": 1, "fornecedor_id": 1, "numero_nf": "1", "data": HOJE, "volume_litros": 1000, "valor_total": 6000}],
    "equipamentos": [{"id": 1, "nome": "Trator", "tipo": "trator", "tipo_medidor": "horimetro", "ativo": True, "fazenda_id": 1}],
    "abastecimentos": [{"id": 1, "fazenda_id": 1, "tanque_id": 1, "equipamento_id": 1, "data_hora": HOJE + "T08:00:00", "volume_litros": 100,
                        "leitura_medidor": 10, "frente": "cana"},
                       {"id": 2, "fazenda_id": 1, "tanque_id": 1, "equipamento_id": 1, "data_hora": HOJE + "T18:00:00", "volume_litros": 50,
                        "leitura_medidor": 20, "frente": "cana"}],
    "manutencoes": [{"id": 1, "equipamento_id": 1, "tipo": "troca_oleo", "data": HOJE, "leitura": 10, "intervalo": 250, "custo": 800}],
    "medicoes_fisicas": [], "ajustes_estoque": [], "alertas": [], "talhoes_areas": [], "culturas": [], "operacoes": [], "safras": [],
    "funcionarios": [], "lancamentos_financeiros": [],
}
COLAB = perfil("u10", "Secretaria", "colaborador", {"combustivel_estoque": "editar", "combustivel_cadastros": "editar", "combustivel_rateio": "visualizar",
               "combustivel_abastecimento": "visualizar", "combustivel_alertas": "visualizar", "combustivel_auditoria": "visualizar"})
JS_COMB = """async () => {
  const est = PageEstoqueResumo(), notas = PageCadastro('entradasEstoque'), manut = PageManutencoes();
  const frente = PageRateioFrente(), equip = PageRateioEquipamento(), painel = PagePainel();
  const colsFrente = colunasDoRelatorio(RELATORIO_TIPOS.frente).map(c=>c.label);
  const colsAbast = colunasDoRelatorio(RELATORIO_TIPOS.abastecimentos).map(c=>c.label);
  state.page = 'entradasEstoque'; render();
  await new Promise(r=>setTimeout(r, 50));
  const btn = document.querySelector('[data-novo-cadastro="entradasEstoque"]');
  if(btn) btn.click();
  await new Promise(r=>setTimeout(r, 100));
  const modal = document.querySelector('.modal');
  return {valorEstoque: est.includes('Valor aprox. em estoque'), notasValor: notas.includes('Valor total'), notasVolume: notas.includes('Volume'),
          manutCusto: manut.includes('>Custo<'), frenteCusto: frente.includes('Custo no período'), frenteVolume: frente.includes('Volume no período'),
          equipRs: equip.includes('R$ por hora'), equipConsumo: equip.includes('Consumo'), painelCusto: painel.includes('R$ '),
          relatorioRs: colsFrente.some(l=>l.includes('R$')) || colsAbast.some(l=>l.includes('R$')),
          relatorioVolume: colsFrente.includes('Volume (L)'),
          formValor: !!(modal && modal.textContent.includes('Valor total')), abriuForm: !!modal};
}"""

with sync_playwright() as pw:
    exe = "/opt/pw-browsers/chromium"
    browser = pw.chromium.launch(executable_path=exe) if Path(exe).exists() else pw.chromium.launch()

    print("\n== AE Matriz")
    r = {}
    for nome, quem in (("admin", ADMIN), ("dona", DONA), ("secretaria", SECRETARIA)):
        ctx, page, erros = abre(browser, "AEMatriz.html", DB_MATRIZ, quem)
        r[nome] = page.evaluate(JS_MATRIZ)
        conf(not sem_erro(erros), f"{nome}: abre sem erro de JavaScript", " | ".join(sem_erro(erros)[:3]))
        ctx.close()
    for nome in ("admin", "dona"):
        conf("resultados" in r[nome]["paginas"] and "financiamentos" in r[nome]["paginas"], f"{nome}: Resultados e Financiamentos no menu", str(r[nome]["paginas"]))
        conf(not r[nome]["temAviso"] and r[nome]["temCustoha"] and r[nome]["subMenu"] == 1, f"{nome}: Financeiro completo, com Custo por hectare (tela e menu)", str(r[nome]))
        conf(r[nome]["painelCusto"] is True, f"{nome}: custo do diesel no Painel")
    s = r["secretaria"]
    conf("resultados" not in s["paginas"] and "financiamentos" not in s["paginas"], "secretaria: Resultados e Financiamentos fora do menu (mesmo com a permissao marcada)", str(s["paginas"]))
    conf("financeiro" in s["paginas"] and "contas" in s["paginas"], "secretaria: Financeiro e Pagar/Receber continuam", str(s["paginas"]))
    conf(s["temAviso"], "secretaria: o Financeiro avisa que mostra so os lancamentos dela")
    conf(not s["temCustoha"] and s["subMenu"] == 0, "secretaria: sem Custo por hectare (tela e setinha do menu)", str(s))
    conf(s["custohaVirouDespesa"], "secretaria: aba Custo por hectare guardada volta para Despesas")
    conf(s["painelCusto"] is False, "secretaria: custo do diesel no Painel vira traco (mesmo com Rateio do Combustivel)")
    ctx, page, erros = abre(browser, "AEMatriz.html", dict(DB_MATRIZ, profiles=[ADMIN, SECRETARIA]), ADMIN)
    m = page.evaluate("""() => { const b = blocoPermissoes('u5');
      return {soDono: ['matriz_resultados','matriz_financiamentos','pec_financeiro','pec_resultados'].every(k=>b.includes(`data-perm-so-acesso-total="${k}"`)),
              semSelect: !['matriz_resultados','matriz_financiamentos','pec_financeiro','pec_resultados'].some(k=>b.includes(`data-perm-modulo="${k}"`)),
              finSelect: b.includes('data-perm-modulo="matriz_financeiro"') && b.includes('data-perm-modulo="contas"')}; }""")
    conf(m["soDono"] and m["semSelect"], "tela de acesso: Resultados, Financiamentos e Financeiro/Resultados da Pecuaria como 'So administrador e proprietarios'", str(m))
    conf(m["finSelect"], "tela de acesso: Financeiro e Contas continuam com a escolha")
    ctx.close()

    print("\n== AE Pecuaria")
    rp = {}
    for nome, quem in (("admin", ADMIN), ("operador", OPERADOR), ("consultor", CONSULTOR), ("vendedora", VENDEDORA)):
        ctx, page, erros = abre(browser, "AEpecuaria.html", DB_PEC, quem)
        rp[nome] = page.evaluate(JS_PEC)
        conf(not sem_erro(erros), f"{nome}: abre sem erro de JavaScript", " | ".join(sem_erro(erros)[:3]))
        ctx.close()
    a = rp["admin"]
    conf(a["financeiro"] and a["resultados"] and all(a["acoes"]), "admin: Financeiro, Resultados e acoes de dinheiro", str(a))
    conf(a["estoqueValor"] and a["ingrPreco"] and a["dietaCusto"] and a["racaoCusto"] and a["insemCusto"] and a["pesagemCusto"] and a["vendasValor"],
         "admin: todos os R$ (estoque, ingrediente, dieta, racao, inseminacao, Custo/@, vendas)", str(a))
    conf(a["movimentoPrecoAtual"], "admin: entrada de insumo mostra o preco atual")
    for nome in ("operador", "consultor", "vendedora"):
        x = rp[nome]
        conf(not x["financeiro"] and not x["resultados"], f"{nome}: sem Financeiro e Resultados", str(x))
        conf(not any(x["acoes"]), f"{nome}: sem acoes de dinheiro (receita, preco da @, despesa, meta, investimento)", str(x["acoes"]))
        conf(not x["estoqueValor"] and not x["estoqueRkg"], f"{nome}: estoque sem valor nem R$/kg")
        conf(not x["racaoCusto"], f"{nome}: saida de racao sem custo estimado")
        conf(not x["pesagemCusto"] and x["pesagemTemGanho"], f"{nome}: pesagem com @ produzidas e sem Custo/@", str(x))
        conf(x["movimentoPreco"], f"{nome}: o formulario de entrada de insumo continua pedindo o preco pago")
    for nome in ("operador",):
        x = rp[nome]
        conf(not x["insemCusto"] and x["insemTemLinha"], "operador: lista de inseminacoes sem custo do protocolo (a linha aparece)", str(x))
        conf(x["formInsemCusto"], "operador: o formulario de inseminacao continua pedindo o custo do protocolo")
        conf(not x["ingrPreco"] and not x["dietaCusto"], "operador: ingrediente e dieta sem preco")
        conf(not x["vendasValor"] and x["vendasQtd"], "operador: Vendas mostra cabecas e nenhum valor", str(x))
        conf(not x["movimentoPrecoAtual"], "operador: entrada de insumo sem o preco atual")
    c = rp["consultor"]
    conf(c["ingrPreco"] and c["dietaCusto"], "consultor: preco dos ingredientes e custo da dieta (so nas dietas)", str(c))
    conf(not c["vendasValor"], "consultor: Vendas sem valor")
    v = rp["vendedora"]
    conf(v["vendasValor"], "vendedora (Vendas): ve o valor das vendas", str(v))
    conf(not v["ingrPreco"] and not v["dietaCusto"], "vendedora: ingrediente e dieta sem preco")
    ctx, page, erros = abre(browser, "AEpecuaria.html", DB_PEC, ADMIN)
    pp = page.evaluate(JS_PEC_PERM)
    conf(pp["soDono"] and pp["semSelect"] and pp["vendasSelect"], "tela de acesso da Pecuaria: Financeiro e Resultados como 'So administrador e proprietarios'", str(pp))
    ctx.close()

    for arquivo, frente in (("AECana.html", "Cana"), ("AECereais.html", "Graos")):
        print(f"\n== {arquivo}")
        rl = {}
        for nome, quem in (("admin", ADMIN), ("operador", OP_CANA)):
            ctx, page, erros = abre(browser, arquivo, db_lavoura(frente), quem)
            rl[nome] = page.evaluate(js_lavoura(frente))
            conf(not sem_erro(erros), f"{nome}: abre sem erro de JavaScript", " | ".join(sem_erro(erros)[:3]))
            ctx.close()
        a, o = rl["admin"], rl["operador"]
        conf(a["valorEstoque"] and a["precoMedio"] and a["entradasPreco"] and a["aplicCusto"], "admin: valor em estoque, preco medio, preco pago e custo", str(a))
        conf(not o["valorEstoque"] and not o["precoMedio"], "operador: estoque sem valor nem preco medio", str(o))
        conf(not o["entradasPreco"] and o["entradasQtd"], "operador: lista de entradas com quantidade e sem preco pago", str(o))
        conf(not o["aplicCusto"], "operador: lista de aplicacoes sem custo")
        conf(o["abriuForm"] and o["formPreco"], "operador: o formulario da entrada continua pedindo o preco pago", str(o))

    print("\n== AE Combustivel")
    rc = {}
    for nome, quem in (("admin", ADMIN), ("colaboradora", COLAB)):
        ctx, page, erros = abre(browser, "AECombustivel.html", DB_COMB, quem)
        rc[nome] = page.evaluate(JS_COMB)
        conf(not sem_erro(erros), f"{nome}: abre sem erro de JavaScript", " | ".join(sem_erro(erros)[:3]))
        ctx.close()
    a, o = rc["admin"], rc["colaboradora"]
    conf(a["valorEstoque"] and a["notasValor"] and a["manutCusto"] and a["frenteCusto"] and a["equipRs"] and a["painelCusto"] and a["relatorioRs"],
         "admin: todos os R$ (estoque, notas, manutencao, rateio, painel, relatorio)", str(a))
    conf(not o["valorEstoque"], "colaboradora: estoque sem valor")
    conf(not o["notasValor"] and o["notasVolume"], "colaboradora: lista de notas com volume e sem valor", str(o))
    conf(not o["manutCusto"], "colaboradora: manutencao sem custo")
    conf(not o["frenteCusto"] and o["frenteVolume"], "colaboradora: rateio por frente so com litros", str(o))
    conf(not o["equipRs"] and o["equipConsumo"], "colaboradora: rateio por equipamento com consumo e sem R$", str(o))
    conf(not o["painelCusto"], "colaboradora: Painel sem custo em R$ (mesmo com Rateio)")
    conf(not o["relatorioRs"] and o["relatorioVolume"], "colaboradora: relatorio e CSV sem colunas de R$", str(o))
    conf(o["abriuForm"] and o["formValor"], "colaboradora: o formulario da nota continua pedindo o valor", str(o))

    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
