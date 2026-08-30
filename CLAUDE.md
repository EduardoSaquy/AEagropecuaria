# AE Agropecuária — contexto do projeto

Família de apps HTML de arquivo único (JS puro + Supabase) que administram uma
operação agropecuária: gado (Pecuária), cana (Cana), grãos (Cereais), combustível
(Combustível), uma calculadora de adubação (Adubação) e um app consolidador
(Matriz). Sem build, sem framework, sem npm. Cada `.html` é o app inteiro e é
aberto direto no navegador ou instalado como PWA.

| Arquivo | O que é |
|---|---|
| `AEMatriz.html` | consolidação: financeiro, centros de custo, financiamentos, usuários, resultados |
| `AEpecuaria.html` | gado: lotes, pesagens, ração, reprodução, abate. Financeiro/Resultados/Fazenda daqui migraram pro Matriz — aqui é só leitura |
| `AECana.html` | cana: talhões, safras, aplicações, colheitas. Sem Financeiro/Resultados próprios (migraram pro Matriz) |
| `AECereais.html` | grãos: mesma estrutura da cana, outra frente |
| `AECombustivel.html` | controle de diesel/Arla/gasolina das três frentes. Código completo mas **ainda com credenciais Supabase placeholder** — nunca foi ligado a um banco real |
| `Adubacao.html` | calculadora de calagem/gessagem/adubação, sem Supabase e sem login (sessão única) |
| `AELavoura.html` | página de redirecionamento para Cana/Cereais (o app antigo foi dividido) |
| `sw.js` | service worker único de todos os apps (cache `ae-v4`) |
| `gerar_apps_lavoura.py` | gera AECana e AECereais a partir de `AELavoura_app_completo.html.bak` |

Cana e Cereais são propositalmente separados: ficam em estados diferentes do
país e a operação é independente. Não voltar a unificá-los.

## Banco

Projeto Supabase único (`kmkystqgpvmzrccxvyaz`) para Matriz, Pecuária, Cana e
Cereais. `AECombustivel.html` é pensado para ter projeto próprio e separado,
mas esse projeto ainda não foi criado — o app está com credenciais placeholder.

O projeto antigo da Pecuária (`leojfqlbdtlriemdgnyw`) tinha leitura anônima em
10 tabelas e a Edge Function `atualizar-permissoes` (que faz UPDATE em
`profiles` com a chave de serviço sem checar quem chamou) publicada lá — órfã
(nenhum app mais chama), mas exposta a quem tivesse a anon key antiga,
recuperável no histórico do git. **Pausado pelo Eduardo em 30/08/2026** —
projeto parado no painel do Supabase, risco fechado.

### Registro de alterações

`log_alteracoes`, ligado por gatilho em `lancamentos_financeiros`, `abates`,
`profiles` e `centros_custo` (`auditoria_05_registro_de_alteracoes.sql`).
Só admin lê, ninguém grava pela API (só o gatilho, `security definer`).
**Confirmado em produção em 29/08/2026** (`pontas_soltas_confere_tudo.sql`):
tabela existe, gatilho `trg_registrar_alteracao` ligado nas 4 tabelas — não
estava no `schema_real.txt` de 22/08, mas está no banco de verdade.

### `lancamentos_financeiros` é a única tabela financeira

Toda despesa, receita e investimento das quatro frentes vive aqui.
Colunas que importam: `tipo` (despesa/receita/investimento), `atividade`
(graos/cana/pecuaria/geral), `fazenda_id` (nulo = Geral), `centro_custo_id`
(NOT NULL), `talhao_id`, `areas text[]`.

**`data` e `mes` são independentes. Nunca derive uma da outra.**

| `data` | `mes` | significado |
|---|---|---|
| preenchida | preenchido | lançamento normal |
| nula | nulo | despesa recorrente, vale todo mês |
| nula | preenchido | competência mensal histórica (importação Conag) |

Derivar `mes` de `data` (ou vice-versa) corrompe os dados. Já aconteceu: um mês
de R$ 43.928,73 virou R$ 1.230.390,69.

`lancamentoToRow` preserva isso com
`mes: l.data ? l.data.slice(0,7) : (l.mes || null)`. Não "simplifique".

### Lançamento "geral" pode estar rateado — leia de `lancamentos_rateados`, não da tabela

Um `lancamento_financeiro` sem atividade própria (`atividade='geral'`) pode
ter o valor repartido entre atividades/fazendas em `lancamento_rateios`
(criado pela importação do Conag: 791 títulos "geral de uma fazenda" e 2.526
"administrativo", ratados pela proporção real de gasto de cada
atividade/fazenda na mesma safra). A tabela `lancamentos_financeiros`
continua com o lançamento inteiro, atividade `'geral'` — quem filtra
`.eq('atividade', 'cana')` direto nela **não vê a fatia rateada**, só os
lançamentos que já nasceram com `atividade='cana'`.

Por isso toda tela que soma despesa/receita por atividade tem que ler da
view `lancamentos_rateados`, não da tabela: ela devolve os lançamentos
diretos inteiros e os rateados já divididos, com a `atividade`/`fazenda_id`
do destino. Chame com `.eq('atividade', X)` do mesmo jeito que antes — só
troca a tabela. A view não tem coluna `id` (é `lancamento_id`; `rateio_id`
distingue as partes de um mesmo lançamento rateado, útil como chave quando
precisa de uma por linha).

**`lancamento_id` não é único na view — `fetchAllRows`/`buscarTudo` precisam
de `.order('lancamento_id').order('rateio_id')`, as duas.** Um lançamento
rateado em várias fazendas gera várias linhas com o mesmo `lancamento_id`;
paginando com `.range()` em blocos de 1000 e só `order('lancamento_id')`,
o Postgres não garante a mesma ordem de desempate entre uma chamada de
página e a próxima — uma linha pode sumir ou duplicar na fronteira. Achado e
corrigido em 28/08/2026, junto com a correção acima: sozinho, num teste local
com Postgres real, isso desviou a soma em ~0,006% (R$ 1.234 num total de
R$ 20,7 milhões) — real, mas não do tamanho da despesa da Cana ter
aparentemente dobrado em produção no mesmo dia. **Essa segunda causa, maior,
foi identificada no mesmo dia**: duplicação entre o lançamento manual e a
importação do Conag pra Cana/Pecuária a partir de jan/2026 — ver "O import
do Conag duplicou Cana e Pecuária de jan/2026 em diante", mais abaixo.

Esse ponto ficou destampado até 28/08/2026: `carregarResultadoCana/Cereais/
Pecuaria` (AEMatriz.html) e o Financeiro só-leitura do AEpecuaria.html liam
direto de `lancamentos_financeiros`, então a fatia rateada de um custo
"geral" nunca aparecia no Resultado de nenhuma atividade — a despesa da
Cana, por exemplo, saía menor do que o Conag mostrava pra mesma atividade.
Corrigido nos quatro pontos. Se abrir uma tela nova que soma financeiro por
atividade, comece por `lancamentos_rateados`.

### A regra do recorrente tem uma implementação só (na intenção — hoje tem duas)

`vigentesNoMes(despesas, mesStr)` no AEMatriz.html. Um recorrente vale no mês
**a menos que** exista lançamento próprio com a mesma chave:
`` `${descricao}||${centroCustoId}||${atividade}||${fazendaId ?? ''}||${areas}` ``
Se precisar da mesma lógica em outro lugar, chame a função. Não reescreva.

`AEpecuaria.html` reimplementa essa regra localmente em `custosFixosDoMes()`
(chave `${nome}||${nomeDoCentro}||pecuaria||${fazendaId}||${areas}` — usa o
*nome* do centro de custo em vez do id, mas dá a mesma partição hoje porque
nome de centro é único). Confirmado equivalente em 25/08/2026, mas é
duplicação frágil: mudar a regra num app sem replicar no outro reintroduz o
bug do R$ 1,2 milhão em silêncio. Se for mexer nessa regra, mexa nos dois.

### `ano_safra`: safra de produção, independente do mês da transação

Campo opcional no formulário de despesa/receita do AEMatriz.html ("Safra"),
coluna `lancamentos_financeiros.ano_safra` (integer, o ano de início da safra
maio-abril — ex.: `2025` = safra 2025/2026). Existe pra resolver o
descasamento apontado pelo Eduardo em 28/08/2026: uma venda pode acontecer
depois do fim da safra que produziu — gado vendido em junho que engordou na
safra passada, grão vendido meses depois da colheita — e nesses casos o mês
da transação (`mes`/`data`) não é o mês da produção. Preenchido, `ano_safra`
diz a qual safra aquele valor pertence de verdade; em branco (`null`, a
maioria dos casos) o lançamento continua contando pelo mês, como sempre foi.

**Não é o mesmo campo que `safra_id`** (também na tabela, mas FK pra
`safras`, que exige `fazenda_id`+`cultura_id` — só serve pra Cana/Grãos, veio
da migração antiga da Lavoura, sem uso hoje). `ano_safra` é livre, serve
qualquer atividade incluindo Pecuária, e é uma criação nova, não um resgate
daquele campo.

**A aba "Safra" do Resultados usa este campo** (`resultadoOperacaoNoPeriodo()`
no AEMatriz.html, via `despesaNaSafra()`/`receitasNaSafra()`): um lançamento
com `mes` dentro da janela maio-abril da safra conta nela A MENOS QUE tenha
`ano_safra` apontando pra outra; um lançamento de fora da janela com
`ano_safra` apontando pra esta safra entra mesmo assim. Só afeta a parte que
vem de `lancamentos_financeiros` — despesa fixa (Pecuária) / despesa geral
(Cana, Cereais) e a receita inteira. Ração, pasto e reprodução da Pecuária
vêm de outras tabelas (`saidas_racao`, `pasto`, `reproducao_custos`), não têm
`ano_safra`, e continuam somadas por calendário dentro da janela — não faz
sentido remarcar custo variável de ração pra outra safra manualmente.
Recorrente (despesa sem `mes`) também não usa `ano_safra`: continua vigente
em toda a janela como sempre foi, via `vigentesNoMes()`.

**As abas Mês e Ano continuam 100% por calendário**, sem olhar `ano_safra` —
são regime de caixa/competência mesmo, de propósito. Só a aba Safra muda de
comportamento.

Depende de duas migrações rodadas nesta ordem: `lancamentos_ano_safra_01_
adicionar_coluna.sql` (cria a coluna) e `lancamentos_rateados_03_ano_safra.sql`
(alarga a view — sem isso o campo fica gravado na tabela mas invisível pros
Resultados, que leem de `lancamentos_rateados`).

### Plano de contas

`centros_custo.tipo` ('entrada'/'saida') e `.subcategoria` ('GRUPO | Subcategoria'),
seguindo o DFC do Conag. 63 centros, 7 grupos, sem duplicados — há índice único
em `lower(nome)` impedindo recriação. Centro de custo é **sempre global**: nunca
amarrar centro a fazenda específica.

### O custo do insumo NÃO entra no resultado

A compra do adubo já é despesa lançada. A aplicação no talhão serve para
**repartir** esse custo entre talhões, nunca para somar ao total. A tela de
Resultados já somou as duas coisas — foi corrigido. Não reintroduzir.

### Financiamentos: só o juros vira despesa

`financiamentos`/`parcelas_financiamento` (`financiamentos_01_criar_modulo.sql`,
tela em AEMatriz.html) são separadas de `lancamentos_financeiros` de propósito.
Receber o empréstimo não é receita (é dívida entrando); pagar a amortização não
é despesa (é dívida saindo) — só o **juros** de cada parcela paga vira um
`lancamento_financeiro` (`tipo:'despesa'`), no centro de custo **"Juros e
Encargos de Financiamento"**. Mesma classe de erro do bug do insumo contado
duas vezes: nunca lançar o valor da parcela inteira nem o desembolso do
principal como despesa/receita.

Financiamento de **capital de giro** não tem uma atividade só: ao marcar a
parcela como paga, o juros vira **3 lançamentos iguais** (Pecuária/Cana/Grãos,
1/3 cada — decisão do Eduardo, mais simples que ratear por hectare).
Investimento/custeio têm atividade única, escolhida no cadastro.

A importação do Conag (`conag_dashboard_2_depois_do_csv.sql`) pisou nessa
regra em 28/08/2026: o insert original marcava `tipo='despesa'` para os
9.400 títulos sem olhar pra que conta cada um caía, inclusive os 75 de
"AMORTIZAÇÃO DE FINANCIAMENTO" (R$ 17,8 milhões — desembolso de principal,
não é despesa) e os 337 de compra de máquina/terra/matriz/infraestrutura
(R$ 7,2 milhões — deveriam ser `tipo='investimento'`). Corrigido: amortização
de financiamento fica de fora do import (não vira lançamento nenhum), e conta
que cai no grupo `INVESTIMENTOS` do plano do Conag vira `tipo='investimento'`.
O `conag_dashboard_4_corrigir_producao.sql` refaz o import já feito sem
precisar recarregar o CSV. Cana e Grãos **não** tiveram esse problema — o
CSV já traz `atividade` separado certo (1.762 cana, 1.689 graos).

### O import do Conag duplicou Cana e Pecuária de jan/2026 em diante

A Cana só passou a ser lançada à mão no app a partir de janeiro/2026 (a
Pecuária, em volume, também — antes disso só existia um lançamento
recorrente isolado por mês). A importação do Conag cobre até agosto/2026,
sem excluir esse período: de jan/2026 a ago/2026, a mesma despesa real
ficava lançada duas vezes — uma vez à mão, outra vez pelo Conag, cada
uma com o campo `fornecedor` escrito diferente (por isso um `join` exato
por fornecedor não encontrava o par; só bateu comparando total por mês).
Confirmado dia 28/08/2026 e corrigido com
`conag_dashboard_6_remover_duplicidade.sql`: apagou a despesa **do Conag**
de Cana/Pecuária a partir de jan/2026 (~R$ 2,51 milhões / 467 títulos de
Cana, ~R$ 1,02 milhão / 436 títulos de Pecuária), mantendo a lançada à mão
— decisão do Eduardo, porque é o registro nativo do time. Grãos nunca teve
lançamento à mão, então não tinha esse risco.

O mesmo padrão apareceu em **receita** e em **investimento**, achado e
fechado em 29/08/2026:

- **Receita**: a Cana em 2026 estava 100% duplicada (5 títulos), a Pecuária
  parcialmente (mar/mai/jun/ago, 10 títulos / R$ 1.021.117,93 — jan/fev eram
  venda nova, sem duplicidade; jul ficou de fora, a soma não batia exato).
  O Eduardo resolveu a Cana manualmente antes — mas ao contrário da
  despesa, manteve a versão **do Conag** e apagou a lançada à mão (sem
  problema, o total bate igual). A Pecuária só foi fechada depois, com
  `pecuaria_receita_remove_duplicidade_2026.sql` (mantendo a lançada à mão,
  apagando a do Conag, mesmo critério da despesa) — receita 2026 da
  Pecuária caiu de R$ 4.399.776,43 pra R$ 3.378.658,50.
- **Investimento**: dos 7 títulos do Conag em 2026 (Pecuária, ~R$ 463 mil),
  4 batiam exato (valor e mês) com lançamento manual — duplicidade de
  verdade, fechada com `pecuaria_investimento_remove_duplicidade_2026.sql`
  (R$ 252.724,71). Os outros 3 (dois de Renato Mendes Camargo em jan, que
  parecem uma compra parcelada, e um de Alemar Rodrigues em ago) não
  tinham par exato — confirmados como investimento novo, ficaram intocados.

**Cuidado ao reusar os scripts de dedup de Cana/receita 2026**: como a Cana
manteve a versão do Conag (ao contrário de despesa/Pecuária, que mantiveram
a versão manual), um script que apague `conag_id is not null` pra Cana em
2026 hoje apagaria a receita inteira da Cana por engano — os arquivos
antigos que faziam isso (`conag_receita_02/03_...`) foram removidos do
repositório por causa disso.

**Se algum dia reimportar ou expandir o CSV do Conag**: nunca deixar
título de Cana ou Pecuária com competência (`mes`) a partir de 2026-01
entrar de novo sem checar contra o que já foi lançado à mão primeiro.

## Armadilhas que já custaram caro

- **Leia o catálogo vivo, não os arquivos de schema.** `cana_schema.sql` e
  `supabase_schema.sql` estão desatualizados e já enganaram quatro vezes.
  `schema_real.txt` é a referência.
- **O Supabase trunca em 1000 linhas sem avisar.** Há 2.759 lançamentos. Toda
  consulta que pode passar de mil linhas usa `fetchAllRows(...)`.
- **Nada de acentos em comentário de SQL.** O separador de statements do editor
  do Supabase não ignora comentários e quebra o arquivo.
- **Uma consulta por arquivo de conferência.** O editor do Supabase mostra
  o resultado de uma consulta por vez. Um arquivo com quatro `select` faz o
  Eduardo mandar sempre o mesmo resultado, sem conseguir chegar nos outros.
  Junte tudo num `union all` com colunas `item / valor / situacao`, e faça
  cada linha dizer `OK` ou o que está errado — não peça para ele comparar
  números de cabeça.
- **Teste o arquivo SQL inteiro de uma vez.** O editor manda tudo como uma
  transação implícita: um erro no fim desfaz o começo. Testar bloco a bloco já
  deixou passar dois erros de sintaxe.
- **Todo script tem guarda de projeto** para não rodar no banco errado:
  `if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then raise exception 'PROJETO ERRADO...'`
- **`hojeStr()` em vez de `toISOString()`.** `toISOString` é UTC e devolve o dia
  seguinte depois das 21h no Brasil.
- **`manter(valor)`** devolve `undefined` quando o campo não veio, o
  `JSON.stringify` some com a chave e o banco preserva a coluna em update
  parcial. Usar em todo `*ToRow` de atualização.
- **Medir antes de afirmar.** Já anunciei impacto que a medição desmentiu.

## Testes

`teste_apps_lavoura.py` (44), `teste_matriz.py` (22), `teste_paginacao.py` (2),
`teste_financiamentos.py` (33). Rodam com Playwright + Python contra um stub
do Supabase (`teste_stub_supabase.js` — `insert`/`update`/`delete` gravam de
verdade em `window.__DB__` desde que o teste de Financiamentos passou a
clicar em "Salvar"/"Marcar como paga" de verdade, não só ler tela). 101
testes. Cobrem `AEMatriz.html`/`AEpecuaria.html`/`AECana.html`/`AECereais.html`,
mas nada ainda de `AECombustivel.html`/`Adubacao.html`.
Rodar todos antes de entregar qualquer alteração. Em sandbox sem rede pra
buscar fonte/CDN externo, espere 2 falhas de `ERR_CONNECTION_RESET` em
`teste_apps_lavoura.py` — é ruído do ambiente, não regressão (o teste já
filtra outros códigos de erro de rede, mas não esse).

## Restrições de segurança permanentes

- **Nunca** guardar CPF, salário ou Pix em tabela com leitura pela chave anônima.
  `AECombustivel.html` grava CPF de operador (`operadores.cpf`) — confirmado
  que a política de select exige `tem_permissao(...)`, que depende de
  `auth.uid()` e por isso não é anônima. Se um dia esse app ganhar qualquer
  policy `using (true)` ou papel `anon`, isso vira violação desta regra.
- `entidades.documento` (AEMatriz.html, pode ter CNPJ/CPF de fornecedor) —
  achado na varredura de 29/08/2026, checado e **resolvido**: RLS ligado,
  as 4 policies (select/insert/update/delete) exigem `is_dono()` ou
  `tem_permissao(...)`, e as duas dependem de `auth.uid()` com curto-circuito
  seguro por `NULL` (sem sessão, `id = auth.uid()` não bate linha nenhuma,
  a policy nunca libera). `documento` está vazio em todos os registros hoje,
  então era risco teórico mesmo antes de confirmar a policy.
- Senha do banco e credenciais são preenchidas pelo Eduardo, nunca pedidas nem
  digitadas pelo assistente.
- Contas de usuário são criadas por ele na tela de Usuários do AE Matriz.

## Como o Eduardo trabalha

Respostas diretas, técnicas, com número e tabela quando couber. Discordar
abertamente quando a premissa dele estiver errada. Não enfeitar. Português do
Brasil.
