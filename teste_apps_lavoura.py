"""Testes do AELavoura.html e dos dois apps em que ele virou (Cana/Cereais).

Reconstrução do zero (o original tinha 44 testes aqui, bem mais do que os 3
abaixo -- provavelmente cobria os formulários de talhão/aplicação de cada
app, que não tentei recriar sem poder rodar e ver o DOM de verdade). O que
ficou é o que dá pra garantir com confiança lendo o código: o link de quem
ainda tem o AELavoura.html salvo continua indo pro lugar certo, e nenhum dos
dois apps voltou a apontar pro projeto Supabase errado.
"""
from _test_utils import REPO, app_url


def test_lavoura_redireciona_para_cana(page):
    page.goto(app_url("AELavoura.html"))
    page.click("a.app:has-text('AE Cana')")
    assert page.url.endswith("AECana.html")


def test_lavoura_redireciona_para_cereais(page):
    page.goto(app_url("AELavoura.html"))
    page.click("a.app:has-text('AE Cereais')")
    assert page.url.endswith("AECereais.html")


def test_lavoura_redireciona_para_matriz(page):
    page.goto(app_url("AELavoura.html"))
    page.click("a.matriz")
    assert page.url.endswith("AEMatriz.html")


def _aponta_para_projeto_unificado(caminho_html):
    texto = (REPO / caminho_html).read_text(encoding="utf-8")
    assert "kmkystqgpvmzrccxvyaz.supabase.co" in texto
    assert "leojfqlbdtlriemdgnyw" not in texto, (
        "%s ainda referencia o projeto Supabase antigo/desativado da Pecuária"
        % caminho_html
    )


def test_cana_aponta_para_projeto_supabase_unificado():
    _aponta_para_projeto_unificado("AECana.html")


def test_cereais_aponta_para_projeto_supabase_unificado():
    _aponta_para_projeto_unificado("AECereais.html")
