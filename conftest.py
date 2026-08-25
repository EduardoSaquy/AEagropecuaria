import pytest
from pathlib import Path

REPO = Path(__file__).parent


def app_url(nome_arquivo):
    """file:// URL de um dos apps na raiz do repo, pro Playwright abrir direto."""
    return (REPO / nome_arquivo).as_uri()


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args):
    # Os apps assumem fuso do Brasil pra "hoje" (ver hojeStr/mesAtualStr em
    # cada app). Fixar o fuso do contexto de teste evita que os testes só
    # peguem o bug de toISOString() por acidente, dependendo do fuso da
    # máquina que roda a suíte.
    return {**browser_context_args, "timezone_id": "America/Sao_Paulo"}
