"""Testes do AEMatriz.html.

Reconstrução do zero -- os testes originais (era pra ter 34 aqui, segundo o
CLAUDE.md) se perderam com a máquina antiga. Esta versão é menor e foca nas
regras que já causaram erro de verdade, documentadas no CLAUDE.md e no
próprio código: independência de mes/data, o agrupamento de recorrentes em
vigentesNoMes (chave com fazenda+área, pra não misturar duas contas com o
mesmo nome de fazendas diferentes) e hojeStr() não avançar o dia à noite no
Brasil. Nenhum desses bugs está aberto hoje -- os três já foram corrigidos
no código atual; os testes existem pra não deixarem voltar.

Cada teste abre o AEMatriz.html de verdade (via file://) e chama as funções
puras do app diretamente com page.evaluate -- elas ficam disponíveis no
escopo global porque o app é um <script> clássico, sem type="module", então
as declarações `function nome(){...}` são hospedadas (hoisted) mesmo que o
resto do boot (supabase.createClient, carregar dados) não termine ou dê erro
sem rede. Não precisamos simular login nem mockar o Supabase pra testar essa
camada.

Precisa de internet na hora de rodar: o app carrega a biblioteca do Supabase
de um CDN (cdn.jsdelivr.net) antes do próprio código -- sem ela, o script
pode nem chegar a declarar as funções.
"""
import json

from _test_utils import app_url, brasilia


def test_lancamento_to_row_deriva_mes_da_data(page):
    page.goto(app_url("AEMatriz.html"))
    lancamento = {
        "tipo": "despesa", "atividade": "geral", "fazendaId": None,
        "centroCustoId": 7, "descricao": "Combustível", "valor": 1200,
        "data": "2026-05-10", "mes": None,
        "fornecedor": "", "observacao": "", "areas": [],
        "talhaoId": None, "loteId": None, "arrobas": None,
    }
    row = page.evaluate("lancamentoToRow(%s)" % json.dumps(lancamento))
    assert row["data"] == "2026-05-10"
    assert row["mes"] == "2026-05"


def test_lancamento_to_row_preserva_mes_quando_edita_sem_data(page):
    """O caso que já corrompeu dado de verdade: lançamento histórico com
    mês preenchido e sem data (competência mensal) não pode virar recorrente
    (mes=None) só por ter sido reaberto e salvo de novo."""
    page.goto(app_url("AEMatriz.html"))
    lancamento = {
        "tipo": "despesa", "atividade": "geral", "fazendaId": None,
        "centroCustoId": 7, "descricao": "Contador", "valor": 900,
        "data": "", "mes": "2025-11",
        "fornecedor": "", "observacao": "", "areas": [],
        "talhaoId": None, "loteId": None, "arrobas": None,
    }
    row = page.evaluate("lancamentoToRow(%s)" % json.dumps(lancamento))
    assert row["data"] is None
    assert row["mes"] == "2025-11"


def test_lancamento_novo_sem_data_e_sem_mes_fica_recorrente(page):
    page.goto(app_url("AEMatriz.html"))
    lancamento = {
        "tipo": "despesa", "atividade": "geral", "fazendaId": None,
        "centroCustoId": 7, "descricao": "Internet", "valor": 150,
        "data": "", "mes": None,
        "fornecedor": "", "observacao": "", "areas": [],
        "talhaoId": None, "loteId": None, "arrobas": None,
    }
    row = page.evaluate("lancamentoToRow(%s)" % json.dumps(lancamento))
    assert row["data"] is None
    assert row["mes"] is None


def _despesa(descricao, centro_custo_id, atividade, fazenda_id, areas, mes):
    return {
        "descricao": descricao, "centroCustoId": centro_custo_id,
        "atividade": atividade, "fazendaId": fazenda_id, "areas": areas,
        "mes": mes, "valor": 1000,
    }


def test_vigentes_no_mes_nao_mistura_fazendas_diferentes(page):
    """Sem fazenda na chave de agrupamento, um recorrente 'Aluguel' da
    Fazenda A seria engolido por um lançamento pontual 'Aluguel' da
    Fazenda B com o mesmo centro de custo/atividade."""
    page.goto(app_url("AEMatriz.html"))
    despesas = [
        _despesa("Aluguel", 3, "graos", "fazenda-a", [], None),  # recorrente A
        _despesa("Aluguel", 3, "graos", "fazenda-b", [], None),  # recorrente B
    ]
    resultado = page.evaluate(
        "vigentesNoMes(%s, '2026-03')" % json.dumps(despesas)
    )
    assert len(resultado) == 2
    fazendas = {r["fazendaId"] for r in resultado}
    assert fazendas == {"fazenda-a", "fazenda-b"}


def test_vigentes_no_mes_lancamento_do_mes_substitui_recorrente(page):
    page.goto(app_url("AEMatriz.html"))
    despesas = [
        _despesa("Salário", 1, "pecuaria", "fazenda-a", [], None),        # recorrente
        _despesa("Salário", 1, "pecuaria", "fazenda-a", [], "2026-03"),   # valor real do mês
    ]
    resultado = page.evaluate(
        "vigentesNoMes(%s, '2026-03')" % json.dumps(despesas)
    )
    assert len(resultado) == 1
    assert resultado[0]["mes"] == "2026-03"


def test_vigentes_no_mes_recorrente_vale_em_mes_sem_lancamento_proprio(page):
    page.goto(app_url("AEMatriz.html"))
    despesas = [
        _despesa("Salário", 1, "pecuaria", "fazenda-a", [], None),
        _despesa("Salário", 1, "pecuaria", "fazenda-a", [], "2026-03"),
    ]
    resultado = page.evaluate(
        "vigentesNoMes(%s, '2026-04')" % json.dumps(despesas)
    )
    assert len(resultado) == 1
    assert resultado[0]["mes"] is None


def test_hoje_str_nao_avanca_dia_a_noite_no_brasil(page):
    """new Date().toISOString() já mostra o dia seguinte em UTC entre ~21h
    e meia-noite no horário do Brasil -- hojeStr() existe pra evitar isso."""
    page.clock.install(time=brasilia(2026, 3, 15, 23, 30))
    page.goto(app_url("AEMatriz.html"))
    assert page.evaluate("hojeStr()") == "2026-03-15"
