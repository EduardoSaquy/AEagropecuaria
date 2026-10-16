"""
Confere, com a chave PUBLICA do site, o que um estranho consegue ler do banco.

A chave "anon" fica no codigo da pagina (de proposito: o app precisa dela
para entrar). O banco se protege com RLS, que esconde as linhas de quem nao
esta logado. Tabela com RLS devolve vazio; VIEW nao: ela roda com os direitos
de quem a criou e passa por cima do RLS. Foi assim que o Financeiro inteiro
ficou aberto por lancamentos_rateados ate 16/10/2026 (ver
seguranca_01_fecha_view_para_anonimo.sql).

Este script pergunta so a CONTAGEM de linhas de cada tabela ou view que os
apps usam, de toda tabela ou view que algum script .sql do repositorio cria
(inclusive copias de seguranca: tabela criada pelo editor do Supabase nasce
aberta para o "anon") e de algumas internas. Nunca baixa uma linha. Sai com
codigo 1 se algum objeto devolver linhas para a chave publica.

    python conferir_chave_publica.py

Precisa de internet. Rode depois de criar qualquer view ou tabela nova.
"""
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent
APPS = ("AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html")

# objetos que o app nem sempre cita pelo nome mas que guardam dado sensivel
EXTRAS = (
    "lancamentos_financeiros", "lancamentos_rateados", "lancamento_rateios", "log_alteracoes",
    "profiles", "entidades", "titulos", "titulo_baixas", "titulo_rateios", "contas_bancarias",
    "financiamentos", "parcelas_financiamento", "movimentos_financiamento",
    "erp_plano_contas", "erp_staging", "centros_custo",
)

RE_CLIENTE = re.compile(r"createClient\(\s*'(https://[a-z0-9]+\.supabase\.co)'\s*,\s*'([^']+)'")
RE_TABELA = re.compile(r"\.from\(\s*['\"]([a-z_][a-z_0-9]*)['\"]")
RE_CRIA = re.compile(
    r"create\s+(?:or\s+replace\s+)?(?:(?:global\s+|local\s+)?temp(?:orary)?\s+)?(?:materialized\s+)?"
    r"(?:table|view)\s+(?:if\s+not\s+exists\s+)?(?:public\.)?\"?([a-z_][a-z0-9_]*)\"?", re.I)


def projetos_e_tabelas():
    projetos, tabelas = {}, set(EXTRAS)
    for app in APPS:
        caminho = REPO / app
        if not caminho.exists():
            continue
        txt = caminho.read_text(encoding="utf-8")
        for url, chave in RE_CLIENTE.findall(txt):
            projetos[url] = chave
        tabelas.update(RE_TABELA.findall(txt))
    for sql in REPO.glob("*.sql"):
        tabelas.update(n.lower() for n in RE_CRIA.findall(sql.read_text(encoding="utf-8", errors="replace")))
    return projetos, sorted(tabelas)


def pergunta(url, chave, nome):
    """(situacao, linhas_visiveis) sem baixar nenhuma linha (HEAD + contagem)"""
    req = urllib.request.Request(
        f"{url}/rest/v1/{nome}?select=*&limit=1", method="HEAD",
        headers={"apikey": chave, "Authorization": f"Bearer {chave}", "Prefer": "count=exact"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            faixa = r.headers.get("Content-Range", "")
            status = r.status
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return "fechado (acesso negado)", 0
        if e.code in (404, 406):
            return "nao existe", 0
        return f"erro {e.code} (consulta lenta ou recusada; nenhuma linha devolvida)", 0
    except (urllib.error.URLError, TimeoutError) as e:
        return f"sem resposta ({getattr(e, 'reason', e)})", 0
    total = faixa.rsplit("/", 1)[-1]
    if total.isdigit() and int(total) > 0 and not faixa.startswith("*"):
        return "ABERTO", int(total)
    return "fechado (RLS devolve vazio)", 0


def main():
    projetos, tabelas = projetos_e_tabelas()
    if not projetos:
        print("Nao achei a chave publica nos apps.")
        return 2
    abertos = []
    for url, chave in projetos.items():
        print(f"\nProjeto {url.split('//')[1].split('.')[0]}  ({len(tabelas)} objetos conferidos)")
        for nome in tabelas:
            situacao, linhas = pergunta(url, chave, nome)
            if situacao == "nao existe":
                continue
            if linhas:
                abertos.append((url, nome, linhas))
            marca = "  !!" if linhas else "    "
            extra = f" - {linhas} linhas visiveis" if linhas else ""
            print(f"{marca} {nome:28s} {situacao}{extra}")
    print()
    if abertos:
        print(f"ATENCAO: {len(abertos)} objeto(s) legivel(is) por qualquer pessoa com a chave publica:")
        for url, nome, linhas in abertos:
            print(f"  - {nome} ({linhas} linhas)")
        print("Feche com: revoke all on public.<nome> from anon, public;  (ver seguranca_01_...sql)")
        return 1
    print("Nenhum objeto devolve linhas para a chave publica.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
