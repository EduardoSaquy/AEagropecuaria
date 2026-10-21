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
| `AECombustivel.html` | controle de diesel/Arla/gasolina das três frentes. Rateio por talhão/área — sem centro de custo, sem entrar em `lancamentos_financeiros` (controle próprio, por ora) |
| `Adubacao.html` | calculadora de calagem/gessagem/adubação, sem Supabase e sem login (sessão única) |
| `AELavoura.html` | página de redirecionamento para Cana/Cereais (o app antigo foi dividido) |
| `sw.js` | service worker único de todos os apps (cache `ae-v5`). Página do site: rede primeiro (revalida sempre, cai pro cache após 4 s sem resposta **ou se o site responder erro, 404/5xx**: com o GitHub Pages fora do ar quem já usa o app continua abrindo) e atualiza o cache a cada abertura online; CDN do Supabase e fontes: cache primeiro. Sem a biblioteca do Supabase no cache o app não abre offline — foi o bug até a v4 |
| `gerar_apps_lavoura.py` | gera AECana e AECereais a partir de `AELavoura_app_completo.html.bak` |

Cana e Cereais são propositalmente separados: ficam em estados diferentes do
país e a operação é independente. Não voltar a unificá-los.

## Banco

Projeto Supabase único (`kmkystqgpvmzrccxvyaz`) para Matriz, Pecuária, Cana,
Cereais **e, desde 29/08/2026, Combustível também** — o plano original era
projeto próprio e separado pro Combustível, mas o Supabase free limita a 2
projetos ativos, então o Eduardo decidiu integrar ao unificado em vez de
duplicar cadastro (`fazendas`/`talhoes_areas`/`centros_custo`/`culturas`/
`safras`/`funcionarios` já existentes). Ver `combustivel_unificado_01_
schema.sql`/`_02_libera_geo_para_combustivel.sql`/`_03_remover_centro_
custo.sql`/`_04_abastecimento_no_posto.sql`/`_05_operador_vira_
funcionario.sql`. Combustível **não** grava em `lancamentos_financeiros`
— fica como controle próprio (litros, rateio por talhão/área), à parte do
financeiro, por ora.

**Confirmado em produção em 30/08/2026** (rodados nesta ordem pelo
Eduardo): abastecimento não tem mais centro de custo (só talhão/área,
opcional), "Operador" não é mais um cadastro próprio com CPF — lista os
`funcionarios` do Matriz (exceto cargo "Administrativo"), e a origem do
abastecimento virou Fazenda (resolve o tanque dela — só existe um por
fazenda) ou "Posto de gasolina" (sem tanque, sem desconto de estoque).
A tabela `operadores` foi apagada.

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
| nula | preenchido | competência mensal histórica (importação ERP) |

Derivar `mes` de `data` (ou vice-versa) corrompe os dados. Já aconteceu: um mês
de R$ 43.928,73 virou R$ 1.230.390,69.

`lancamentoToRow` preserva isso com
`mes: l.data ? l.data.slice(0,7) : (l.mes || null)`. Não "simplifique".

### Lançamento "geral" pode estar rateado — leia de `lancamentos_rateados`, não da tabela

Um `lancamento_financeiro` sem atividade própria (`atividade='geral'`) pode
ter o valor repartido entre atividades/fazendas em `lancamento_rateios`
(criado pela importação do ERP: 791 títulos "geral de uma fazenda" e 2.526
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
importação do ERP pra Cana/Pecuária a partir de jan/2026 — ver "O import
do ERP duplicou Cana e Pecuária de jan/2026 em diante", mais abaixo.

Esse ponto ficou destampado até 28/08/2026: `carregarResultadoCana/Cereais/
Pecuaria` (AEMatriz.html) e o Financeiro só-leitura do AEpecuaria.html liam
direto de `lancamentos_financeiros`, então a fatia rateada de um custo
"geral" nunca aparecia no Resultado de nenhuma atividade — a despesa da
Cana, por exemplo, saía menor do que o ERP mostrava pra mesma atividade.
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
seguindo o DFC do ERP. 63 centros, 7 grupos, sem duplicados — há índice único
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

A importação do ERP (`erp_dashboard_2_depois_do_csv.sql`) pisou nessa
regra em 28/08/2026: o insert original marcava `tipo='despesa'` para os
9.400 títulos sem olhar pra que conta cada um caía, inclusive os 75 de
"AMORTIZAÇÃO DE FINANCIAMENTO" (R$ 17,8 milhões — desembolso de principal,
não é despesa) e os 337 de compra de máquina/terra/matriz/infraestrutura
(R$ 7,2 milhões — deveriam ser `tipo='investimento'`). Corrigido: amortização
de financiamento fica de fora do import (não vira lançamento nenhum), e conta
que cai no grupo `INVESTIMENTOS` do plano do ERP vira `tipo='investimento'`.
O `erp_dashboard_4_corrigir_producao.sql` refaz o import já feito sem
precisar recarregar o CSV. Cana e Grãos **não** tiveram esse problema — o
CSV já traz `atividade` separado certo (1.762 cana, 1.689 graos).

### O import do ERP duplicou Cana e Pecuária de jan/2026 em diante

A Cana só passou a ser lançada à mão no app a partir de janeiro/2026 (a
Pecuária, em volume, também — antes disso só existia um lançamento
recorrente isolado por mês). A importação do ERP cobre até agosto/2026,
sem excluir esse período: de jan/2026 a ago/2026, a mesma despesa real
ficava lançada duas vezes — uma vez à mão, outra vez pelo ERP, cada
uma com o campo `fornecedor` escrito diferente (por isso um `join` exato
por fornecedor não encontrava o par; só bateu comparando total por mês).
Confirmado dia 28/08/2026 e corrigido com
`erp_dashboard_6_remover_duplicidade.sql`: apagou a despesa **do ERP**
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
  despesa, manteve a versão **do ERP** e apagou a lançada à mão (sem
  problema, o total bate igual). A Pecuária só foi fechada depois, com
  `pecuaria_receita_remove_duplicidade_2026.sql` (mantendo a lançada à mão,
  apagando a do ERP, mesmo critério da despesa) — receita 2026 da
  Pecuária caiu de R$ 4.399.776,43 pra R$ 3.378.658,50.
- **Investimento**: dos 7 títulos do ERP em 2026 (Pecuária, ~R$ 463 mil),
  4 batiam exato (valor e mês) com lançamento manual — duplicidade de
  verdade, fechada com `pecuaria_investimento_remove_duplicidade_2026.sql`
  (R$ 252.724,71). Os outros 3 (dois de Renato Mendes Camargo em jan, que
  parecem uma compra parcelada, e um de Alemar Rodrigues em ago) não
  tinham par exato — confirmados como investimento novo, ficaram intocados.

**Cuidado ao reusar os scripts de dedup de Cana/receita 2026**: como a Cana
manteve a versão do ERP (ao contrário de despesa/Pecuária, que mantiveram
a versão manual), um script que apague `erp_id is not null` pra Cana em
2026 hoje apagaria a receita inteira da Cana por engano — os arquivos
antigos que faziam isso (`erp_receita_02/03_...`) foram removidos do
repositório por causa disso.

**Se algum dia reimportar ou expandir o CSV do ERP**: nunca deixar
título de Cana ou Pecuária com competência (`mes`) a partir de 2026-01
entrar de novo sem checar contra o que já foi lançado à mão primeiro.

### O custo da Pecuária NÃO se divide por categoria de venda

As despesas fixas (mão de obra, energia, manutenção…) são 81% do custo da
Pecuária em 2026 (R$ 1,57 mi de R$ 1,93 mi) e 100% dos lançamentos estão como
"Geral" (sem área); só ração e pasto (19%) vêm marcados por lote/área, e mesmo
essas são do rebanho inteiro. Dividir a despesa total pelas @ de uma categoria
(bezerro/abate) cobrava o custo de tudo de uma categoria só e mostrou
**-400% de lucro/@ numa atividade com +24% de margem** (14/10/2026). Em
Resultados > Operacional a Pecuária é um card só, `resumoPecuariaNoPeriodo()`:
resultado da atividade toda; a categoria entra só com cabeças, @ e receita.
Se um dia as despesas fixas passarem a ser marcadas por área (Cria vs
Confinamento), aí sim dá pra repartir o custo — hoje não.

- A unidade comum a toda venda é a **cabeça** (toda venda registra quantos
  animais saíram). Venda por cabeça não tem peso: entra em cabeças, nunca "fica
  de fora". A @ só existe nas vendas com peso.
- Custo e receita por cabeça só aparecem quando ≥ 98% da receita do período tem
  venda registrada (`abate_id`). Receita antiga de "Venda de gado…" sem nº de
  animais e o excedente de milho não têm cabeças; sem essa regra o R$/cab sai
  inflado.
- A venda de milho **é receita da Pecuária de propósito**: ela compra o milho
  da lavoura e revende a sobra. Não reclassificar.

### Ganho de peso (GMD) é boi a boi, não pela média do lote

Pedido do Eduardo em 21/10/2026. O GMD pela média (peso médio de agora −
peso médio da pesagem anterior do lote) compara grupos diferentes quando o
curral é apartado: o Curral 2 mostrava +0,22 kg/dia (108 bois antes, 62
depois) e o ganho real, dos 59 bois presentes nas duas, era +1,02. Quando a
pesagem tem peso por animal, `gmdDesdeAnterior`/`ganhoDoLoteNaJanela`
(AEpecuaria.html) calculam com o **mesmo animal** nas duas pesagens,
procurado em qualquer lote do mesmo tipo (`indicePesosIndividuais`: o boi
apartado leva o histórico; a vaca com o mesmo número fica de fora por estar
em lote de Cria). Número repetido na mesma pesagem é ambíguo e não entra.
Sem peso por animal, volta pela média. Vale para "GMD desde a anterior",
Painel de Resultado dos Lotes, @ produzidas/Custo/@ (ganho = GMD × dias) e
o GMD de cada animal no detalhe do lote. A tela diz qual método usou.
`teste_gmd_boi_a_boi.py`.

### Contas a Pagar/Receber: conta repetida e baixa em lote

Pedidos do Eduardo em 21/10/2026 (AEMatriz.html):
- **Não deixa lançar a mesma conta duas vezes** (`tituloRepetido`): mesmo
  tipo, mesmo fornecedor, mesmo valor (centavos) e mesmo vencimento, em título
  não cancelado, pago ou em aberto. A descrição fica de fora de propósito (a
  mesma conta costuma vir escrita diferente). Em lançamento parcelado, se uma
  parcela repete, nenhuma é gravada. É regra da tela, não do banco.
- **Baixa em lote**: caixa de seleção em cada conta baixável
  (`tituloBaixavel`: saldo > 0, não cancelada, com rateio), "marcar todas" da
  lista filtrada e o modal `baixaLote` (data do vencimento de cada conta ou
  uma data para todas). Quita o saldo inteiro de cada uma num **insert só** em
  `titulo_baixas`: o banco aceita todas ou nenhuma, e o gatilho
  `trg_baixa_gera_lancamento` cria os lançamentos como na baixa individual.
  Baixa parcial continua uma a uma. `teste_contas_lote.py`.

### Resultados > Empresa: a empresa como uma atividade só

Fluxo de caixa em 3 blocos, juros por ano e por ano-safra, cobertura de juros
e dívida (Fase 1 em 14/10/2026). Fase 2 em 15/10/2026: dívida no tempo
(vencimentos em 12 meses x depois, por ano e por ano-safra; taxa média dos
contratos; saldo médio e custo médio da dívida).

**Conta bancária e saldo em conta: o Eduardo NÃO coloca no app** ("não é
seguro", 15/10/2026). Não proponha caixa real por conta, saldo inicial por
conta nem peça agência/conta/saldo. O fluxo de caixa da aba é a variação do
período calculada pelos lançamentos, sem saldo bancário; no Pagar/Receber o
campo "Conta bancária" é opcional ("— Não informada —") e assim deve ficar. O
que ainda poderia vir sem nenhum dado bancário (só se ele pedir): liquidez com
contas a pagar/receber e um balanço simplificado. O balancete por centro de
custo já existe em Resultados > Relatórios.

- Base: `lancamentos_financeiros` **direto** (`state.lancamentos`, a empresa
  inteira, sem ratear) + `movimentos_financiamento` + o módulo Financiamentos.
  **Não lê `lancamentos_rateados`**: para a empresa toda não há o que repartir,
  e em 14/10/2026 a visão rateada estava **R$ 645 mil abaixo** do Financeiro em
  2026 (de 2023 a abril/2026 bate centavo por centavo; de maio/2026 em diante
  os custos "geral" chegam às atividades só pela metade, de R$ 38 mil a R$ 170
  mil por mês). Relatórios, Geral e Operacional leem a visão e herdam o buraco;
  a aba Empresa avisa a diferença do período. Diagnóstico:
  `rateio_confere_soma_das_partes.sql`. Os totais também diferem de
  Geral/Operacional porque estas usam o custo de cada app (ração e pasto
  consumidos).
- O bloco de cada linha vem do **grupo** do plano de contas
  (`blocoDfcDoGrupo`). Juros e despesas financeiras estão no grupo
  FINANCIAMENTOS, então "Resultado operacional" já sai antes dos juros. "Juros
  pagos" são dois centros, achados **pelo nome** (`CENTROS_JUROS_EMPRESA`):
  renomear um deles zera os juros da tela (o teste pega).
- Amortização e entrada de empréstimo **nunca** viram `lancamentos_financeiros`
  (não são despesa nem receita): moram em `movimentos_financiamento` (import
  do ERP: 75 títulos, R$ 17,8 mi, `financiamentos_02_movimentos_erp.sql`) e
  no módulo Financiamentos. O juros das parcelas pagas do módulo **já é**
  lançamento: não somar de novo. Contrato nascido de renegociação não é
  dinheiro novo. Movimento com data futura é dívida a vencer, não fluxo
  realizado.
- **Contrato que já está no ERP: lance por "Lançar contrato", nunca à mão.**
  Em Financiamentos, a lista "Dívida do ERP ainda sem contrato"
  (`gruposErpParaLancar`) tem um botão por contrato (credor + apelido do contrato;
  linha sem número se separa pelo valor da parcela; contrato todo pago não
  aparece, o histórico dele já está no ERP). O botão cria o financiamento
  com **uma parcela por linha do ERP** (`parcelasDoGrupoErp`: datas e
  valores reais, inclusive anuais e crescentes, que o gerador SAC/Price não
  reproduz) e grava `financiamento_id` em cada linha. Linha com esse vínculo
  **não conta mais** no ERP (`movimentoAssumidoPorContrato`; contrato
  cancelado devolve a linha): a dívida da aba Empresa é saldo dos contratos +
  o que só está no ERP, e a amortização paga entra uma vez só, pela parcela.
  Ninguém apaga linha do ERP (rodar o script de novo seria desfazer o
  apagamento; o vínculo sobrevive, `on conflict do update set contrato`).
  Por que não casar contrato digitado à mão com as linhas: o ERP só traz o
  contrato em 67 dos 75 títulos e os valores reais não batem com o
  que o gerador calcula. Se alguém lançar à mão um contrato que está no ERP, a
  dívida dobra (o modal avisa).
  - Parcelas já pagas do contrato importado entram **pagas e sem juros**: o
    juros delas já é lançamento do ERP (lançar de novo dobraria a despesa, e
    `pagarParcela` lança com a data de hoje, não a do pagamento). As a vencer
    ficam pendentes com juros **estimado** pela taxa informada (o ERP não tem
    juros futuro).
  - Contrato importado (`observacao` começa com "Importado do ERP",
    `importadoDoErp`) **nunca regera o cronograma**: o "Editar" dele
    (`_travado`) mexe só em finalidade, atividade, data, taxa, fazenda, garantia
    e observação; mudar taxa ou data refaz só o juros **estimado** das parcelas
    em aberto (`reestimarJurosPendentes`). Não conta como empréstimo recebido
    (data aproximada, valor = só o que o ERP viu pagar). A data do contrato é
    **estimada** (`inicioEstimadoErp`: 1ª parcela menos o intervalo mediano entre
    parcelas; 365 dias se só tem uma) e o mesmo cálculo alimenta a linha do tempo
    da dívida antes e depois de lançar, então lançar não muda o saldo médio.
    `sistema_amortizacao` fica 'sac' só porque o banco exige um dos 3.
  - **Ajustar depois de lançar** (pedido do Eduardo: "se já foi amortizado eu apago
    ou edito"), na tela do contrato: **Registrar pagamento** (data e juros reais;
    o juros só vira despesa, na data do pagamento, se a caixa estiver marcada),
    **Editar** parcela (vencimento e juros; a amortização só no importado, e aí o
    saldo de cada parcela e o principal se refazem), **Quitar** (todas as parcelas
    em aberto pagas numa data, sem juros), **Cancelar contrato** (só muda o
    status; as linhas do ERP voltam; não cancela se alguma parcela já virou
    lançamento no Financeiro). Nada apaga histórico.
  - O contrato "sem número" do Banco do Brasil (4 parcelas de R$ 456.737,72) tem
    duas parcelas em 15/08/2029 e nenhuma em 2028 no ERP: provável erro de
    digitação de lá; o total fecha, só o vencimento do meio sai errado.
  - Lançar parcela antiga como "paga" em contrato digitado à mão também
    duplicaria o juros (já está no ERP).
- O ERP **não tem entrada de empréstimo**, só amortização: sem ela, a
  cobertura do serviço da dívida sai pior que a realidade.
- **Dívida no tempo** (`vencimentosDaDivida`, `taxaMediaContratos`,
  `linhaDoTempoDivida`, `saldoMedioDivida`): vencimentos juntam as parcelas em
  aberto dos contratos ativos (com o juros estimado) e as linhas do ERP que
  nenhum contrato assumiu (só principal); "12 meses" = até hoje + 12 meses. A
  taxa média dos contratos é a **contratada**, ponderada pelo saldo. O **custo
  médio** (juros pagos ÷ saldo médio) é só um indicador: o saldo médio é
  estimado (linha do ERP solta tem data de contrato estimada, dívida quitada
  antes de 2023 não existe) e **período em andamento não tem custo médio**
  (os juros dele ainda estão incompletos; em 15/10/2026 os de 2026 eram R$ 46 mil
  porque os contratos ainda não estavam lançados). Com o ERP de 2023 a 2025
  o custo médio estimado deu 9,6%, 13,8% e 9,8% a.a.
  `teste_divida_empresa.py` confere cada conta à mão.
- O plano tem o mesmo grupo escrito de dois jeitos (`VARIACOES…`/`VARIAÇÕES…`);
  `blocoDfcDoGrupo` normaliza acento. "BANCO DO BRASIL" e "BANCO BRASIL" eram o
  mesmo credor: o script unifica.
- **Sem rolar de lado** (pedido do Eduardo). A tabela do histórico tem 9
  colunas (~980 px só da tabela) e, com título em linha única, passava do card.
  Classes: `tabela-cabecalho-quebra` (título quebra em 2 linhas) e
  `tabela-em-blocos` (até 1060 px cada linha vira um bloco, com o nome da coluna
  vindo de `data-rotulo` em cada `<td>`; a linha de seção leva `linha-secao`;
  células de botões levam `acoes`). Tabela nova com mais de 5 colunas usa as
  duas: confira a largura mínima dela (min-content) antes de escolher o ponto de
  corte. A barra de abas de Resultados (4
  botões, 361 px) passava da tela de celular e a página inteira rolava de lado:
  leva `periodo-tabs-ajusta` (ocupa a largura toda, botões dividem o espaço);
  ao acrescentar outra aba, rode o teste. `teste_empresa.py` mede em 1280,
  1100, 1000, 800, 390, 376, 360 e 320 px se algo passa da coluna central. Compare
  com `documentElement.clientWidth`, não com `innerWidth` (que inclui a barra
  de rolagem do Windows e escondeu 16 px de sobra).

## Armadilhas que já custaram caro

- **O repositório é PÚBLICO: nada de dado sensível em arquivo versionado.**
  CPF/CNPJ, número de conta bancária, número de contrato/cédula, número de
  documento/nota do ERP (o "doc" mais um número, que as cargas antigas punham na descrição) e o razão por fornecedor **nunca** entram no
  git (o Eduardo mandou, em 15/10/2026: "qualquer referência a número de
  documento ou conta bancária, apague ou troque o nome"). Os dumps do ERP e as
  cargas antigas de dados ficam só no computador, em `AEagropecuaria_dados_privados`
  (pasta irmã, fora do git; também no `.gitignore`). Script ou teste novo usa
  número inventado e apelido, nunca o real. `teste_sem_dados_sensiveis.py`
  varre tudo que o git rastreia e falha se achar CPF/CNPJ válido, número de documento na descrição,
  "BANCO + número de conta" ou arquivo de dump versionado. No banco, o contrato
  do ERP vira apelido C01, C02... (`financiamentos_02_movimentos_erp.sql`;
  `financiamentos_03_apelidos_contratos.sql` troca os números reais que já
  tivessem sido gravados).
  O repositório foi **recriado em 16/10/2026** com o histórico filtrado (os
  números reais já tinham ido parar nos commits antigos e em mais de 100 pull
  requests, que o GitHub não deixa apagar): o antigo ficou **privado** como
  `AEagropecuaria-antigo` (só o Eduardo acessa), o novo tem só a `main` e os
  mesmos endereços do site. Sessão na nuvem (claude.ai/code) pode precisar que
  o Eduardo dê acesso ao repositório novo ao app do Claude no GitHub.

- **O nome do ERP de origem não aparece em lugar nenhum.** O Eduardo, em
  16/10/2026: "o nome ... aparece em tudo, não é para aparecer". Nem na tela,
  nem no banco, nem em arquivo, nem em nome de arquivo: no texto, no código e
  nas colunas ele é só "ERP" (`erp_id`, `erp_plano_contas`, "Dívida do ERP ainda
  sem contrato"). `teste_sem_nome_do_erp.py` varre todo arquivo versionado e o
  nome de cada um; script que precisa citar o nome antigo (para renomear algo no
  banco) o monta por pedaços (`'con' || 'ag'`), como `erp_20_...sql`.
  - **Fornecedor que tem esse nome no cadastro é fornecedor de verdade** (52
    lançamentos e 1 entidade em 16/10/2026, escritos em MAIÚSCULAS no banco):
    não renomear. A troca mexe só no que o sistema escreveu sozinho:
    `criado_por`, a observação "ERP 12345 - Boleto" e a descrição das cargas.
    (Cuidado ao contar: a view `lancamentos_rateados` repete o lançamento
    rateado em várias linhas; a conta certa é na tabela.)
  - Contrato importado é reconhecido por `OBS_IMPORTADO`
    (`/^Importado do \S+ \(contrato /`): contrato lançado antes da troca guarda
    o nome antigo no texto e continua valendo. `movimentos_financiamento.origem`
    só é comparada com `'manual'`, então o app funciona antes e depois de o SQL
    do banco rodar.
  - Banco: `erp_20_tira_o_nome_antigo_do_banco.sql` renomeia colunas, índices,
    tabelas, textos e comentários (o script para sem mudar nada se achar função
    do banco citando o nome antigo; desliga o registro de alterações só durante
    a troca em massa, senão ele gravaria uma linha por lançamento) e
    `erp_21_confere_o_que_sobrou.sql` lista o que ainda tem o nome (esperado:
    só os fornecedores reais e o histórico de `log_alteracoes`). Rodaram de
    verdade num Postgres descartável (banco montado como o de produção antes da
    troca; `ensaio_sql_banco.py`) antes de irem para o Eduardo.
  - A conferência na produção achou o que o `erp_20` deixou: observações com o
    nome no MEIO do texto ("Importado da <nome> (soma dos funcionarios...)", 44
    lançamentos; o `erp_20` só trocava as que começavam com o nome), a tabela
    antiga `custos_fixos` (nome e observação; é da Pecuária antiga, já migrada
    para `lancamentos_financeiros`, sem uso no app) e a tabela de pouso do CSV, que
    ficou porque a trava de "9 mil lançamentos importados" era alta demais
    (a duplicidade de 2026 apagou ~900; a trava agora é 5 mil). Quem arremata é
    `erp_22_arremata_o_que_sobrou.sql` (termina com a mesma conferência do
    `erp_21`). `custos_fixos.nome` precisa ficar igual à descrição dos
    lançamentos migrados, por isso troca junto. O histórico de alterações
    (`log_alteracoes`) guarda o nome nas cópias antigas e não se reescreve.
  - **Feito na produção em 16/10/2026** (`erp_20` e depois `erp_22`, rodados
    pelo Eduardo). Conferência final: só sobraram `entidades.nome` (1),
    `lancamentos_financeiros.fornecedor` (52) e `.descricao` (51), que são
    fornecedores de verdade, e `log_alteracoes.antes/depois`. Nenhuma tabela,
    coluna, índice, trava, função ou comentário com o nome.
  - O histórico do git (commits antigos) ainda guarda o nome em arquivos e
    mensagens; só some recriando o repositório de novo.

- **Offline com login vencido.** O token do Supabase vale 1 h; vencido e
  sem rede, `db.auth.getSession()` fica ~25 s tentando renovar e depois
  devolve "sem sessão" (medido com supabase-js 2.117 em 13/10/2026). Por
  isso todo app abre com `sessaoInicial()` (sessão guardada no aparelho se
  a biblioteca demorar ou não houver rede) e `buscarPerfilDoBanco()` (último
  perfil conhecido). Nunca voltar a `await db.auth.getSession()` direto no
  `initAuth`.

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

28 arquivos `teste_*.py`, 696 checagens (21/10/2026; a tabela abaixo lista os
principais, `ls teste_*.py` é a lista completa). Rodam com Playwright + Python
contra um stub do Supabase (`teste_stub_supabase.js` — `insert`/`update`/`delete`
gravam de verdade em `window.__DB__`). Neste notebook, 5 checagens de tempo de
`teste_offline.py` ("offline com login vencido: abre em menos de 3 s") falham, e
falhavam igual no código publicado antes: é a máquina, não regressão.

| Arquivo | Testes | Cobre |
|---|---|---|
| `teste_apps_lavoura.py` | 44 | AECana.html, AECereais.html |
| `teste_matriz.py` | 32 | AEMatriz.html |
| `teste_paginacao.py` | 2 | AEMatriz.html, AEpecuaria.html |
| `teste_financiamentos.py` | 35 | AEMatriz.html |
| `teste_venda.py` | 28 | AEMatriz.html |
| `teste_unidade.py` | 31 | AEMatriz.html |
| `teste_exclusao.py` | 20 | AEMatriz.html, AEpecuaria.html, AECana.html, AECereais.html |
| `teste_lote_racao.py` | 15 | AEpecuaria.html |
| `teste_cereais_cultura.py` | 27 | AECereais.html |
| `teste_contas.py` | 83 | AEMatriz.html |
| `teste_offline.py` | 24 | sw.js (offline dos 5 apps), abertura offline com login vencido, botão ← Painel, cards do Painel na mesma janela |
| `teste_resultado_por_unidade_drilldown.py` | 51 | AEMatriz.html (Resultados > Operacional: por unidade produzida, Pecuária como atividade toda) |
| `teste_empresa.py` | 63 | AEMatriz.html (Resultados > Empresa: fluxo de caixa em 3 blocos, juros por ano e safra, cobertura, dívida, linha do ERP assumida por contrato, sem rolar de lado de 1280 a 320 px) |
| `teste_divida_empresa.py` | 42 | AEMatriz.html (Empresa, Fase 2: vencimentos em 12 meses/por ano/por safra, taxa média ponderada, saldo e custo médio, lançar contrato não muda o saldo médio) |
| `teste_financiamentos_erp.py` | 40 | AEMatriz.html (Financiamentos > Lançar contrato do ERP: lista, cronograma real, vínculo das linhas, divida sem contar duas vezes, cancelar devolve) |
| `teste_financiamentos_editar.py` | 40 | AEMatriz.html (Financiamentos: registrar pagamento com data/juros reais, editar parcela e contrato, quitar, cancelar; tela do contrato sem rolar de lado) |
| `teste_sem_dados_sensiveis.py` | 14 | todo arquivo versionado (repositório público: sem CPF/CNPJ, número de conta, de contrato ou de documento; sem dumps de dados) |
| `teste_site_fora_do_ar.py` | 12 | sw.js (site respondendo 404/503: o app abre da cópia guardada; endereço nunca guardado continua dando 404; online a versão nova entra na hora) |
| `teste_sem_nome_do_erp.py` | 8 | todo arquivo versionado e o nome de cada um (o nome do ERP de origem não aparece em lugar nenhum) |
| `teste_gmd_boi_a_boi.py` | 7 | AEpecuaria.html (GMD boi a boi: lote apartado, histórico do animal entre currais, vaca com o mesmo número fora, sem peso por animal cai na média) |
| `teste_contas_lote.py` | 18 | AEMatriz.html (Contas: conta repetida bloqueada, inclusive já paga e em parcelado; seleção e baixa em lote com data do vencimento ou data única) |

Não são `teste_*.py` (não entram na rodada normal): `conferir_chave_publica.py`
(pergunta ao banco de verdade, com a chave pública, quantas linhas de cada tabela
e view um estranho consegue ler; precisa de internet) e `ensaio_sql_banco.py`
(roda os SQL de segurança e de troca de nome num Postgres descartável, 141
checagens, entre elas 19 perfis de usuário lendo a view como o PostgREST faz,
com papel `authenticated` e JWT; precisa de um venv com `pgserver` e
`psycopg2-binary`, instruções no topo do arquivo).

Nada ainda cobre `AECombustivel.html`/`Adubacao.html`. **Confirmado em
30/08/2026**: contagem batida arquivo por arquivo (a lista antiga listava só
4 arquivos e 101 testes — ficou pra trás conforme os outros 6 foram
adicionados; achado ao conferir pendências de teste).

Rodar todos antes de entregar qualquer alteração — `ls teste_*.py` primeiro,
não confie de cabeça na lista acima ficar completa. Em sandbox sem rede pra
buscar fonte/CDN externo, espere 2 falhas de `ERR_CONNECTION_RESET` em
`teste_apps_lavoura.py` — é ruído do ambiente, não regressão (o teste já
filtra outros códigos de erro de rede, mas não esse).

## Restrições de segurança permanentes

- **Nunca** guardar CPF, salário ou Pix em tabela com leitura pela chave anônima.
- **View passa por cima do RLS.** Ela roda com os direitos de quem a criou, não
  de quem consulta: tabela com RLS devolve vazio para a chave pública, mas a view
  que lê dela devolve tudo. `lancamentos_rateados` ficou aberta ao "anon" desde
  que foi criada (fim de agosto/2026) até 16/10/2026: 30.043 linhas com valor,
  fornecedor, contrato e CNPJ/CPF de fornecedor, legíveis só com a chave que
  está no código do site (não há como saber se alguém leu). Achada ao conferir o
  banco com a chave pública e fechada pelo Eduardo no mesmo dia com
  `seguranca_01_fecha_view_para_anonimo.sql` (`revoke all ... from anon,
  public`; quem está logado continua lendo), conferida de fora.
  **Toda view nova** leva `revoke all on public.<view> from anon, public;` logo
  depois do `create` (os scripts que criam `lancamentos_rateados` já levam), e
  depois de criar tabela ou view rode `python conferir_chave_publica.py`: ele
  conta as linhas que a chave pública enxerga em cada tabela/view que o código
  usa e em tudo que algum `.sql` do repositório cria (inclusive cópias de
  segurança, que o editor do Supabase cria abertas), sem baixar nada, e sai com
  1 se algo estiver aberto. Em 16/10/2026: 89 nomes testados (75 existem), nenhum
  aberto; depois do `seguranca_03` todos respondem "acesso negado" (antes, as
  tabelas com RLS respondiam vazio).
  - **Quem está logado lê o quê na view**
    (`seguranca_02_view_so_para_quem_tem_permissao.sql`, rodado pelo Eduardo em
    16/10/2026): sem isso todo usuário logado lia o Financeiro inteiro pela
    API, mesmo sem permissão (a tela escondia, o banco não). A view agora filtra
    pela permissão de quem consulta (`auth.uid()` via
    `tem_permissao`): **tudo** para admin/proprietário, `matriz_resultados` e
    `matriz_financeiro`; **só linhas de atividade `pecuaria`** (inclusive a fatia
    rateada de um lançamento "geral") para `pec_financeiro`, `pec_resultados`,
    `vendas`, `confinamento`, `pasto`, `cria`, `lotesGeral` (as telas de Pesagem
    mostram o Custo/@, que soma o custo fixo vindo desta view); **nada** para o
    resto. A regra é a das telas de hoje (quem usa não perde nada).
    - Por que não `security_invoker`: a política da tabela só deixa a Pecuária ver
      linhas de atividade `pecuaria`, mas a fatia de um lançamento "geral" que foi
      rateada para a Pecuária (que a Pecuária precisa ver) só existe na view.
      Com `security_invoker` a Pecuária perderia essa fatia e o custo dela
      sairia menor, em silêncio.
    - A regra mora em `ve_todo_o_financeiro()` e `ve_financeiro_da_pecuaria()`:
      tela nova que leia a view para outro perfil entra ali (um `or` a mais).
      `postgres` e `service_role` passam (os scripts de conferência rodados no
      editor continuam vendo tudo, senão voltariam vazios sem avisar).
    - `aplicar_regra_na_view_lancamentos_rateados()` embrulha a definição que a
      view TEM no banco (`pg_get_viewdef`, sem redigitar coluna). Os scripts que
      recriam a view a chamam no fim, então recriar não desfaz a regra.
    - Se alguém perder uma tela que devia ter: dê a permissão certa em Usuários
      (Resultados ou Financeiro do Matriz, ou o módulo da Pecuária) ou acrescente
      o perfil na função. O script termina com a lista do que cada pessoa passa
      a ver. Em 16/10/2026, 14 pessoas ativas: 6 veem tudo (3 proprietários, o
      admin e 2 colaboradores com Resultados/Financeiro), 5 só a Pecuária e 3
      operadores nada, e nenhuma delas usa tela que dependa da view (conferido
      no código: toda tela que lê a view é protegida por uma dessas permissões).
      Conferido também com os dados reais (30.043 linhas na view, 11.284 de
      Pecuária): cada uma das 14 viu exatamente o que a regra manda.
    - `seguranca_02_confere_como_cada_um_ve.sql` prova isso com os dados reais:
      assume o papel e o código (JWT) de cada pessoa ativa, conta as linhas da view
      que ela enxerga e escreve ok/DIFERENTE ao lado do que a regra manda. Rode
      depois de mexer nas funções ou nas permissões de alguém.
  - **Anon sem acesso a tabela nenhuma**
    (`seguranca_03_anon_sem_acesso_a_tabela.sql`, rodado pelo Eduardo em
    16/10/2026: 0 objetos abertos ao anon, e a conferência de fora mostra as 75
    tabelas e views que existem respondendo "permissão negada"): nenhum app lê
    dado como anon (todos exigem login antes, e o
    login passa pelo serviço de autenticação, não pelas tabelas). O script tira
    todo privilégio do anon em tabelas, views e sequências do schema `public` e
    muda o padrão para o que o editor (postgres) criar daqui para frente, para o
    próximo esquecimento de RLS ou de revoke não abrir nada. Também acaba com a
    consulta anônima cara: `lancamentos_financeiros` pela chave pública
    respondia 500 (estourava os 3 s porque a política era avaliada linha por
    linha; não vazava, mas qualquer um podia disparar). Funções não mudam (as de
    permissão precisam continuar chamáveis). Depois dele, tabela ou view nova que
    o app precise ler só precisa do GRANT para `authenticated` (o padrão do
    Supabase já dá).
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

**SQL só como bloco de código na mensagem, nunca como arquivo anexado
(SendUserFile).** Confirmado em 30/08/2026 — os cartões de arquivo não abrem
no aparelho dele. Cola o SQL direto no texto da resposta, pra ele segurar o
dedo e selecionar tudo.
