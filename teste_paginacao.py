"""Testes da armadilha documentada no CLAUDE.md: 'O Supabase trunca em 1000
linhas sem avisar' -- qualquer consulta que pode passar de mil linhas
precisa paginar com fetchAllRows(...) (ou, no caso do AEpecuaria, pedir um
range explícito grande o bastante).

Reconstrução do zero (o teste_paginacao.py original tinha 2 testes -- mantive
o mesmo tamanho, um por variante de fetchAllRows que existe no código hoje).
"""
import json
from urllib.parse import urlparse, parse_qs

from _test_utils import app_url

CORS = {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "*",
}


def test_fetch_all_rows_matriz_pagina_alem_de_mil(page):
    """AEMatriz.html: fetchAllRows(queryFactory) recebe a consulta pronta e
    deve continuar pedindo páginas de 1000 até a última vir incompleta,
    concatenando tudo. Sem isso, lancamentos_financeiros (~2.759 linhas
    hoje) perde silenciosamente tudo depois da linha 1000."""
    page.goto(app_url("AEMatriz.html"))

    total_fake = 1500
    resultado = page.evaluate(
        """
        async (total) => {
          const todasAsLinhas = Array.from({length: total}, (_, i) => ({id: i}));
          const chamadas = [];
          const queryFactory = () => ({
            range: async (from, to) => {
              chamadas.push([from, to]);
              return { data: todasAsLinhas.slice(from, to + 1), error: null };
            },
          });
          const { data, error } = await fetchAllRows(queryFactory);
          return { total: data.length, erro: error, chamadas };
        }
        """,
        total_fake,
    )

    assert resultado["erro"] is None
    assert resultado["total"] == total_fake, (
        "fetchAllRows devolveu %d linhas de %d -- parece ter parado na "
        "primeira página em vez de continuar paginando"
        % (resultado["total"], total_fake)
    )
    assert len(resultado["chamadas"]) >= 2, "esperava mais de uma página pra 1500 linhas"


def test_fetch_all_rows_cana_pagina_alem_de_mil(page):
    """AECana.html (e AECereais.html, idêntico) já tinha a versão antiga de
    fetchAllRows(table, orderBy, ascending), que fecha sobre `db` em vez de
    receber a consulta pronta. Como `db` é `const` no escopo do próprio
    script, não dá pra trocar por um mock em JS -- então intercepta a
    requisição HTTP real (rota fake, nunca bate no Supabase de verdade).

    O supabase-js dessa versão pagina com `?offset=N&limit=1000` na própria
    URL, não com um header Range (só descobri isso depurando: sem ler
    offset/limit direito, o mock sempre devolvia a página 0 e o app pedia
    página atrás de página pra sempre, sem nunca ver uma página curta pra
    parar -- não era bug do app, era o mock devolvendo o dado errado)."""
    total_fake = 1500
    todas_as_linhas = [{"id": i} for i in range(total_fake)]

    def handler(route):
        request = route.request
        if request.method == "OPTIONS":
            route.fulfill(status=204, headers=CORS)
            return
        query = parse_qs(urlparse(request.url).query)
        offset = int(query.get("offset", ["0"])[0])
        limit = int(query.get("limit", ["1000"])[0])
        pagina = todas_as_linhas[offset:offset + limit]
        route.fulfill(
            status=206,
            content_type="application/json",
            headers={**CORS, "content-range": "%d-%d/%d" % (offset, offset + len(pagina) - 1, total_fake)},
            body=json.dumps(pagina),
        )

    page.route("**/rest/v1/tabela_fake_de_teste*", handler)
    page.goto(app_url("AECana.html"))

    resultado = page.evaluate(
        "async () => { const { data, error } = await fetchAllRows('tabela_fake_de_teste', 'id', true); "
        "return { total: data.length, erro: error }; }"
    )

    assert resultado["erro"] is None
    assert resultado["total"] == total_fake, (
        "fetchAllRows (variante Cana/Cereais) devolveu %d linhas de %d"
        % (resultado["total"], total_fake)
    )
