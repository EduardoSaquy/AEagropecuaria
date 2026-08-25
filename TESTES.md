# Testes

Os arquivos `teste_*.py` (Playwright + pytest, contra os `.html` de verdade,
sem precisar de Supabase real) foram **reconstruídos do zero**. Os originais
— 80 testes ao todo, segundo o CLAUDE.md — não existem em nenhum commit do
histórico do repo, então sumiram antes de qualquer coisa ser versionada. O
que está aqui é bem menor (14 testes) e cobre principalmente as armadilhas
documentadas no CLAUDE.md, não uma recriação completa da suíte antiga.

Rodei os 14 numa instalação limpa (Windows, sem Python nem Playwright antes)
e todos passam. `pytest.ini` existe porque o pytest não reconhece `teste_*.py`
como nome de teste por padrão (o padrão dele é `test_*.py`) — sem ele, a
suíte inteira é ignorada silenciosamente, "0 items collected".

## Instalar (uma vez)

```bash
winget install Python.Python.3.12
```

Feche e reabra o terminal depois de instalar (o PATH só atualiza numa sessão
nova), depois:

```bash
cd "C:/Users/W10/OneDrive/Documentos/AEagropecuaria"
pip install -r requirements.txt
playwright install chromium
```

(`requirements.txt` inclui `tzdata` para Windows — sem ele, `zoneinfo`
não acha `America/Sao_Paulo` e a suíte inteira falha na coleta.)

## Rodar

```bash
cd "C:/Users/W10/OneDrive/Documentos/AEagropecuaria"
pytest -v
```

Precisa de internet: os apps carregam a biblioteca do Supabase de um CDN
antes do próprio código.

## O que cada arquivo cobre

- `teste_matriz.py` (7) — independência de `mes`/`data`, agrupamento de
  recorrentes em `vigentesNoMes` (chave com fazenda+área) e `hojeStr()` não
  avançar o dia à noite no Brasil. As três já estão corrigidas no código
  atual — os testes existem só pra não deixar regredir.
- `teste_paginacao.py` (2) — as duas variantes de `fetchAllRows` que existem
  hoje (a do AEMatriz, que recebe a consulta pronta, e a do Cana/Cereais,
  que recebe nome da tabela) realmente paginam além de 1000 linhas em vez de
  truncar. A do Cana/Cereais mocka a API REST do Supabase via `page.route` —
  essa versão do supabase-js pagina com `?offset=N&limit=1000` na URL, não
  com header `Range`.
- `teste_apps_lavoura.py` (5) — os links do redirecionamento do AELavoura
  levam pro app certo, e Cana/Cereais apontam pro projeto Supabase unificado
  (`kmkystqgpvmzrccxvyaz`), não pro antigo da Pecuária.

## O que ficou faltando

Os formulários de cada app (talhão, aplicação, lançamento, dieta etc.) não
têm teste de UI aqui — teria exigido simular login/sessão sem eu conseguir
ver o app rodando pra confirmar os seletores certos. `manter()` (o helper que
evita apagar campo em update parcial) já existe e está corretamente aplicado
em `AEpecuaria.html` (`pesagemToRow`, `diagnosticoToRow` etc., no campo
`manejo_id`) — não escrevi teste pra ele ainda, mas não é uma lacuna aberta
como cheguei a achar antes.

Se quiser fechar a lacuna dos 80 testes originais, a forma mais segura é ir
gravando um teste por bug que aparecer daqui pra frente (regressão), em vez
de tentar adivinhar de uma vez os 44+34 que existiam antes.
