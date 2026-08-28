"""
Excluir e so de admin ou proprietario, em todo o app.

Por que este teste existe: a RLS nega DELETE em SILENCIO - apaga zero
linhas e nao devolve erro. Um botao de excluir que sobrasse na tela viraria
um clique que nao faz nada e nao explica nada. Entao o teste conta os
botoes: para quem nao e dono, tem que ser ZERO em todas as telas.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

PESSOAS = [
    ("Eduardo",  "admin",        {},                                                        True),
    ("Alice",    "proprietario", {"pec_financeiro": "editar"},                               True),
    ("Creunice", "colaborador",  {"matriz_financeiro": "editar", "contas": "editar",
                                  "pec_financeiro": "editar"},                               False),
    ("Gustavo",  "colaborador",  {"confinamento": "editar", "pasto": "editar",
                                  "cria": "editar", "dietas": "editar", "insumos": "editar",
                                  "operacoes": "editar", "cana_cadastros": "editar"},        False),
    ("Irlei",    "consultor",    {"pec_financeiro": "visualizar"},                           False),
]

BASE = {
    "fazendas": [{"id": 1, "nome": "Palhadao", "estado": "SP", "area_ha": 100, "ativo": True}],
    "fazenda_atividades": [{"id": 1, "fazenda_id": 1, "atividade": "cana", "area_ha": 80}],
    "centros_custo": [{"id": 90, "nome": "ADUBOS", "frente": None, "ativo": True,
                       "tipo": "saida", "subcategoria": "OPERACIONAL | X"}],
    "lancamentos_financeiros": [
        {"id": 1, "tipo": "despesa", "atividade": "cana", "fazenda_id": 1, "centro_custo_id": 90,
         "descricao": "Adubo", "valor": 100.0, "data": "2026-08-05", "mes": "2026-08", "areas": []}],
    "lotes": [{"id": 1, "nome": "Lote 1", "numero_animais": 10, "destino": "pasto"}],
    "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg"}],
    "dietas": [{"id": 1, "nome": "Dieta 1", "itens": []}],
    "culturas": [{"id": 1, "nome": "Cana", "frente": "cana"}],
    "talhoes_areas": [{"id": 1, "fazenda_id": 1, "nome": "T-01", "tipo": "talhao",
                       "area_ha": 10, "cultura_id": 1, "ativo": True}],
    "safras": [{"id": 1, "nome": "2026/27", "cultura_id": 1}],
    "funcionarios": [{"id": 1, "nome": "Ze", "ativo": True}],
    "funcionario_atividades": [], "lotes_pec": [],
    "entidades": [{"id": 5, "nome": "AGROSAQUY", "papel": "fornecedor", "ativo": True}],
    "contas_bancarias": [],
    "titulos": [{"id": 1, "tipo": "pagar", "entidade_id": 5, "descricao": "Boleto",
                 "valor": 500.0, "vencimento": "2026-12-01", "parcela": 1, "parcelas": 1,
                 "previsao": False, "cancelado": False, "valor_baixado": 0, "situacao": "aberto"}],
    "titulo_rateios": [{"id": 1, "titulo_id": 1, "fazenda_id": 1, "atividade": "cana",
                        "centro_custo_id": 90, "competencia": "2026-08", "valor": 500.0}],
    "titulo_baixas": [],
    # Cada tabela precisa de ao menos UMA linha: sem linha nao ha item na
    # lista, e sem item nao existe botao de excluir para contar. Um fixture
    # vazio faria o teste passar por ausencia de tela, nao por permissao.
    "animais": [{"id": 1, "numero": "001", "lote_id": 1}],
    "pesagens": [{"id": 1, "data": "2026-08-01", "lote_id": 1, "peso_medio_kg": 300}],
    "manejos": [{"id": 1, "data": "2026-08-01", "lote_id": 1}],
    "movimentos": [{"id": 1, "data": "2026-08-01", "ingrediente_id": 1,
                    "tipo": "entrada", "quantidade": 100}],
    "saidas_racao": [{"id": 1, "data": "2026-08-01", "lote_id": 1, "dieta_id": 1,
                      "quantidade": 50}],
    "leituras_cocho": [{"id": 1, "data": "2026-08-01", "lote_id": 1, "nota": 2}],
    "pasto": [{"id": 1, "data": "2026-08-01", "lote_id": 1, "dieta_id": 1, "quantidade": 10}],
    "producoes_racao": [{"id": 1, "data": "2026-08-01", "dieta_id": 1, "quantidade_kg": 500}],
    "reproducao_custos": [{"id": 1, "data": "2026-08-01", "lote_id": 1, "valor": 50}],
    "diagnosticos_gestacionais": [{"id": 1, "data": "2026-08-01", "lote_id": 1}],
    "partos": [{"id": 1, "data": "2026-08-01", "lote_id": 1}],
    "desmamas": [{"id": 1, "data": "2026-08-01", "lote_id": 1}],
    "abates": [{"id": 1, "data": "2026-08-01", "lote_id": 1}],
    "insumos_cana": [{"id": 1, "nome": "Ureia", "unidade": "kg", "categoria": "fertilizante"}],
    "insumos_graos": [{"id": 1, "nome": "Ureia", "unidade": "kg", "categoria": "fertilizante"}],
    "aplicacoes_cana": [{"id": 1, "data": "2026-08-01", "talhao_id": 1,
                         "insumo_id": 1, "quantidade": 10}],
    "aplicacoes_graos": [{"id": 1, "data": "2026-08-01", "talhao_id": 1,
                          "insumo_id": 1, "quantidade": 10}],
    "colheitas_cana": [{"id": 1, "data": "2026-08-01", "talhao_id": 1, "toneladas": 100}],
    "colheitas_graos": [{"id": 1, "data": "2026-08-01", "talhao_id": 1, "sacas": 100}],
    "plantios_cana": [{"id": 1, "data": "2026-08-01", "talhao_id": 1}],
    "plantios_graos": [{"id": 1, "data": "2026-08-01", "talhao_id": 1}],
    "entradas_insumo_cana": [{"id": 1, "data": "2026-08-01", "insumo_id": 1, "quantidade": 100}],
    "entradas_insumo_graos": [{"id": 1, "data": "2026-08-01", "insumo_id": 1, "quantidade": 100}],
    "custos_fixos": [], "precos_arroba": [], "investimentos": [], "receitas": [],
    "config_financeiro": [], "config_fazenda": [],
}

APPS = ["AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html"]

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    print("\n  EXCLUSAO SO DE ADMIN OU PROPRIETARIO")
    for app in APPS:
        print(f"\n  -- {app} --")
        for nome, papel, perms, deve in PESSOAS:
            page = browser.new_page()
            page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
            page.add_init_script(STUB)
            perfil = {"id": "u1", "nome": nome, "usuario": nome.lower(),
                      "papel": papel, "permissoes": perms, "ativo": True}
            page.add_init_script(
                f"window.__DB__ = {json.dumps(dict(BASE, profiles=[perfil]))};"
                f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
            page.goto("file://" + str(REPO / app))
            page.wait_for_timeout(900)

            # Varre TODAS as telas clicando na navegacao do proprio DOM.
            # Cada app tem um modelo de paginas diferente (PAGES no Matriz,
            # GROUPS na Pecuaria, subnav na lavoura); navegar pelo DOM
            # funciona nos quatro sem eu ter que conhecer cada um.
            contar = ("() => [...document.querySelectorAll('*')].filter(el =>"
                      "  [...el.attributes].some(a => a.name.startsWith('data-del-'))).length")
            # Pergunta ao proprio app quais telas existem. Navegar clicando
            # no DOM nao bastava: na Pecuaria as subabas so aparecem depois
            # de abrir o grupo, entao 31 cliques passavam longe da tela de
            # Ingredientes, que e onde o botao estava. O teste dava "0
            # botoes" e eu quase concluí que a varredura tinha apagado tudo.
            telas = page.evaluate("""() => {
              if (typeof PAGES !== 'undefined')
                return PAGES.map(p => p.key);
              // O AE Cereais monta os grupos a partir do cadastro de
              // culturas, entao nao existe mais um GROUPS constante nele.
              if (typeof gruposAtuais === 'function')
                return Object.values(gruposAtuais()).flatMap(g => (g.pages||[]).map(p => p.key));
              if (typeof GROUPS !== 'undefined')
                return Object.values(GROUPS).flatMap(g => (g.pages||[]).map(p => p.key));
              return [];
            }""")
            total = 0
            visitadas = 0
            for chave in telas:
                page.evaluate("(k) => { state.page = k; render(); }", chave)
                page.wait_for_timeout(110)
                visitadas += 1
                total += page.evaluate(contar)
            achou = total > 0
            conf(achou == deve,
                 f"{nome} ({papel}): {'tem' if deve else 'NAO tem'} botao de excluir",
                 f"encontrou {total} botoes em {visitadas} telas")
            page.close()
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
