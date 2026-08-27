"""Utilitários compartilhados pelos testes -- não é um arquivo de teste
(prefixo _ pra pytest não tentar coletar funções daqui como teste)."""
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPO = Path(__file__).parent
FUSO_BRASIL = ZoneInfo("America/Sao_Paulo")


def app_url(nome_arquivo):
    """file:// URL de um dos apps na raiz do repo, pro Playwright abrir direto."""
    return (REPO / nome_arquivo).as_uri()


def brasilia(ano, mes, dia, hora, minuto=0, segundo=0):
    """Instante absoluto correspondente a um horário local de Brasília --
    usar com page.clock pra testar código que depende de 'hoje' sem ficar
    refém do fuso horário de quem roda a suíte."""
    return datetime(ano, mes, dia, hora, minuto, segundo, tzinfo=FUSO_BRASIL)
