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
| `core.js` | **núcleo comum** dos cinco apps (Matriz, Pecuária, Cana, Cereais, Combustível): avisos na tela, sessão e perfil guardado no aparelho, ícones, datas e números, `esc`/`fmt`, telas comuns. Carregado por `<script src="core.js?v=...">` antes do script do app. Ver "Núcleo comum dos apps" |
| `core_lavoura.js` | núcleo só do **AE Cana e do AE Cereais** (as funções que os dois tinham idênticas: login, carga de dados, telas de usuários e permissões, cadastros, estoque de insumos) |
| `atualiza_nucleo.py` | troca o `?v=` (impressão digital) das tags `core*.js` nos apps; rodar depois de mexer em `core.js`/`core_lavoura.js`. `--confere` só confere |
| `gerar_apps_lavoura.py` | gera AECana e AECereais a partir de `AELavoura_app_completo.html.bak` |

Cana e Cereais são propositalmente separados: ficam em estados diferentes do
país e a operação é independente. Não voltar a unificá-los.
O que os dois têm de código idêntico mora em `core_lavoura.js` (uma vez só); o que é diferente (tabelas, textos, campos) vem de
constantes que cada app define. Separar a operação não pede código duplicado.

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

**`lancamento_id` não é único na view — `fetchAllRows` (antes `buscarTudo` na Pecuária) precisa
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

### Rateio incompleto da safra 2026/27: achado e correção (05/11/2026)

- **O problema** (aparecia desde 14/10/2026 como "R$ 645 mil abaixo" na aba
  Empresa): 604 lançamentos do ERP (atividade `geral`, competência de mai/2026 a
  abr/2027, importados em 28/08) tinham em `lancamento_rateios` partes que
  somavam só ~22,7% do valor. R$ 979.432,02 (R$ 734.937,23 de despesa e
  R$ 244.494,79 de investimento) não chegavam a atividade nenhuma, e a Cana não
  tinha parte nenhuma. O Financeiro e a aba Empresa estavam certos; Relatórios,
  Geral e Operacional por atividade ficavam com custo a menos. **Causa exata não
  identificada**: o importador sempre fecha o rateio em 100%, `log_alteracoes`
  não mostra edição em nenhum dos 604 e nenhum script do repositório apaga
  partes. Duas falhas do importador também ficaram à vista: a base de proporção
  só contava despesa **com fazenda** (a Pecuária e boa parte da Cana lançadas à
  mão não têm fazenda e ficavam de fora) e somava receita e investimento.
- **Regra de rateio decidida pelo Eduardo (05/11/2026)**, da mais forte para a
  mais fraca, para conta `geral` do ERP sem destino: (1) tem **fazenda**: vai
  para as atividades daquela fazenda (`fazenda_atividades` com área), em partes
  iguais; (2) salário de **funcionário cadastrado**: pela alocação da aba
  Funcionários (`funcionario_atividades`, % por atividade; o cadastro só tem o
  primeiro nome, por isso há um pareamento nome do ERP → id); (2b) pessoa sem
  cadastro: pela atividade que ele informou; (3) centro de custo de uma
  atividade só por natureza (Nutrição animal, Reprodução animal, Compra de
  animais → Pecuária); (4) o resto: **três partes iguais** entre Pecuária, Cana
  e Grãos, a mesma regra do juros de capital de giro. Conta específica de duas
  atividades já nasce com a atividade na hora do lançamento no app e não entra
  nisso.
- **Scripts** (rodados por ele no Supabase, nesta ordem): `rateio_02_diagnostico.sql`
  (acha e classifica, só leitura), `rateio_03_quem_divide_diferente.sql` e
  `rateio_03b_funcionarios_e_alocacao.sql` (listas para decidir),
  `rateio_04_previa.sql` (só leitura: como ficaria, conta por conta),
  `rateio_05_conserto.sql` (tudo ou nada; recusa se não forem exatamente 604
  lançamentos e R$ 979.432,02; guarda as partes antigas em
  `zz_backup_rateio_2026_11_05`, fechada a anon e a quem está logado; **desfazer
  no fim do arquivo**) e `rateio_06_contas_em_tres_partes.sql` (lista as contas que
  ficaram em três partes). A versão com **nomes de pessoas** das listas
  (`de_para`, `regras_nome`) fica só em
  `AEagropecuaria_dados_privados\rateio_2026-11\`: nome de pessoa não entra no
  git. Ensaiados num Postgres descartável com um caso de cada regra, as recusas e
  o desfazer (devolve o banco idêntico).
- **Rodado em 05/11/2026**: das 604 contas, Cana R$ 471.747,11 (37,2%), Grãos
  R$ 334.915,40 (26,4%), Pecuária R$ 461.005,52 (36,4%); 3.534 partes antigas no
  backup; 0 lançamentos com rateio que não fecha; visão rateada = Financeiro
  (diferença R$ 0,00). Ficou como está por decisão dele: o rateio de 2023 a
  abril/2026 (proporção do gasto: Cana 24%, Grãos 44%, Pecuária 32%) não foi
  mexido; FGTS, tributos, juros do BB e o resto ficaram em três partes iguais
  (regra dele para conta geral sem destino). Os financiamentos de máquinas
  (Bradesco, Sicoob) e o consórcio ficaram em três partes por decisão **explícita**
  dele ("rateado entre as 3"), e os **seguros de máquinas** (quatro apólices)
  também ("rateio entre as 3"). Ele corrigiu em 05/11/2026 que NÃO vale assumir
  que combustível, frota e seguro servem às três só porque os financiamentos de
  máquinas servem: cada fornecedor foi perguntado (a lista `rateio_09` mostra cada
  lançamento com o código do documento do ERP) e as respostas viraram os ajustes
  abaixo.
- **Ajuste 1, rodado em 05/11/2026** (a lista de contas em três partes mostrou
  contas de uma atividade só): 16 lançamentos passaram de três partes para UMA
  parte com o valor inteiro: adubos, fertilizantes, corretivos de solo, frete de
  compra de produtos de um fornecedor de grãos, ferramentas de manejo e
  infraestrutura de um fornecedor de pecuária → **Pecuária** (R$ 48.983,00);
  análises agrícolas, seguro de safra e uma cooperativa de cana (máquinas) →
  **Cana** (R$ 2.645,51); aquisição de equipamentos do milho → **Grãos**
  (R$ 60.000,00). Só mexe em lançamento que o conserto refez e que ainda estava com
  três partes iguais; recusa se não forem exatamente esses números; backup das
  partes antigas em `zz_backup_rateio_ajuste1_2026_11_05` (fechada), desfazer no
  fim do arquivo. O script (`rateio_07`) tem nomes de fornecedores e fica só em
  `AEagropecuaria_dados_privados\rateio_2026-11\`. Depois dele, das 604 contas:
  Cana R$ 437.183,13 (34,5%), Grãos R$ 357.705,89 (28,2%), Pecuária
  R$ 472.779,01 (37,3%); 0 que não fecha; diferença R$ 0,00. Contas de **atividade
  única** assim se resolvem por fornecedor + centro de custo com a atividade
  informada pelo Eduardo, nunca por palpite do nome.
- **Ajuste 2 (combustível), rodado em 05/11/2026**: 17 lançamentos de combustível
  de dois fornecedores (R$ 23.796,81) passaram de três partes para **duas, Pecuária
  e Grãos, metade cada** (ele não indicou outra proporção), com os centavos na
  primeira parte. Mesmo formato do ajuste 1 (`rateio_10`, nomes na pasta privada;
  backup `zz_backup_rateio_ajuste2_2026_11_05`; desfazer no fim). Depois: das 604
  contas, Cana R$ 429.250,88 (33,9%), Grãos R$ 361.672,00 (28,5%), Pecuária
  R$ 476.745,15 (37,6%); 0 que não fecha; diferença R$ 0,00.
- **Exclusão de parcelas pessoais, rodada em 05/11/2026**: 24 parcelas de
  investimento de um fornecedor que é **gasto pessoal, não da empresa**
  (R$ 136.800,00, de mar/2026 a fev/2028) saíram do Financeiro por decisão dele; uma
  receita de R$ 9.400,00 de 2023 com o mesmo nome **ficou** (não é o gasto
  pessoal). Cópia completa dos lançamentos e das partes do rateio em
  `zz_backup_lanc_pessoais_2026_11_05` e `zz_backup_lanc_pessoais_rateios_2026_11_05`
  (fechadas), 66 partes saíram junto, `log_alteracoes` guardou cada exclusão;
  desfazer no fim do script (`rateio_08`, na pasta privada). **Se o ERP for
  reimportado essas parcelas voltam**: tirar de novo (o Financeiro, a aba Empresa e
  os resultados perdem esses R$ 136.800 de investimento, inclusive nos meses
  futuros).
- **Ajuste 3 (manutenção da frota), rodado em 05/11/2026**: 22 lançamentos
  (R$ 20.408,64) de fornecedores de peças e serviços da frota passaram de três
  partes para UMA, na atividade que ele apontou fornecedor por fornecedor: Cana
  R$ 15.072,64, Grãos R$ 2.250,00, Pecuária R$ 3.086,00 (`rateio_11`, nomes na pasta
  privada; backup `zz_backup_rateio_ajuste3_2026_11_05`; desfazer no fim). Ficaram
  em três partes: um fornecedor sem resposta dele (R$ 4.078, oito lançamentos
  mensais) e um pequeno por decisão dele.
- **Estado final do rateio da safra 2026/27 (05/11/2026)**: depois do conserto,
  dos ajustes 1 a 3 e da exclusão das parcelas pessoais, as contas que o conserto
  refez somam R$ 1.199.268,03 (592 lançamentos; eram 604 e R$ 1.267.668,03,
  menos as 12 parcelas pessoais de R$ 68.400,00): **Cana R$ 414.720,60 (34,6%),
  Grãos R$ 334.319,14 (27,9%), Pecuária R$ 450.228,29 (37,5%)**; 0 lançamentos que
  não fecham; visão rateada = Financeiro (diferença R$ 0,00). Seguem em três
  partes iguais por decisão dele: financiamentos de máquinas e consórcio, seguros
  de máquinas, tributos, FGTS, juros do BB e o resto da administração. As
  constantes "604 / R$ 979.432,02" do `rateio_05` não valem mais (já rodou; ele
  recusa). Backups a apagar quando ele confirmar: `zz_backup_rateio_2026_11_05`,
  `zz_backup_rateio_ajuste1_2026_11_05`, `..._ajuste2_...`, `..._ajuste3_...`,
  `zz_backup_lanc_pessoais_2026_11_05` e `zz_backup_lanc_pessoais_rateios_2026_11_05`.
- **Se reimportar o ERP**: não rode o rateio do importador como está (mesmas
  falhas acima); use as regras do `rateio_05`. Gente nova na folha: cadastre em
  Funcionários (alocação) e acrescente o pareamento ao próximo rateio. Depois
  de qualquer carga, `rateio_02_diagnostico.sql` tem de dar 0 que não fecham **e**
  `rateio_18_sem_atividade.sql` tem de mostrar "SEM ATIVIDADE" só nos centavos e nos
  movimentos de caixa (o 02 não pega lançamento `'geral'` sem partes; o 18 pega).
  `zz_backup_rateio_2026_11_05` pode ser apagada quando ele confirmar que está
  tudo certo.

### Lançamento novo sempre tem atividade; conta de mais de uma atividade é dividida (05/11/2026)

Pedido do Eduardo: "não poder lançar sem atividade; se for para ratear, lança as
três atividades, para não gerar confusão". A origem do problema acima: um
lançamento `'geral'` sem as partes do ERP não cai em nenhuma das três atividades
nos resultados, e a tela de custo por hectare o reparte por hectares (outra
regra). Agora, só no `AEMatriz.html`:

- **`ATIVIDADES_NOVO_LANC`** (pecuária, cana, grãos) é o que o formulário
  oferece. `ATIVIDADES_LANC` segue inteira (com "Geral") porque filtros e rótulos
  precisam mostrar os lançamentos antigos. Quem mexer nos formulários: não
  devolva "Geral" à lista de lançamento novo.
- **Nova despesa/receita/investimento** nasce **sem atividade** (antes vinha
  "pecuária" sozinha, e passava lançamento de outra atividade sem ninguém
  escolher) e não salva sem escolher. Herda o filtro da tela só quando ele é
  uma das três.
- **"Dividir entre as atividades"** (só em lançamento novo): um **lançamento por
  atividade**, o mesmo modelo que a baixa de um título rateado já gera (não um
  `'geral'` com partes escondidas em `lancamento_rateios`). Começa em partes iguais
  (`DIVISAO_PADRAO` 33,333 / 33,333 / 33,334, para 900 dar 300 + 300 + 300; com
  duas casas daria 299,97 / 299,97 / 300,06), percentuais editáveis, 0 deixa uma
  atividade de fora, soma tem de ser 100% e são no mínimo duas. O último leva o
  resto dos centavos (100 → 33,33 + 33,33 + 33,34). Entram numa **chamada só**
  (todas ou nenhuma). `observacao` ganha "Dividido entre atividades: parte i de n
  (p% de R$ total)": **as partes iguais entre si aparecem como "repetidos" nas
  consultas `rateio_12/13/14` (mesmo fornecedor, valor e mês); a observação é o
  que as distingue de duplicidade.**
- **Lançamento `'geral'` já existente** (ERP ou antigo) abre com a atividade
  **travada** em "Geral (como está)": trocar não desfaria as partes do ERP, que a
  view `lancamentos_rateados` continua usando; os outros campos editam normal.
  `geral` em lançamento novo (ou trocado para `geral`) é barrado ao salvar.
- **Contas a pagar/receber**: cada parte do rateio pede a atividade
  (`rateioVazio()` nasce sem; "Geral" só aparece num título que já era geral). Para
  uma conta de várias atividades, o título já se divide em partes.
- **A tabela `lancamento_rateios` continua fechada**: conferido em 05/11/2026,
  RLS ligado, 0 regras, `anon` sem leitura nem escrita. O app não grava nela (só a
  importação e os scripts) e lê pela view. Por isso a divisão acima não a usa.
- **Limites**: a trava é só do app. Não há trava no banco: SQL direto ou o
  importador ainda criam `'geral'`. A tela de custo por hectare segue repartindo
  `'geral'` por hectares (decidir se passa a ler as partes/terços é com ele).
- Teste: `teste_lancamento_atividade.py` (falha no código anterior);
  `teste_contas.py` passou a escolher a atividade antes de salvar a conta.
- **Quanto estava fora das três atividades (medido em 05/11/2026 com
  `rateio_18_sem_atividade.sql`)**. Os avisos que existiam (aba Empresa "rateio
  incompleto" e a conferência "visão rateada = Financeiro") NÃO pegam lançamento
  `'geral'` sem partes: a view o devolve inteiro, então os totais batem e ele cai em
  nenhuma das três atividades. Resultado em todas as safras: **despesa R$ 3.486,08
  sem atividade em R$ 39,6 mi** (12 lançamentos: 3 de dinheiro de verdade, R$ 2.581,99
  serviços profissionais, R$ 704,00 análises agrícolas e R$ 200,00 outras despesas
  financeiras, todos de 2026/27, e 9 de centavos que somam R$ 0,09); **investimento
  R$ 0,00**; **receita R$ 699.761,02 em R$ 57,2 mi** (52 lançamentos), dos quais
  R$ 620.570,23 são movimentos de caixa que não são receita de atividade (ajuste de
  saldo bancário, resgate de aplicações, estorno, outras movimentações, aporte,
  rendimentos), R$ 44.705,55 venda de veículos e máquinas, R$ 17.325,23 "não
  relacionados à atividade rural" e só R$ 17.160,01 de receita de atividade sem
  atividade. Nenhum lançamento recorrente sem mês. A aba Empresa soma o Financeiro
  inteiro, então o total da empresa nunca deixou nada de fora. Não foi medido o
  contrário (lançamento com a atividade errada).
  `rateio_19_lista_sem_atividade.sql` lista o que sobrou e precisa de atividade.
- **Ajuste 4, rodado por ele em 05/11/2026 (`rateio_20`, nomes fora do git; backup
  `zz_backup_ajuste4_lanc_2026_11_05` e `zz_backup_ajuste4_rateios_2026_11_05`,
  fechadas, a apagar quando ele confirmar)**: a segurança patrimonial passou a
  **Cana** (4 importações de 2026/27, antes em três partes, R$ 9.291,92) e a
  cooperativa de cana lançada à mão de 06/2026 passou de Pecuária a **Cana**
  (R$ 425,96). Por decisão dele; **não** mexeu no histórico (antes de maio/2026:
  segurança 14 lançamentos R$ 21.965,00 e cooperativa 91 lançamentos R$ 68.013,48
  ainda não estão só em Cana, pela proporção do ERP) nem na parcela de R$ 425,33 da
  cooperativa que o conserto pôs em Pecuária. Conferência: 0 lançamentos que não
  fecham o valor.
- **Regra dele para o que está sem atividade (05/11/2026)**: "da safra 26/27 para
  trás pode ratear entre as três atividades, mas só o que estiver sem atividade";
  a safra 26/27 ele decide um a um. Combinado com ele (e ele concordou): **não**
  ratear o que não é receita de atividade, porque colocaria R$ 638 mil de "receita"
  dentro de Pecuária, Cana e Grãos: os movimentos de caixa (R$ 620.569,54: ajuste de
  saldo bancário, resgate de aplicações, estorno, outras movimentações, aporte,
  rendimentos), os "outros recebimentos não relacionados à atividade rural"
  (R$ 17.325,23) e os centavos. Esses ficam sem atividade de propósito: a aba
  Empresa os mostra nos blocos próprios do fluxo, e `rateio_18_sem_atividade.sql`
  vai continuar listando-os.
- **Ajuste 6, rodado por ele em 05/11/2026 (`rateio_22`, ids fixos, backup
  `zz_backup_ajuste6_lanc_2026_11_05`, a apagar quando ele confirmar)**: 10 receitas
  anteriores a maio/2026 que estavam sem atividade passaram a três partes iguais
  (R$ 28.865,55: venda física de produção 6 lançamentos R$ 13.810,00, serviços
  agropecuários R$ 1.350,00, casa-sede R$ 2.000,00, venda de veículos e máquinas
  2 lançamentos R$ 11.705,55). Conferência: 0 lançamentos que não fecham o valor.
- **Reconferido por ele no fim de 05/11/2026 com `rateio_18` (depois dos ajustes 4,
  6 e 7)**: despesa sem atividade R$ 0,09 (centavos de arredondamento do ERP),
  investimento R$ 0,00, receita R$ 637.895,47 em R$ 57,2 mi (1,1%), que é só o que
  ficou de fora de propósito (movimentos de caixa R$ 620.570,23, "não relacionados à
  atividade rural" R$ 17.325,23 e R$ 0,01). Em toda safra e tipo,
  Pecuária + Cana + Grãos + sem atividade = total da empresa.
- **Ele mudou a decisão sobre esses R$ 637 mil (05/11/2026, noite) e passou a
  querê-los rateados também**: movimentos de caixa (32 lançamentos, R$ 620.569,54) e
  "não relacionados à atividade rural" (7, R$ 17.325,23), todos anteriores a maio/2026,
  em **três partes iguais**, sabendo que isso põe R$ 637.894,77 de entradas de caixa
  como "receita" nas telas por atividade (quase tudo de 2022/23 e 2023/24; a aba
  Empresa não muda). Script `rateio_24_ratear_caixa_e_nao_rural_antigos.sql`
  (RODADO por ele em 05/11/2026, tudo OK: 39 receitas, R$ 637.894,77, 0 que não fecha,
  receita sem atividade agora só R$ 0,70; traps 32/7 e os dois valores, backup
  `zz_backup_ajuste8_lanc_2026_11_05`,
  desfazer no fim; os centavos, R$ 0,70 de receita e R$ 0,09 de despesa, ficam de fora).
  Isto SUPERA o "ficam sem atividade de propósito" do item anterior. Depois de
  rodar, a `rateio_18` deve mostrar receita sem atividade só nos centavos.
- **Safra 26/27 sem atividade, decidido por ele (`rateio_23`, RODADO por ele em
  05/11/2026, tudo OK e 0 lançamentos que não fecham o valor)**: análises agrícolas R$ 704,00 em **Grãos**; serviço do próprio ERP
  R$ 2.581,99 em **três partes iguais**; uma despesa de R$ 200,00 lançada à mão
  em **Cana**; venda de veículo ou máquina de R$ 33.000,00 (importação de
  06/2026) em **Pecuária**. Backup `zz_backup_ajuste7_lanc_2026_11_05`. Substitui a
  `rateio_21`, que foi removida do repositório (ela pôs as análises em Cana, que
  não foi a decisão dele).

### Lançamentos repetidos da importação do ERP e do acerto de 21/10: o que sai e o que fica (05/11/2026)

Achado com `rateio_14_pares_por_data.sql` (par = mesmo fornecedor, mesmo valor,
pagamento a até 7 dias do vencimento, mesmo documento do ERP quando a linha tem
um; **não** parear por mês: a importação guarda a competência e o vencimento, o
acerto guarda a data do pagamento, e o par certo cai em meses diferentes).
Resultado que ele rodou: **A) 32 pares, R$ 93.636,53** (linha do acerto repetida
da importação, mesmo documento); **B) 18 pares, R$ 43.646,80** (lançada à mão,
sem autor, vinda do app antigo da Pecuária, repetida de uma importação "geral"
que a limpeza de agosto não alcançou); **463 linhas do acerto, R$ 1.530.124,65,
sem par**: não são duplicata (o acerto casou título a título). Pedido dele:
"o que tiver duplicado, apaga e deixa um lançamento só, corrigido".

`rateio_15_remove_duplicados.sql` (tudo ou nada, traps de 32/R$ 93.636,53 e
18/R$ 43.646,80, cópia fechada `zz_backup_dup_*_2026_11_05`, desfazer no fim):
- **A**: fica a **importação** (tem a competência e as regras de rateio dele);
  sai a linha do acerto.
- **B**: se a importação já foi refeita pelo `rateio_05_conserto` (está em
  `zz_backup_rateio_2026_11_05`), ela já segue as regras de hoje (combustível
  Pecuária/Grãos 50/50, cooperativa de cana = Cana): fica a importação, sai a
  lançada à mão. Se **não** foi refeita (competência antiga), fica a lançada à
  mão (regra de agosto: é o registro nativo) e sai a importação. Duas lançadas à
  mão iguais para uma importação só: fica uma.
- **Nunca apaga** linha com contrato de financiamento, lote, abate ou áreas da
  pecuária, nem se algo apontar para ela (chave estrangeira): o par fica inteiro
  e aparece na lista final para ele decidir.
- Efeito: o Financeiro perde R$ 137.283,33 que estava contado duas vezes.
  **Se o ERP for reimportado, as importações apagadas voltam.**
- Atividade que muda de lado: nos 13 pares de A (R$ 23.311,08) em que o acerto
  traz a atividade do ERP (segurança patrimonial, plano de saúde, seguro,
  manutenção de infraestrutura, frete, serviço técnico) e a importação está em
  três partes (regra padrão dele), vale a importação. A segurança patrimonial é o
  caso duvidoso: o ERP e a linha que ele mesmo lançou em novembro dizem Cana; a
  importação está em três partes. Nomes ficam fora do git (a lista com nomes está
  nesta conversa e na memória, não aqui).
- Ensaiado num Postgres descartável com os 50 pares (valores e datas reais, nomes
  trocados por letras) e os casos de recusa e de desfazer.
- **Rodado por ele em 05/11/2026, igual ao ensaio**: 50 lançamentos apagados,
  R$ 137.283,33 (A: 32, R$ 93.636,53; B: 18, R$ 43.646,80), 70 partes de rateio
  saíram junto, 0 pares pulados, 0 que não fecha o valor, visão rateada = Financeiro
  (diferença R$ 0,00). Dos 18 de B, 9 ficaram com a importação (já refeita) e 9 com
  a lançada à mão (competência antiga). Cópias fechadas a apagar quando ele
  confirmar: `zz_backup_dup_2026_11_05`, `zz_backup_dup_rateios_2026_11_05` e
  `zz_backup_dup_pares_2026_11_05`.
- **Decisões dele logo depois**: a segurança patrimonial é **Cana**; a cooperativa
  de cana (as lançadas à mão que ficaram em Pecuária) passa a **Cana**; os outros
  repetidos (um prestador com pagamentos de mesmo valor, peças e outros) são
  compras parceladas repetidas de verdade e **ficam como estão**.
- Os totais de "Estado final do rateio da safra 2026/27" acima mudaram com estas
  exclusões (as importações que ficaram carregam as regras dele; saíram linhas do
  acerto que contavam a mesma conta): recalcular com uma consulta nova, não confiar
  naqueles números.
- **Repetidos de janeiro a abril/2026 (`rateio_17_pares_desde_janeiro.sql`, rodado por
  ele em 05/11/2026)**: a `rateio_14` e a `rateio_15` começavam em 15/04. Desde 01/01
  há **56 pares lançada à mão × importação, mesmo dia e mesmo valor, R$ 769.448,59**
  (todos classe B, sem documento): a limpeza de agosto só tirou a importação de
  atividade Cana ou Pecuária, não a "geral" com partes, e a importação voltou depois
  (ids ~20546 a 21300). **O acerto de 21/10 cobre de janeiro a outubro, não só de
  15/04** (488 linhas do acerto sem par, R$ 2,17 mi: ok, não são duplicata).
- **`rateio_25`, rodado por ele em 05/11/2026**: 50 pares, R$ 106.279,83 (despesas e as
  parcelas da cooperativa), 154 partes de rateio saíram junto, 0 pulados, 0 que não
  fecha, visão rateada = Financeiro. Em todos ficou a **lançada à mão** (inteira em
  Pecuária, regra de agosto) e saiu a importação; em 17 desses pares a importação
  estava dividida entre atividades (combustível e cooperativa, R$ 45.451,61): esse
  valor passou a contar 100% em Pecuária (ele não pediu o contrário). Cópias fechadas,
  a apagar quando ele confirmar: `zz_backup_dup2_2026_11_05`,
  `zz_backup_dup2_rateios_2026_11_05` e `zz_backup_dup2_pares_2026_11_05`.
- **Compras de matrizes e consórcio, esclarecidas por ele pelo extrato (05/11/2026)**:
  as duas compras do primeiro vendedor (07/01/2026, R$ 228.150,00 e R$ 232.375,00)
  estavam lançadas duas vezes (a lançada à mão "Compra de matrizes para reprodução" e a
  transferência do ERP): `rateio_26_remove_duplicados_compra_matrizes.sql` apaga a
  importação e fica a lançada à mão (R$ 460.525,00; **RODADO por ele em 05/11/2026**, tudo OK, 0 que não fecha; cópias
  `zz_backup_dup3_*_2026_11_05`). As do segundo vendedor (13/02/2026, R$ 173.037,50 e
  R$ 6.562,50) e o consórcio (17/03/2026, R$ 22.799,46) ele disse que **não** são o mesmo
  pagamento: **ficam as duas linhas de cada uma**; as transferências estão certas e
  divididas porque pagaram "conforme carregou o gado"; é Pecuária; o consórcio é rateado
  entre as atividades. Mantidas as duas linhas, o app soma R$ 202.399,46 duas vezes se
  um dia o extrato mostrar que era a mesma saída: é só refazer a conferência. O
  financiamento dessas compras será lançado por ele no módulo Financiamentos.
- **Auto Posto de R$ 244,30 de 15/04 (duas compras iguais, `#3018` à mão e `#21300`
  importação): não é duplicata** (a `rateio_15` tirou a repetição de uma; as duas que
  sobraram são as duas compras) e ele decidiu que é **Cana**: `rateio_27_ajuste_posto_244_em_cana.sql`
  (**RODADO por ele em 05/11/2026**, tudo OK; cópias `zz_backup_ajuste9_*_2026_11_05`). A primeira
  rodada recusou porque a importação está no centro "COMBUSTÍVEL PARA FROTA…" e a lançada à
  mão em "COMBUSTÍVEIS DA OPERAÇÃO…"; a trava passou a aceitar os dois.
- **Consórcio lançado à mão (`#500`, R$ 22.799,46, 17/03/2026)**: ele confirmou que vai para
  **três partes iguais** (7.599,82 cada; o lançamento passa a `'geral'` com as partes, como
  as outras divididas): `rateio_28_ajuste_consorcio_tres_partes.sql` (**RODADO por ele em 05/11/2026**, tudo OK, 0 que não fecha;
  cópia `zz_backup_ajuste10_lanc_2026_11_05`). A importação do mesmo consórcio (`#21098`)
  continua dividida pela proporção do ERP e **não** é tocada (as duas linhas ficam).
- **Três pares de valores iguais, confirmados por ele como lançados em dobro (07/11/2026)**: o
  `saude_do_banco_02_detalhe.sql` (item A8) deixou três pares para conferir no ERP. Ele respondeu: o
  adubo (R$ 194.320,00 ×2, jun/2023, #14296/#14298) é da **Cana** e foi lançado duas vezes; a nutrição
  animal (R$ 50.000,00 ×2, ago/2024, #17113/#17115) é da **Pecuária** e também; o combustível
  (R$ 11.100,00 ×2, 15/03/2026, lançados à mão, #2570/#2571) é da **Cana** e também. Os dois primeiros
  pares têm códigos do ERP diferentes: o ERP também tem os dois, e **se o ERP for reimportado a linha
  apagada volta**. Uma consulta nas cópias `zz_backup_dup_pares` e `zz_backup_dup2_pares` não achou
  importação gêmea para o combustível (nenhuma linha). `rateio_29_remove_tres_pares_repetidos.sql`:
  fica o de MENOR número de cada par, sai o outro (R$ 255.420,00 a menos no Financeiro), e a linha que
  fica passa à atividade decidida (dividida entre atividades vira UMA parte da atividade, como na
  `rateio_27`; inteira em outra atividade troca a atividade). Um par só é tratado se as duas linhas
  forem idênticas, sem contrato/lote/abate/áreas e sem nada apontando para a que sai; senão o par
  não é tocado e a conferência diz por quê (os outros seguem). Cópias fechadas
  `zz_backup_dup4_*_2026_11_07`, desfazer no fim do arquivo. Ensaiado num Postgres descartável com o
  adubo dividido, a nutrição e o combustível inteiros, os mesmos já na atividade certa, as travas de
  06/11 instaladas, as recusas e o desfazer (37 checagens). **RODADO por ele em 07/11/2026, tudo OK**:
  3 lançamentos apagados (#14298, #17115, #2571), R$ 255.420,00; nenhum par pulado; as 3 que ficaram
  (#14296 e #2570 inteiras em Cana, #17113 inteira em Pecuária); os 6 lançamentos estavam inteiros,
  sem partes de rateio (backup 6 / 0); 0 lançamentos com rateio que não fecha; visão rateada =
  Financeiro (diferença R$ 0,00). Cópias `zz_backup_dup4_*_2026_11_07` a apagar quando ele confirmar.

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
`ano_safra`. Desde 28/10/2026 elas **não entram mais na despesa** (veja "Ração:
a compra é o custo financeiro" abaixo); ficam só em `consumoGerencial`.
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

### Ração: a compra é o custo financeiro, o consumo é custo por animal

Decisão do Eduardo em 28/10/2026. O custo **financeiro** da ração (e do pasto)
é a **compra** do insumo, que já é despesa lançada (centro Nutrição animal /
Insumos pecuários, na despesa fixa da Pecuária). A **saída de ração** (kg x
preço da dieta, `saidas_racao`) só serve para saber quanto se gasta por animal
e por lote. O Matriz somava as duas coisas e contava a ração duas vezes
(R$ 99 mil de jul a out/2026; a Pecuária no Matriz mostrava R$ 1,65 mi em vez
de R$ 2,07 mi). Corrigido em `carregarResultadoPecuaria()`: `despesa` e
`despesaPorCategoria` só têm o lançado (`fixa`); o consumo fica em
`consumoGerencial` (racao, pasto, reproducao), só informativo. Coberto por
`teste_matriz_racao_nao_duplica.py`. Mesma classe de erro do insumo agrícola
contado duas vezes: não reintroduzir.

Mesma regra no AE Pecuária (corrigido em 28/10/2026): **custo por animal e por
lote = consumo da ração + fixo SEM a compra de ração**; **resultado financeiro
= despesa lançada inteira** (a compra fica). `ehCompraDeRacao(c)` reconhece a
compra pelo nome do centro de custo ("Nutrição animal") ou pelo nome EXATO da
conta lançada à mão ("Nutrição animal" em Insumos pecuários) -- nunca por
"contém" (um fornecedor com "nutrição animal" no nome, em centro de manutenção,
não é ração). `dadosFinanceiroBase()` devolve `fixosMes` (lançado inteiro, vai
pro resultado), `fixosCustoMes`/`fixoConfinamentoCusto`/`fixoPastoCusto`/
`fixoCriaCusto`/`fixosAnoCusto` (sem a compra, vão pro `totalMes`, `totalAno`,
custo por animal, Custo/@ e `fixoAreaMes` do Por Lote) e `compraRacaoMes`/
`compraRacaoAno` (quanto ficou de fora; a tela do Resumo avisa). As despesas por
área (`fixoConfinamento`, `fixoPasto`, `fixoCria`) seguem com a compra, são
despesa. Coberto por `teste_pecuaria_custo_sem_compra_racao.py`. Se alguém
renomear o centro "Nutrição animal", o teste pega.

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
  (R$ 252.724,71). Os outros 3 (dois pagamentos de um vendedor de animais em
  jan, que pareciam uma compra parcelada, e um de outro em ago) não
  tinham par exato — confirmados como investimento novo, ficaram intocados.
  **Revisto em 05/11/2026**: aquele pareamento era por MÊS (competência de janeiro
  no ERP × pagamento em 13/02 no app); pelas DATAS existe lançamento à mão igual
  aos dois pagamentos. Ver "Repetidos de janeiro a abril/2026" na seção sobre
  lançamentos repetidos: a decisão sobre eles está pendente com o Eduardo.

**Acerto das despesas de 2026 com o ERP (21/10/2026, rodado pelo Eduardo).**
Base: 4 relatórios de despesas pagas do ERP (Cana, Pecuária e Soja pagas em
jan–out/2026; Milho desde 2023), 1.656 títulos, R$ 9.282.737,41, carregados
numa mesa de pouso `despesas_erp_2026` (apagar depois). Cada título foi
casado um a um com o app (mesmo id do ERP, ou mesmo valor na mesma
atividade/geral com pagamento até 7 dias ou mesmo mês; cada lançamento serve
de par uma vez só). Resultado: 1.133 já estavam, 520 lançados
(`criado_por = 'ERP (acerto 21/10/2026)'`, data e mês = pagamento,
competência e id na observação), 3 amortizações ficaram de fora. Apagados:
os 270 lançamentos agrupados "ERP — Contas a Pagar cana…" de mai–out/2026
(R$ 1.504.783,65, total do mês por centro de custo, sem data; trocados pelas
notas) e os 8 "Mão de obra - importação ERP" da Pecuária de jan–ago/2026
(R$ 300.652,88: a folha já estava salário a salário, contava em dobro).
Fazenda Três Marias = Mata Verde. Na conferência mês a mês, "falta no app"
num mês e "sobra" em outro é deslocamento, não erro: o lançamento antigo do
ERP está no mês da competência, o relatório soma pelo mês do pagamento.
Ficou para olhar: a Cana de jan–abr/2026 tem R$ 20–117 mil por mês no app
sem par no ERP (itens que se repetem todo mês).

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

### Cana: área colhida na colheita

Pedido do Eduardo em 21/10/2026. Coluna opcional `colheitas_cana.area_colhida`
(`cana_colheita_area_colhida.sql`, rodar ANTES do app novo). Em branco = o
talhão inteiro foi colhido. Serve para quando parte do talhão fica sem colher
(cana planta do ano): o TCH do formulário e do histórico do talhão (média
ponderada: soma das toneladas ÷ soma das áreas colhidas) e a produtividade do
Matriz (`areaColhidaNoPeriodo`: por talhão, a área colhida informada ou a do
talhão; com mais de um corte no período, a maior) usam esse número
(`areaDaColheita` no AECana). Área colhida maior que o talhão não salva.
`teste_area_colhida_cana.py`. Colheita de grãos não tem o campo.
Na Palmito (21/10/2026) os talhões "Histórico 2023/2024/2025" foram apagados
(as 3 colheitas deles divididas pela área dos Talhões 1 a 5) e a colheita de
20/10/2026 (11.483,74 t) ficou em 112,41 ha colhidos de 152,41 ha.

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
  mil por mês). Relatórios, Geral e Operacional leem a visão e herdavam o buraco
  (**fechado em 05/11/2026**, ver "Rateio incompleto da safra 2026/27");
  a aba Empresa avisa a diferença do período. Diagnóstico:
  `rateio_confere_soma_das_partes.sql`. Os totais podem diferir de
  Geral/Operacional por esse buraco do rateio (até 28/10/2026 também porque
  estas somavam a ração e o pasto consumidos; hoje contam só a compra).
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
- **22/10/2026: a dívida a vencer do ERP foi apagada, os contratos passam a
  ser lançados à mão.** Pedido do Eduardo ("lançar de novo daqui para frente").
  O módulo não tinha contrato nenhum; saíram as 14 linhas de
  `movimentos_financiamento` com data depois de 22/10/2026 (R$ 4.287.031,96).
  Ficaram as 61 já pagas (R$ 13.542.127,95), histórico de amortização da aba
  Empresa. A lista "Dívida do ERP ainda sem contrato" fica vazia; o que segue
  sobre "Lançar contrato" vale só se uma carga nova do ERP trouxer dívida a
  vencer. Contrato lançado à mão: data real da cédula (senão vira empréstimo
  recebido falso no fluxo de caixa) e parcela antiga não se marca paga (o juros
  já está no Financeiro).
- **Cadastro de contrato à mão (22/10/2026, pedido do Eduardo: "gerou parcelas
  mensais mesmo eu colocando que o pagamento era anual").** Antes só gerava
  parcela mensal, não tinha data do 1º vencimento (só "carência") e abria em
  "Parcela única", que escondia o número de parcelas. Agora
  (`financiamentos_04_periodicidade.sql`, rodar ANTES do app novo): abre em SAC
  anual; "Pagamento das parcelas" (`periodicidade_meses` 1/3/6/12) e "Data do 1º
  vencimento" (`primeiro_vencimento`; a carência gravada é derivada dela). O
  juros da 1ª parcela conta o prazo real desde a contratação, as outras o
  período. Contrato antigo (sem 1º vencimento) gera igual a antes.
  "Informar valor e juros de cada parcela" abre a tabela da cédula (vem com o
  cálculo; amortização = parcela - juros; a soma tem que fechar com o principal
  em R$ 1); editar contrato com valores digitados reabre com eles
  (`parcelasManuaisDoContrato`), para não trocar pelo cálculo. **Excluir**
  (admin/dono) apaga contrato, parcelas e o juros que elas lançaram;
  renegociação excluída devolve a de origem a ativo. Cancelar continua sendo o
  que guarda histórico. No mesmo dia o Eduardo apagou os contratos vigentes que
  tinha lançado (ficaram os quitados) para lançar de novo assim.
  `teste_financiamentos_periodicidade.py`.
- **Apagar a dívida a vencer do ERP derrubou o saldo médio do passado**
  (achado pelo Eduardo no mesmo 22/10/2026: custo médio da dívida de 2025 foi
  de 9,8% para 31,1% a.a.). A linha do tempo da dívida monta cada contrato do
  ERP como "soma de todas as parcelas, pagas e a vencer"; sem as a vencer, a
  dívida de 2025 encolheu e o juros de 2025 não. Volta quando os contratos
  vigentes forem relançados **só pelo saldo**, com data de contratação = dia da
  última parcela paga e a caixa **"Contrato que já existia"** marcada
  (`financiamentos.continuacao`, `financiamentos_05_continuacao.sql`): o
  histórico do ERP leva a dívida até aquela data e o contrato segue dali, sem
  contar duas vezes, e ele **não** entra como empréstimo recebido no fluxo de
  caixa. Relançar o contrato inteiro (principal original) dobraria a dívida
  antiga, porque as parcelas pagas continuam no ERP.
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
    lançamento no Financeiro). Nada apaga histórico. **Editar o contrato** também
    aparece na lista, para todo contrato ativo (23/10/2026: a lista escondia o
    botão nos importados do ERP e nos com parcela paga e o Eduardo perguntou "pq
    não posso editar um dos financiamentos"; o clique é o mesmo da tela do
    contrato e já abre a edição reduzida, que nunca regera o cronograma).
  - O contrato "sem número" do Banco do Brasil (4 parcelas de R$ 456.737,72) tem
    duas parcelas em 15/08/2029 e nenhuma em 2028 no ERP: provável erro de
    digitação de lá; o total fecha, só o vencimento do meio sai errado.
  - Lançar parcela antiga como "paga" em contrato digitado à mão também
    duplicaria o juros (já está no ERP).
- O ERP **não tem entrada de empréstimo**, só amortização: sem ela, a
  cobertura do serviço da dívida sai pior que a realidade.
- **Lançar contrato a partir do extrato do banco, sem duplicar** (feito em
  23/10/2026 com dois extratos do Banco do Brasil). Antes de inserir qualquer
  coisa, case cada pagamento do extrato, **por valor exato (centavo)**, com o que
  o sistema já tem: amortizações do ERP (`movimentos_financiamento`, pelo apelido
  C##) e despesas de juros e encargos do Financeiro. Compare a **soma do dia**,
  não as partes: o ERP pode ter dividido o pagamento diferente do banco (um
  financiamento de investimento foi lançado com amortização constante e o resto
  como juros; o principal real era menor, mas o total do dia batia). O passado
  que já está lá não se relança: o contrato só assume as linhas
  (`financiamento_id`) e as parcelas pagas entram sem juros. Pagamento de antes
  de 2023 não existe no ERP e não entra. Tarifa e IOF pagos à vista na liberação
  de contrato posterior a ago/2026 não estão em lugar nenhum: conferir e lançar
  como despesa (capital de giro: 3 partes iguais, como o juros).
  - **Juros diferidos**: o banco acumula juros, TR e seguros financiados e cada
    parcela cobra a fração (amortização ÷ principal em aberto) do acumulado
    (conferido nos 4 pagamentos de um BB Investe Agro, com diferença de
    centavos). O gerador SAC/Price não reproduz isso e subestima o total em
    centenas de milhares: escreva as parcelas a vencer pela regra do banco
    (estimativa, trocada pelo valor real em "Registrar pagamento"). O custeio do
    BB acumula juros compostos por dia, base 365 (a liberação, não a assinatura,
    é a data de início).
  - **Como fazer**: por SQL, que o Eduardo cola no Supabase, com travas que
    recusam se faltar uma linha esperada ou se o contrato já existir. Ache as
    linhas do ERP pelo apelido do contrato (depois de 22/10/2026 nenhum contrato
    tem linha a vencer: a dívida a vencer do ERP foi apagada, então a dívida
    dele só passa a existir quando o contrato é lançado). Teste antes num
    Postgres de teste com o DDL real do módulo **e no app de verdade**: o fluxo
    de caixa dos meses já pagos tem que dar os mesmos números antes e depois.
    Extratos, consultas e SQL de cada lançamento ficam na pasta privada, nunca
    no repositório (têm valores e datas dos contratos).
  - **Dois jeitos de lançar contrato vigente; nunca os dois para o mesmo
    contrato.** (a) "Contrato que já existia" (`continuacao`, pelo saldo, data da
    última parcela paga, as pagas seguem livres no histórico do ERP): é o jeito
    da tela. (b) "Estilo importado" (usado para o financiamento dos tratores):
    contrato com todas as parcelas (as pagas iguais ao ERP, sem juros) e
    observação `Importado do ERP (contrato C##)`, que **assume** as linhas pagas
    do ERP (`financiamento_id`). Os dois não contam a dívida duas vezes e não
    entram como empréstimo recebido; o (b) devolve ao saldo médio de 2023 em
    diante o saldo que o contrato tinha (medido: +R$ 240 mil por ano no
    contrato dos tratores), que é o que a exclusão da dívida a vencer derrubou.
    Se um contrato foi lançado por um jeito, lançar pelo outro dobra a dívida.
- **Saldo devedor segundo o banco** (pedido do Eduardo em 23/10/2026, depois de
  lançar os extratos: "o saldo devedor que vc colocou é um e no contrato é outro").
  O extrato soma ao principal o juros, a correção e os seguros financiados que
  ainda não foram pagos (nos tratores o banco mostrava R$ 455 mil e o principal
  era R$ 240 mil); o app conta só o principal como dívida e só lança o juros como
  despesa quando a parcela é paga. Não se resolve mudando a conta, e sim
  mostrando o número do banco ao lado: `financiamentos.saldo_banco` e
  `saldo_banco_em` (`financiamentos_06_saldo_segundo_o_banco.sql`, opcionais;
  **rodado pelo Eduardo em 23/10/2026**, e os dois contratos lançados dos
  extratos já têm o saldo do banco) aparecem na lista ("No banco: R$ … em dd/mm/aaaa" embaixo do saldo devedor) e na
  tela do contrato (cartões: principal que falta pagar, saldo segundo o banco e
  juros, correção e seguros ainda não pagos). **Só informativo: não entra na
  dívida da aba Empresa, nos vencimentos, no saldo médio, no fluxo nem nos juros**
  (`teste_saldo_banco.py` compara tudo com e sem o campo). `saldoDoBanco(f)`:
  só contrato ativo; parcela paga **depois** da data do extrato deixa o saldo
  "desatualizado" e some a diferença (seria falsa); valor e data andam juntos. O
  app só manda as colunas quando há valor ou o contrato já tinha um (salvar contrato
  antes de rodar o SQL continua funcionando). **Ao lançar contrato a partir de
  extrato, grave também o saldo e a "posição em" do extrato.** A correção
  monetária desses contratos é "TR por data", 100% da TR (a parte da poupança que
  corrige o saldo, sem os 0,5% ao mês da poupança inteira): ~0,17% ao mês nos
  últimos 12 meses, já nas estimativas das parcelas a vencer.
  A lista de contratos virou bloco no celular (`tabela-em-blocos`; rolava 457 px de
  lado em 376 px e o `teste_layout_matriz.py` não via, porque o banco dele não
  tem contrato) e o cabeçalho "Finalidade", que desde o começo do módulo ficava em
  cima do valor contratado, virou "Contratado" e "Data do contrato".
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
- **AE Matriz inteiro sem rolar de lado** (pedido do Eduardo em 21/10/2026,
  print de Pagar/Receber com os botões escondidos atrás da barra):
  `teste_layout_matriz.py` abre as 12 telas de 1920 a 320 px e falha se a
  página ou um card rolar de lado. A tabela de Contas usa `tabela-contas`
  (`table-layout:fixed` com `<colgroup>`: o texto quebra dentro da coluna
  em vez de esticar a tabela) e vira bloco até 1060 px; Fazendas, Centros de
  Custo, Usuários e as tabelas de Resultados > Geral usam
  `tabela-blocos-celular` (bloco só até 760 px). O menu do topo quebra em duas
  linhas em vez de rolar. Tela nova: rode esse teste.
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

### Campos de dinheiro com ponto e vírgula ao digitar

Pedido do Eduardo em 22/10/2026. No AE Matriz, os 13 campos de valor em R$
(lançamento, conta a pagar/receber, rateio, parcela, baixa, financiamento,
pagamento e edição de parcela) levam `data-moeda` em vez de `type="number"`:
mostram `1.234.567,89` enquanto digita (ponto de milhar sozinho, vírgula ou
ponto digitado viram os centavos, 2 casas, ao sair completa `,00`), mas
`el.value` devolve `"1234567.89"`, como o campo numérico devolvia
(`prepararCamposMoeda`, chamado no começo de `attachEvents`; o getter/setter
fica no próprio elemento). O resto do código lê e grava sem mudar. Campo de
dinheiro novo: `type="text" inputmode="decimal" data-moeda`. Taxa (%), área,
quantidade e parcelas continuam `type="number"`. `teste_campo_moeda.py`.

### Pecuária: dado que não carregou não pode parecer "nenhum lote"

Em 22/10/2026 o Joilson (Cria) não conseguia lançar saída de ração: a tela
dizia "Nenhum lote de cria cadastrado" e o lançamento "Não há lote de Cria
ativo", com 6 lotes de Cria ativos no banco, permissão Cria: Editar e as dietas
visíveis (conferido com o banco). O `loadAll` do AEpecuaria pega cada consulta
com `buscarTudo` (hoje `fetchAllRows`, do núcleo), que devolve lista **vazia** quando a consulta falha (login
vencido, rede ruim), e nada avisava; tocar antes de a carga terminar também
dava lista vazia. Agora:
- `state.carregouDados`/`state.erroCarga`: aviso "Carregando os dados…" e, se
  lotes/dietas/insumos/animais falharem, aviso vermelho com "tente de novo"
  (`AvisoCarga`); `openNewModal` explica em vez de culpar o lote
  (`dadosProntosParaLancar`; sem rede continua liberado, a fila offline é como antes);
- erro de login vencido (JWT) renova a sessão uma vez e carrega de novo.

No dia seguinte (23/10/2026) ele ainda não conseguia lançar **nada**: entrando
no banco como ele (papel `authenticated` + id dele), via os 14 lotes, as 11
dietas e tudo o mais; com o perfil dele no stub o lançamento abria. O que
travava era a carga: o `loadAll` só liberava a tela depois de baixar tudo
(9.614 movimentos, 11.409 lançamentos, 1.697 saídas...), e com sinal fraco no
campo isso não terminava; com o bloqueio do dia anterior, nada passava. Agora
a carga tem **duas etapas**: lotes, dietas, insumos, animais e perfis primeiro
(liberam a tela e os lançamentos; limite de 25 s, `LIMITE_CARGA_ESSENCIAL_MS`,
depois vira aviso com "tente de novo") e o histórico pesado em segundo plano
(`state.carregandoHistorico`, aviso discreto). Salvar ração/cocho/pasto não
depende do histórico. `cargaAtual` descarta carga antiga se outra começou.
`teste_carga_pecuaria.py`.

Antes disso a primeira suspeita foi a permissão de dietas (só quem tinha
"Dietas" lia a tabela): `pecuaria_dietas_leitura_operador.sql` (rodado pelo
Eduardo em 22/10/2026) libera a **leitura** de dietas para Confinamento, Pasto e
Cria, e falta de dieta tem aviso próprio (`SEM_DIETA_PARA_RACAO`). O Joilson
já tinha Dietas: não era a causa, mas a regra nova vale para os outros
operadores.

### Pecuária: parto que "não salvava", lote em branco, número só com algarismos, aborto e óbito

Em 27/10/2026 o Eduardo editava o parto do Joilson com mãe "721 abortou"
(id 197; ele não tinha onde lançar aborto e escreveu no número) e a alteração
"não salvava". Duas causas, as duas reproduzidas e cobertas por
`teste_parto_aborto_lote_numero.py`:
- **Toque perdido.** Vários campos de texto redesenham a janela inteira no
  `change` (número da mãe/vaca atualiza a raça, número no Manejo e na Pesagem
  mostra os campos de animal novo, lista de números na entrada de animais).
  Digitar e tocar direto em Salvar: o toque tira o foco, o `change` redesenha,
  o botão tocado é trocado por outro e o navegador não entrega o click a
  ninguém. Nada acontecia, sem aviso; precisava de dois toques. Valia também
  para o "Salvar e ir pro próximo animal" do **Manejo**. Correção genérica no
  fim do arquivo: se o botão apertado saiu da página no meio do toque e nenhum
  click chegou, repete o click no botão equivalente (mesmo id e `data-*`).
  Botão novo não precisa de nada.
- **Tela velha.** Partos, desmamas, diagnósticos e inseminações vêm na 2ª
  etapa da carga (histórico pesado); depois de salvar, a lista mostrava o
  dado antigo até essa etapa inteira terminar. `recarregarReproducao()`
  (`TIPOS_REPRODUCAO`) recarrega só essas tabelas, pequenas, logo depois de
  salvar ou excluir. E `atualizarUmaLinha()` avisa quando o update não acha a
  linha (apagada ou recusada pelo banco), em vez de fechar a janela calado.

Pedidos do mesmo dia:
- **Lote sempre em branco** em todo lançamento (parto, inseminação,
  diagnóstico, ração, cocho, pasto, venda, pesagem, desmama, animal, entrada em
  lote existente, Manejo e lote de destino do Manejo): `opcaoSelecioneLote()` e
  `exigirLote()`. Vinha o primeiro lote cadastrado ("VACAS INVERNADA") e
  lançamento caía no lote errado. Escolher o lote não marca mais o primeiro
  bezerro na desmama, e o sexo do bezerro também começa em branco (vinha
  "Macho") e é obrigatório.
- **Número do animal só com algarismos**: `data-numero-animal` limpa ao
  digitar (teclado numérico), `erroNumeroAnimal()` barra no Salvar,
  `validarAnimalNovo()`/`upsertAnimal()` nunca criam cadastro com texto. A
  lista de números aceita só algarismos e separadores. **Número antigo com
  texto, sem mexer, continua salvando** o resto do lançamento e não cria nem
  move cadastro (`legadoMae`/`legadoInsem`/`legadoDg`). Texto do animal vai em
  `animais.nome` (campo "Nome / observação" no Editar do animal; aparece
  embaixo do número no lote e nos lançamentos de reprodução).
- **Aborto**: `partos.tipo` ('nascimento'|'aborto'), escolhido em "O que
  aconteceu" no Novo parto. Aborto não tem sexo/raça de bezerro, não conta em
  nascidos (coluna própria no resumo), não espera desmama e deixa a vaca como
  "Abortou" na situação reprodutiva. Parto com desmama ou óbito não vira aborto.
- **Nasceu morto** (terceira opção em "O que aconteceu", pedido do Eduardo no
  mesmo dia; o Joilson escrevia "pariu morto" no número): grava nascimento com
  óbito no dia do parto e causa "nasceu morto" (`CAUSA_NATIMORTO`,
  `partoEhNatimorto`), num lançamento só; sexo do bezerro opcional. Trocar a
  data leva o óbito junto; voltar para "Nasceu o bezerro" tira o óbito. Parto
  com óbito dias depois do nascimento abre como "Nasceu o bezerro" e não vira
  "nasceu morto" sem remover o óbito antes.
- **Óbito do bezerro antes da desmama**: `partos.data_obito`/`causa_obito`,
  botão "Registrar óbito" na lista de partos (some depois da desmama;
  "Remover óbito" desfaz). Continua contando como nascido, sai da desmama, e a
  taxa de desmame ganhou a coluna "Mortos antes da desmama". Morte depois da
  desmama continua sendo no cadastro do animal.
- SQL: `pecuaria_parto_aborto_obito_nome_animal.sql` (colunas e 3 travas;
  ensaiado num Postgres 16 descartável com as tabelas reais, repetível e numa
  transação só). O app funciona antes dele: parto normal não manda `tipo` e
  animal sem nome não manda `nome` (`_temTipo`/`_temNome`, mesmo padrão do
  `saldo_banco`); aborto, óbito e nome antes do SQL mostram "Rode no Supabase…"
  (`mensagemColunaFaltando`). A conferência do SQL lista os números com texto
  que ainda existem. **Rodado pelo Eduardo em 27/10/2026** (4 colunas, 3 travas,
  176 partos, todos nascimento) e achou 21 números com texto: em `animais`
  "19 ES", "37 ES", "351 não quis o bezerro descarte", "512 2S", "721 abortou"
  e "Alice 1" a "Alice 4"; em `partos.numero_mae` os mesmos 19/37/351, "37 Es",
  "721 " (com espaço) e "368/370 pariu morto" (bezerro que nasceu morto: no
  modelo novo é nascimento com óbito no mesmo dia); em `pesagens_animais`
  "512 2S" e "Alice 1" a "Alice 4". Limpeza:
  `pecuaria_limpa_numeros_com_texto.sql` (decisão do Eduardo: o número fica só
  com algarismos e Alice, 2S, ES e a observação da 351 vão para o Nome; o parto
  197 vira aborto da 721 e o cadastro duplicado "721 abortou" sai; 368/370
  "pariu morto" viram nasceu morto). Só troca um número se não existir outro
  animal do mesmo sexo com ele: "512 2S" fica PENDENTE (já existe o 512 macho
  do Curral 2), assim como qualquer "Alice N" cujo N já for de outro animal.
  Ensaiado no Postgres 16 descartável com os mesmos casos: repetível, numa
  transação só, e recusa rodar antes do SQL das colunas. **Rodado pelo Eduardo
  em 27/10/2026**: 20 resolvidos (inclusive "Alice 2", que não colidiu), o
  cadastro "721 abortou" apagado (a vaca 721 já existia), parto 197 virou
  aborto, partos 3 e 4 ("368/370 pariu morto", de 26/07/2026) viraram nasceu
  morto; só o "512 2S" ficou pendente. Decisão dele: o bezerro vira **512000**
  (fácil de reconhecer) e "2S" vai para o Nome,
  `pecuaria_512_2s_vira_512000.sql` (ensaiado; **rodado pelo Eduardo em 27/10/2026**:
  512000 macho nos Bezerros Invernada, 1 pesagem, nenhum "512 2S" sobrando;
  com isso nenhum número de animal tem mais texto no banco). O 512
  adulto do Curral 2 foi vendido e sai em 28/10/2026, mas o histórico de
  pesagem dele continua com o número 512: não reaproveitar.
- **Vaca do parto no lote do parto** (pedido do Eduardo em 27/10/2026: "o
  número de animais do lote não bate com o de partos"). O app já move a mãe
  para o lote do parto a cada parto lançado ou editado (`upsertAnimal` no
  gancho do parto), mas só o cadastro: não mexe em `lotes.numero_animais` (o
  Manejo com troca de lote mexe). `pecuaria_confere_vacas_no_lote_do_parto.sql`
  (só leitura) deu 0 vacas fora do lote: a diferença era **13 partos lançados
  em dobro** (`pecuaria_confere_partos_repetidos.sql`: 4 vacas relançadas em
  27/10 que já tinham parto em 14/10, 3 lançadas duas vezes no mesmo dia, a 316
  três vezes com toque duplo, e 4 com datas próximas) e 8 mães sem cadastro.
  Decisões do Eduardo: não há gêmeos, os duplicados se unificam
  (`pecuaria_unifica_partos_duplicados.sql`: fica o lançamento mais antigo, na
  316 o de 26/09; o que fica herda raça/sexo em branco e a desmama do que sai);
  vaca com raça em branco vira nelore (mesmo script); a 19 (ex "19 ES") não é a
  019 do parto e vira **19099**; os partos de 26/07 da 368/370 (sem lote, lote
  apagado) são do **Vacas vazia Santa Alice**; 019, 057, 076, 080, 083 e 147
  ganham cadastro em Vacas 07/08 (`pecuaria_vacas_sem_cadastro_e_19099.sql`,
  **rodado em 27/10/2026**; sobrou 1 parto sem lote, listado na conferência do
  script de unificar). **Unificação rodada em 27/10/2026**: os 13 saíram, 8
  vacas viraram nelore, 0 vaca com parto repetido; Vacas 07/08 com 84 partos de
  84 vacas. O parto id 1 (vaca 37, 23/07/2026, sem lote) era o mesmo parto do
  id 57 (13/08/2026, Vacas 07/08): regra do Eduardo para parto sem lote (bezerro
  morto vai para Vacas Vazias Santa Alice, vivo para Vacas 07/08,
  `pecuaria_parto_37_sem_lote.sql`, que parou ao achar o 57) e unificação pela
  mesma regra dos duplicados, fica o id 1 no Vacas 07/08
  (`pecuaria_parto_37_unifica.sql`, **rodado em 27/10/2026**: 0 parto sem lote,
  0 vaca com parto repetido). Ficou para 28/10/2026: as cabeças do
  Vacas 09/10 (70, com 72 vacas paridas), o Eduardo passa a contagem real.
- **Resumo de partos por lote mostra bezerros vivos e perdas à parte**
  (pedido do Eduardo no mesmo dia: no Vacas Vazias os bezerros nasceram mortos e
  o resumo ainda contava nascidos, machos e fêmeas). Colunas: Partos, Bezerros
  vivos (machos/fêmeas só dos vivos) e Perdas (nasceram mortos, morreram antes
  da desmama, abortos). Na taxa de desmame (Resultados > Reprodução) o bezerro
  morto continua nascido, de propósito: é perda que a taxa tem que mostrar.
- **Para não repetir** (mesmo dia): a data do parto começa em branco (vinha
  hoje; os partos de 14/10 relançados em 27/10 saíram com a data do dia), não
  aceita data futura, e `partoRepetidoDaVaca()` pergunta antes de gravar quando
  a mesma vaca tem outro parto/aborto a menos de 240 dias (`DIAS_ENTRE_PARTOS`):
  "é gêmeo?". Com o histórico ainda carregando, pergunta ao banco (5 s de
  limite, sem travar o lançamento com sinal fraco).

### Pecuária: número único, nome ao lado, e "Qual animal é?"

Decisão do Eduardo em 02/11/2026 (opção A): o número do animal continua
**único por sexo** (índice `animais_numero_sexo_unique`); dois animais com o
mesmo brinco (11 e "11 ES") ficam com números diferentes (11 e **11099**, o
texto no Nome; 19099, 24099... seguem o mesmo padrão; 512000 é o caso antigo
com 000). O Nome é opcional. Não identificar animal por número + nome: os
lançamentos (inseminação, diagnóstico, parto, desmama, pesagem, Manejo)
guardam só o número.

Ao salvar inseminação, diagnóstico, parto, pesagem por animal e Manejo,
`confirmarAnimalDoCampo()` pergunta **qual animal é** quando o número
digitado tem parecido com 099/000 no fim (`animaisParecidos`; só do sexo do
lançamento): 11 → 11 ou 11099 · ES. Sem parecido, ou editando sem mexer no
número, não pergunta. "Voltar e corrigir" não grava.

**Zero à esquerda não conta** (Eduardo, 02/11/2026: "57 e 057 são o mesmo
animal"): o campo do número tira o zero ao digitar; digitar 57 com a 057
cadastrada usa a 057 sem perguntar (`mesmoAnimalSemZeros`).
`pecuaria_numero_sem_zero_a_esquerda.sql` tira o zero do cadastro e de
partos, inseminações, diagnósticos, pesagens por animal e protocolos. Se dois
animais do mesmo sexo virariam o mesmo número, o de **lote encerrado** fica
com o zero, com o histórico (os bois 001/002/003 dos Currais 1 e 2, vendidos,
não são os bezerros 1/2/3 "Alice" da Bezerros Invernada); se os dois estão em
lote ativo, o script para sem mudar nada. Animal de lote encerrado não entra
na escolha do "Qual animal é?".

**Rodado pelo Eduardo em 02/11/2026**, nesta ordem:
`pecuaria_bois_001_002_003_viram_1000.sql` (os bois 001/002/003 dos Currais
1 e 2, encerrados, viraram **1000/2000/3000** com as pesagens; os bezerros
1/2/3 "Alice" ficaram) e depois `pecuaria_numero_sem_zero_a_esquerda.sql`: 87
animais, 43 partos, 103 pesagens e 24 inseminações sem o zero, nenhum mantido,
0 número com zero sobrando no banco.
`teste_qual_animal.py`.

### Pecuária: só IATF, no máximo 3 inseminações (zera no parto)

Regra da fazenda (Eduardo, 02/11/2026): não há touro, só IATF; até **3
inseminações** por vaca; não emprenhou na 3ª, vai para o descarte. A contagem
**zera no parto** (qualquer parto lançado, inclusive aborto) e o histórico
fica: `cicloReprodutivoVaca(numero, data)` devolve as crias da vaca na fazenda
(nascimentos), o último parto e as inseminações desde ele (qualquer lote, sem
zeros à esquerda). "Qual inseminação" vem preenchida por ela (1ª/2ª/3ª e
"4ª (fora da regra)"; dá para mudar), a janela da inseminação mostra crias e
inseminações desde o parto, e na 4ª o app **avisa** (`avisoQuartaInseminacao`,
confirm; não bloqueia, decisão dele). O Manejo com inseminação grava a
qual automática e avisa igual. Detalhe do lote de Cria: "N crias · X/3 IA
desde o parto".

### Matriz: Reprodução (Cria) em Resultados > Operacional

Pedido do Eduardo em 02/11/2026. `CardReproducaoOperacional()` /
`reproducaoNoPeriodo()` (AEMatriz.html), carga própria em
`carregarReproducaoPecuaria()` (falha nela não derruba o resultado da
Pecuária). No período do filtro: **custo por bezerro desmamado** =
(inseminação + consumo de ração e pasto dos lotes de Cria + fatia do custo
fixo) ÷ bezerros desmamados no período; a fatia do fixo é a despesa lançada da
Pecuária **sem a compra de ração** (`ehCompraDeRacaoLanc`, mesma regra do AE
Pecuária) × cabeças na Cria ÷ cabeças ativas hoje (estimativa: as despesas não
são lançadas por área). **Taxa de prenhez** = prenhas ÷ (prenhas + vazias) dos
diagnósticos do período. **Desmamados**: total, machos, fêmeas (sexo do parto)
e peso médio. Leitura certa é na Safra/Ano (num mês, custo e desmama raramente
coincidem). Só informativo: não entra em despesa nem resultado.

### Matriz: Resultados > Operacional agrupado por atividade

Pedido do Eduardo em 03/11/2026 ("a cana estava no meio da pecuária"):
`PageResultadosOperacional` mostra a **Pecuária inteira primeiro** (cartão do
resultado, Rebanho estocado e Reprodução) e depois a **Lavoura** (Cana e
Cereais lado a lado), e por fim o Resultado por unidade produzida. Bloco novo
de uma atividade entra no grupo dela.

### Matriz: Rebanho estocado (UA/ha e @/ha) em Resultados > Operacional

Pedido do Eduardo em 02/11/2026. `CardEstoquePecuaria()`/`estoquePecuaria()`,
carga própria em `carregarEstoquePecuaria()`. Retrato de **hoje** (não segue o
filtro de período): para cada lote ativo com animais, peso vivo = cabeças ×
peso médio da **última pesagem** do lote; UA = PV ÷ 450 kg; @ = PV × 50% de
carcaça ÷ 15 kg (premissa do Eduardo, "só para ter noção"); valor = @ × último
preço da @ de `precos_arroba` (fêmea para lote de fêmeas, macho nos demais);
por hectare = área de pecuária em Fazendas. Lote sem pesagem conta nas
cabeças, fica fora de UA/@/valor e a tela diz qual é. Só informativo.
Preço da @: **manual**, lançado no AE Pecuária (decisão do Eduardo, 02/11/2026,
opção B: preço da praça dele, em vez de buscar indicador de fora); com mais de
7 dias (`DIAS_PRECO_ARROBA_VELHO`) ou sem preço, o bloco avisa em vermelho.
`teste_matriz_estoque_pecuaria.py`.

### Revisão geral de 02/11/2026

Pedido do Eduardo ("revisão geral bem minuciosa"). Os 39 `teste_*.py`
passaram antes e depois. Corrigido:
- **Cana e Cereais não escapavam nenhum texto** (não tinham `esc`): nome com
  aspas era cortado no campo de edição e, ao salvar, gravava o nome cortado;
  `<` quebrava a tabela; tag no nome rodaria como código na tela de quem
  abrisse. `esc()` nos dois apps (célula da lista, campo de texto, textarea,
  busca, títulos). `teste_lavoura_texto_escapado.py`. Busca do Pecuária e do
  Combustível e o nome de cadastro ligado no Combustível também.
- **Matriz: consultas sem paginação** que podem passar de 1000 linhas
  (`pasto` e `reproducao_custos` do resultado da Pecuária, `entidades`) e
  paginação sem desempate único (`parcelas_financiamento` só por `numero`,
  `abates` só por `data`): agora `fetchAllRows` com `.order('id')` no fim.
- **Matriz: falha ao carregar Contas a Pagar/Receber passava calada** (lista
  vazia, e a trava de conta repetida não via as contas lançadas): agora avisa.
- **Combustível: custo do abastecimento noturno** usava o dia em UTC (22h
  local = dia seguinte), pegando o preço médio com as notas do dia seguinte;
  agora `dataLocalDoTimestamp`.
- **Pecuária**: a lista de números da entrada de animais também tira o zero
  à esquerda; mensagem errada na venda editada sem centro "Vendas" (dizia que
  a venda não mudou, mas o abate já tinha sido gravado).

### Revisão geral de 05/11/2026 (noite): o que a medição mostrou

Pedido do Eduardo ("check up geral bem minucioso"). Só leitura; o relatório completo e as notas estão
na pasta privada (`AEagropecuaria_dados_privados\revisao_geral_2026-11-05\RELATORIO.md`).
Medido com 25.000 lançamentos (volume real) e CPU 4x mais lenta (tablet de entrada):
- **Financeiro > Despesas desenha todas as linhas** (21.254 `<tr>`, 287.733 elementos): 2,6 s no PC,
  ~23 s no tablet; ~1 s (6 s) por tecla na busca. Sem paginação, filtro padrão "todos os meses" e
  a busca refaz a página inteira a cada tecla.
- `loadAll()` baixa lançamentos + a visão rateada inteira + 3 cópias por atividade e roda de novo
  depois de cada gravação; Relatórios 1,2 s e Empresa 2,4 a 3,3 s (O(meses x linhas) em
  `saldoAnteriorRelatorio`).
- **O resultado por atividade ignora `investimento`**: a compra de animais não reduz o resultado da
  Pecuária (Financeiro de 2025/26: receita 3,72 mi, despesa 2,71 mi, investimento 2,14 mi).
- A venda de animais grava 3 tabelas em sequência pelo navegador (sem transação) e calcula o saldo do
  lote com a cópia da memória (corrida entre duas pessoas perde uma venda).
- O banco não tem: índice único de `erp_id` em lançamentos, trava "geral precisa de partes",
  conferência partes = valor.
- `attachEvents` tem 880 linhas (Matriz) e 2.343 (Pecuária), religado a cada desenho da tela.
- Teste de chave pública contra o banco real: nada abre para quem não está logado.
- `saude_do_banco_01.sql` (só leitura, ensaiado com defeitos plantados): 24 checagens de lançamento,
  contas, financiamentos, pecuária e cadastro, com amostras.

### Segundo check-up (07/11/2026): a nota depois das correções

Pedido do Eduardo ("seguir na sequência"): medir de novo, meta **8 ou mais em todos os quesitos**. Relatório completo na pasta privada
(`revisao_geral_2026-11-07\RELATORIO.md`). Só leitura. Notas (julgamento do Claude): funcionalidade 8,5 → **9,0**; corretude 7 → **7,5**;
integridade 6 → **8** (reconferida por ele no banco real em 07/11/2026, abaixo); segurança 7,5 → **7,5**; desempenho 4 → **7,5**;
manutenibilidade 4,5 → **5,0**; campo 6 → **7,5**; média 6,2 → **7,4**.
- **Tempos medidos** (Matriz, 25.000 lançamentos, sem rede; `medir_orcamento.py` no scratchpad, não versionado): Financeiro > Despesas 97 ms no
  PC e 550 ms com CPU 4x mais lenta (eram 2,6 s e ~23 s); Relatórios 130/666 ms; Empresa 283/1.097 ms; abrir o app até os dados 1,6 s/5,6 s
  (o ponto fraco: a carga completa ainda baixa tudo). A Pecuária não foi medida em volume.
- **Código** (medido pelo navegador): `attachEvents` com 909 linhas (Matriz) e 2.206 (Pecuária); 95 funções com o mesmo nome em 2+ apps, 42
  idênticas e **53 que divergiram**; nenhum CI no momento da medição (instalado no mesmo dia, ver "Testes automáticos no GitHub"); 201 SQL no repo sem índice do que já rodou; 5 `sw_*.js`
  aposentados ainda lá; dinheiro em ponto flutuante (97 `reduce` no Matriz).
- **Segurança**: chave pública não lê nenhum objeto (inclui as cópias `zz_backup_dup4_*`); os apps chamam só 2 funções de criar usuário
  (`criar-usuario-cana`, `criar-usuario-combustivel`); as colunas `agencia` e `conta` de `contas_bancarias` foram **APAGADAS** (07/11/2026, `seguranca_03_apaga_agencia_e_conta.sql`, que só apaga se estiverem vazias; a tabela
  tem 0 linhas). Outras colunas de documento que a consulta dele achou: `fornecedores.cnpj`, `lancamentos_financeiros.cnpj_nota` e a visão `lancamentos_rateados` — CNPJ de
  fornecedor (dado de registro público, usado para casar com o ERP): ficam; backup automático e plano do Supabase não confirmados.
- **`saude_do_banco_01.sql` rodada de novo por ele em 07/11/2026 (depois de todas as limpezas): 21 das 24 checagens OK** (eram 18). Agora
  OK: conta #107 (B2), pesagens com 0 kg (D3), `erp_id` repetido, geral sem partes, rateio que não fecha, financiamentos e cadastros. Seguem em
  ATENÇÃO, todas esperadas: **A4** 22 receitas em centro de saída, R$ 339.094,22 (ele tinha deixado como estava; **RESOLVIDO em 09/11/2026**, ver "Centro de custo do lado certo");
  **D2** 10 lotes ativos sem pesagem há 60 dias (matrizes e cria não são pesados de rotina: a checagem poderia olhar só engorda); **A8** 509 linhas,
  R$ 672.552,40 (eram 515 e R$ 1.183.392,40; os 3 pares de 07/11 saíram, R$ 510.840,00). Desse A8, R$ 405.287,52 são as 8 linhas das 4 duplas que ele
  mandou manter (#497/#20805, #496/#20806, #500/#21098, #3018/#21300); sobram ~501 linhas e ~R$ 267 mil de valores repetidos pequenos (tarifas, salários
  e parcelas que se repetem; o maior item solto é #17328, R$ 11.340,00, ainda não classificado).
- **Para chegar a 8**: a manutenibilidade é o maior buraco (CI primeiro, depois núcleo comum `core.js` para as cópias, quebrar `attachEvents`);
  corretude pede recorrência explícita e dinheiro em centavos; segurança pede 2º fator para administradores, supabase-js no próprio site ou SRI e
  apagar as colunas de conta; campo pede letras de 12 px ou mais (ainda há 21 regras com 9 a 11 px no Matriz) e teste dele no tablet real.

### Financeiro paginado, travas do banco e o resultado da saúde do banco (06/11/2026)

Pedido do Eduardo logo depois do check-up: corrigir primeiro o desempenho, o conceito contábil da
compra de animais e as travas do banco.
- **Rodou `saude_do_banco_01.sql` em 06/11/2026**: 18 das 24 checagens OK (0 valor zero/negativo, 0 data
  fora de faixa, 0 despesa sem centro, 0 recorrente, 0 rateio que não fecha, 0 'geral' sem partes, 0
  `erp_id` repetido, 0 financiamento com defeito, 0 fornecedor duplicado). ATENÇÃO: **A4** 22 lançamentos
  em centro do lado errado (receita em centro de SAÍDA), R$ 339.094,22, ids recentes (~22969 a 22978);
  **A8** 515 linhas com mesmo fornecedor, valor e dia (R$ 1.183.392,40 somando as linhas; inclui os
  pares que ele mandou manter, #497/#20805 e #496/#20806; repetido não quer dizer duplicado);
  **B2** conta a pagar #107 com partes que não fecham (R$ 1.100,00); **D2** 10 lotes ativos sem pesagem
  há 60 dias; **D3** 2 pesagens com peso fora de 20 a 1.000 kg (#9 e #10).
  `saude_do_banco_02_detalhe.sql` (só leitura, ensaiada com 22 casos plantados) abre esses quatro itens:
  A4 por centro e a lista, A8 separado por origem (importação / acerto / à mão) e por documento do ERP
  com o que sobraria se ficasse um só de cada, B2 com as partes da conta, D2/D3 com nome do lote e a
  pesagem de antes e de depois.
- **Lista do Financeiro paginada** (`AEMatriz.html`): desenha 100 linhas (`LINHAS_FINANCEIRO_INICIAL`),
  "Mostrar mais" soma 200, o **total é sempre o do filtro inteiro** ("Total listado (N lançamentos)" quando
  há mais do que aparece); trocar aba, atividade, mês ou busca volta a 100. A busca espera 250 ms
  (`ESPERA_BUSCA_MS`): o texto vale na hora, o redesenho vem uma vez só e o foco volta ao campo. Medido com
  25.000 lançamentos: abrir despesas 2,6 s → 0,11 s no PC e ~23 s → 0,8 s com a CPU 4x mais lenta; tecla da
  busca 1 s → 1 ms; 287.733 → 1.621 elementos. `teste_financeiro_paginado.py` (24 checagens, falha no
  código anterior). Relatórios e Empresa foram resolvidos na "carga leve" abaixo.
- **`banco_travas_01_lancamentos.sql`** (ensaiado num Postgres descartável, com o papel `authenticated` e a
  tabela das partes fechada como em produção): (1) índice único parcial de `erp_id`; (2) lançamento em
  atividade `geral` (valor de R$ 1,00 ou mais) precisa ter as partes do rateio; (3) se tem partes, elas
  somam o valor (até 5 centavos). (2) e (3) são **gatilhos deferidos** (conferidos no fim da gravação):
  lançamento e partes gravados juntos na mesma transação passam (importação, scripts de rateio); gravar só o
  `geral`, ou mudar o valor sem mudar as partes, é recusado. A função é `security definer`: a tabela das
  partes é fechada a quem está logado, e sem isso a trava não enxergaria as partes e barraria até a edição
  normal de um `geral` do ERP. **Recusa instalar** se hoje houver `erp_id` repetido, `geral` sem partes,
  partes que não fecham, ou conta em aberto com parte em Geral (a baixa dela geraria `geral` sem partes). Desfazer no
  fim do arquivo. **Se o ERP for reimportado: gravar o lançamento e as partes na mesma transação.**
  **INSTALADAS no banco real em 06/11/2026** (ele rodou: os 7 itens da conferência final deram OK).
- **Resultado da `saude_do_banco_02_detalhe.sql` (ele rodou em 06/11/2026)**:
  - **A4** (receita em centro de saída, 22 lançamentos, R$ 339.094,22): todos do ERP, `geral`, de abril/2023
    (alguns de 2023/2024), em nome de familiares e da empresa dele: 18 "AJUSTE DE SALDO BANCÁRIO" (R$ 299.890,29),
    3 "OUTRAS MOVIMENTAÇÕES DE CAIXA" (R$ 37.203,93) e 1 manutenção da casa-sede (R$ 2.000,00). Parece acerto
    de conta no ERP, não venda. **Aguarda ele dizer se contam como receita; não mexer.**
  - **A8** ("sobraria R$ 615 mil se ficasse um só de cada" é teto, não duplicata): R$ 202.643,76 são exatamente
    as 4 duplas que ele mandou manter (#497/#20805, #496/#20806, #500/#21098, #3018/#21300); as tarifas do BB
    (R$ 1.500 ×3 e R$ 1.140 ×3, ids 24797 a 24802) são as 3 partes iguais que ele decidiu; salários repetidos
    (R$ 389,71 ×5, ids 836/848/860/872; R$ 2.241,90 ×2, ids 701/702) provavelmente são alocação por fazenda (a
    consulta não separa fazenda). **Só ele confere no ERP**: R$ 194.320 ×2 (30/06/2023, #14296/#14298), R$ 50.000
    ×2 (12/08/2024, #17113/#17115) e combustível R$ 11.100 ×2 à mão (15/03/2026, #2570/#2571). Nomes: só na pasta
    privada.
  - **B2** conta #107 (bateria do trator BH180, R$ 1.100): duas partes idênticas somando R$ 2.200.
    `corrige_conta_107.sql` apaga a de maior id (com guardas e cópia); ensaiado. **RODADO por ele em 06/11/2026**
    (uma bateria só, de R$ 1.100, lançada em dobro: a conta ficou com 1 parte de R$ 1.100). A trava `trg_rateio_fecha` só
    olha mudança nas partes: editar o VALOR do título sem tocar nas partes passa. Fechar isso pede uma gravação
    atômica do título (hoje apaga e regrava as partes em chamadas separadas).
  - **D2** 10 lotes sem pesagem há 60 dias: os de matrizes/cria não são pesados de rotina (a checagem deveria
    olhar só engorda). **D3** pesagens #9 (lote #3) e #10 (lote #33) de 11/08/2026 com 0 kg: aguardam ele.
- **Carga leve (06/11/2026, `AEMatriz.html`, `teste_carga_leve.py` 41 checagens, falha no código anterior)**. Medido
  com 25.000 lançamentos: um `loadAll()` fazia 120 consultas, baixava 75 mil linhas e redesenhava 18 vezes, e
  rodava depois de TODA gravação.
  - `loadAll(grupos)`: sem argumento recarrega tudo (entrar no app); com `['cadastros']`, `['lancamentos']`,
    `['financiamentos']` e/ou `['contas']` só o que mudou (`GRUPOS_AO_SALVAR` para o salvar genérico). Baixa de conta,
    juros de parcela e exclusão de contrato passam `'lancamentos'` junto (criam ou apagam lançamento).
  - A visão rateada é lida UMA vez por carga (`lerRateadosUmaVez`, `rateadosDaAtividade`): Relatórios e os
    resultados de Pecuária/Cana/Cereais filtram na memória (eram 4 leituras). Completa: 120 → 93 consultas,
    75 mil → 50 mil linhas, 18 → 2 desenhos. Salvar conta/contrato/funcionário: 3 a 8 consultas, quase 0 linhas.
  - `atualizarLancamentos(ids)` (salvar, dividir e excluir lançamento): busca só os ids no banco e deixa a memória
    igual à de um recarregamento completo (o banco manda; o que ele não devolve sai; exclusão que a permissão
    barrou continua na tela). Efeito colateral aceito: gravação de OUTRA pessoa só aparece na próxima carga completa;
    por isso voltar à aba depois de 10 min (`MINUTOS_ATE_RECARREGAR`, sem formulário aberto) recarrega tudo.
    A venda de animais continua com `loadAll(['lancamentos'])` (mexe em lote e abate).
  - `renderCarga()`: os carregamentos de fundo pedem desenho e os pedidos juntos viram um (60 ms).
  - `vigentesNoMes` agrupa as despesas uma vez por lista (`gruposDeVigentes`, WeakMap) e `doTipo` filtra por tipo
    uma vez por lista; `lancamentosFiltradosRelatorio` é guardada. Mesma resposta e mesma ordem (fuzz de 2.800
    comparações no teste). Listas do state são TROCADAS, nunca alteradas no lugar: não mutar `state.lancamentos`.
  - Ordenar a lista do Financeiro por data com `localeCompare` custava 160 ms: virou comparação direta (ISO).
  - Medido (PC, 25 mil): Relatórios 942 → 59 ms; Empresa (1ª vez) 2.045 → 176 ms; Operacional 232 → 20 ms.
- **Lista de compras de animais (ele rodou `compra_animais_01_lista.sql`, 06/11/2026)**: 68 lançamentos de 2023 a
  2026, **todos sem lote e sem nº de cabeças**. Giro (centro COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE) 38
  lançamentos, R$ 2.943.640,27 (2023 R$ 961 mil, 2024 R$ 1,16 mi, 2025 R$ 762 mil, 2026 R$ 56 mil); matriz (centro
  COMPRA DE MATRIZES + as lançadas à mão com "matriz" na descrição) 14, R$ 1.428.610,55; "?" 16, R$ 131.096,56
  (R$ 108.200 de animais lançados à mão no centro **INVESTIMENTO EM ANIMAIS**, que é o nome da classe usado como
  centro e não diz se é matriz ou giro; R$ 19.000 de equinos; R$ 3.896,56 de parcelas da cooperativa em "ativos").
  Candidato a duplicata: R$ 30.400 do mesmo vendedor à mão em 13/07/2026 (#508) e importado em 18/08/2026 (#22173).
  Matrizes de 2026: R$ 964.249,71 (inclui as 2 duplas dele, #490/#491 e #496/#497 + #20805/#20806). Fechar a
  classificação = mover as 8 lançadas à mão para um dos dois centros (a classe sai do centro, sem coluna nova).
- **Lotes (ele rodou `compra_animais_02_lotes.sql`, 06/11/2026)**: 15 lotes, **todos com início em 25/07/2026 ou depois**
  (os lotes foram recadastrados nessa data) e **não existe venda registrada (abates) antes de 26/07/2026**. Logo a
  compra de 2023 a 2025 não casa por data com lote nenhum, e o custo dos animais vendidos antes de julho/2026 não
  tem lote nem cabeças para ser casado. Vendidos: #32 Curral 1 (91 cab, R$ 568.818,12), #31 Curral 2 (106 cab,
  R$ 799.705,47), #37 Bezerros venda (131 cab, R$ 386.395,30), #8 Vacas de Descarte 2026 (67 cab, R$ 310.526,50).
  Em andamento: cria (#3 281, #33 89, #42 211, #44 101, #45 70, #43 65 cab), pasto (#9 234, #6 64), confinamento
  (#36 203, #39 163, #46 2). Plano do resultado econômico: ligar (lote + cabeças + classe) só as compras de
  2025/2026 que formam esses lotes; o histórico anterior fica só em caixa.
- **`apaga_pesagens_zero.sql`**: apaga as pesagens #9 (lote #3) e #10 (lote #33), 0 kg de 11/08/2026, a pedido dele
  (guardas, cópia em `zz_backup_pesagens_zero_2026_11_06`, recusa se houver peso individual real; ensaiado).
  **RODADO por ele em 06/11/2026**: 0 pesagens restantes, 0 com peso fora de 20 a 1000 kg.
- **Classificação das compras (decisões dele, 06/11/2026)**: #494 e #508 são matrizes; #502 é bezerro macho de corte
  (giro); #490/#491, #496/#497 e #492 (a descrição diz matriz) também vão para matriz.
  `compra_animais_03_classifica.sql` (ensaiado, **ainda não rodado**) passa as 8 lançadas à mão do centro ambíguo
  INVESTIMENTO EM ANIMAIS para COMPRA DE MATRIZES PARA REPRODUÇÃO (7) ou COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE (1);
  só muda o centro, com guardas, cópia e desfazer. **RODADO por ele em 06/11/2026 (2ª tentativa; a 1ª recusou, abaixo)**:
  7 compras foram para o centro #122 (COMPRA DE MATRIZES PARA REPRODUÇÃO, R$ 887.049,71) e 1 (#502, R$ 5.800) para o #99
  (COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE); `registrar_venda_animais`, `salvar_titulos` e `trg_titulo_valor_fecha`
  estão instaladas (conferência final: OK): venda e conta a pagar/receber gravam em uma transação (PGRST202 = caminho antigo).
  R$ 30.400 do Alemar: #508 (à mão, 13/07/2026, texto "Compra de animais para recria, engorda e…"), #22173 (ERP 5986, vence
  18/08/2026) e #22307 (ERP 6304, R$ 25.900, vence 10/09/2026; os dois do ERP são "recria, engorda e abate" = giro). Ele disse
  (06/11, depois) que **cada compra já diz no próprio texto o que é (matriz ou recria/engorda)**: pelo texto, #508 seria giro,
  mas eu o movi para matriz porque ele tinha dito matriz; **a conferir com ele** (e o extrato: parcelas ou duplicata?).
  **Resposta dele (06/11)**: os R$ 30.400 (#508 e #22173) "provavelmente são parcelas, valor igual e pagamento muito próximo":
  ficam os três lançamentos (#508, #22173, #22307); nada a apagar. Ele disse que rodou `confere_textos_das_compras.sql` mas não colou o
  resultado ainda. **Senha: fica com mínimo 6; ele conversa com o pessoal e depois muda para 10** (não mexer antes).
  **Alemar (06/11, depois)**: ele disse que a compra do Alemar é de MATRIZES e que não foi com dinheiro do custeio (as outras matrizes foram, e
  o custeio ainda não está lançado), mas, perguntado, decidiu que as duas parcelas do ERP (#22173 e #22307) **ficam como giro**: nada a mover
  (`alemar_erp_para_matriz.sql` foi apagado do repo). #508 fica em matriz.
  **Rodada 1 dele (06/11/2026) recusou: o banco tem 2 centros "COMPRA DE ANIMAIS%"**
  (nada foi aplicado). O script passou a escolher o destino pelo **nome exato** (e, havendo nomes iguais, o mais usado;
  empate: recusa listando os candidatos); `sql_2026_11_06_juntos.sql` regerado. O R$ 30.400 repetido (#508 × #22173): ele acha que é a mesma compra
  lançada duas vezes, **mas precisa ver se não são parcelas**; `confere_compra_repetida.sql` (só leitura) mostra os
  lançamentos desse vendedor com a observação do ERP. Se for a mesma compra, o ERP lançou #22173/#22307 como giro e
  ele diz que as compras desse vendedor são matriz: conferir a classe delas também.
- **Resultado com o custo dos animais (06/11/2026)**: como ele não consegue ligar as compras a lote/cabeças agora ("o
  histórico se acha depois, a criação do app foi depois da compra") e quer a implicação financeira no app, o bloco da
  Pecuária passou a mostrar também o **resultado com o custo dos animais de giro** = resultado − compra de giro do
  período (pago no período). Ainda não considera a variação do rebanho (precisa de inventário) e a matriz só entra
  no descarte. Quem vendeu ("de quem") já está em `fornecedor`; lote e cabeças ficam para depois.
- **Resultado de caixa da Pecuária (06/11/2026, `teste_pecuaria_compra_animais.py` 19 checagens, falha no anterior)**:
  `state.resultados.pecuaria.investimentosFinanceiro`; `classeInvestimentoPecuaria(centro)` (giro / matriz /
  "animais" a classificar / outro, pelo NOME do centro); `investimentosPecuariaNoPeriodo()`;
  Resultados > Operacional > Pecuária ganha o bloco "Investimentos da Pecuária" com o **resultado de caixa =
  resultado − investimentos**, e Resultados > Geral ganha o aviso. O resultado (receita − despesa) NÃO muda.
  **Financiamento recebido (07/11/2026)**: o bloco ganhou a linha "Financiamento recebido para a Pecuária" e o cartão "Caixa depois do
  financiamento" (= caixa + principal dos contratos NOVOS com atividade Pecuária e data da cédula no período; fora: contrato que já
  existia, de outra atividade, cancelado, importado do ERP e renegociação; mesma regra do fluxo da Empresa). Financiamento é dívida: não
  muda o resultado. Quando ele lançar o custeio das matrizes (Financiamentos, atividade Pecuária) aparece sozinho.
  Falta o **resultado econômico** (custo do lote casado com a venda, por cabeça; matriz só no descarte): pede
  lote e nº de cabeças em cada compra (formulário + preenchimento do histórico).
- **Gravação atômica (06/11/2026; achado 4/5 da revisão geral)**: duas funções do banco, `security invoker` (as
  permissões de quem chama continuam valendo), que gravam tudo numa transação ou nada. Os dois SQL estão no repo,
  ensaiados num Postgres descartável, e **ele ainda não rodou**; o app novo chama a função e, se ela não existir
  (`funcaoDoBancoNaoExiste`: PGRST202 / 42883), cai no caminho antigo, então nada quebra antes do SQL.
  - `venda_animais_atomica_01.sql`: `registrar_venda_animais(p_abate, p_lancamento)` grava abate + receita + baixa do
    lote, trava a linha do lote (`for update`) e confere o saldo DENTRO do banco (duas vendas ao mesmo tempo: só uma
    passa, a outra vê o saldo novo; testado com duas conexões). `teste_venda_atomica.py` (19) cobre o lado do app.
  - `titulos_atomico_01.sql`: `salvar_titulos(p_itens)` grava todas as parcelas de uma conta com as partes do rateio
    (ou edita uma conta trocando as partes) numa chamada só; e a trava `trg_titulo_valor_fecha` (deferida): mudar o
    VALOR da conta sem as partes fecharem é recusado (a `trg_rateio_fecha` antiga só olhava mudança nas partes: foi
    assim, provavelmente, que a conta #107 ficou com as partes em dobro). Recusa instalar se alguma conta já não fecha.
    `teste_titulo_atomico.py` (23).
  - O stub de teste ganhou `rpc` (`window.__RPC__[nome]` registra um tratador; sem ele responde PGRST202).
  - A baixa de conta já é um insert só com gatilho no banco (uma transação). Os fluxos de várias gravações do AE
    Pecuária (lote, pesagem) ainda não foram revisados nesse ponto.
- **Uso no campo (06/11/2026; achado 7 da revisão geral; `teste_campo_toque.py` 49 checagens)**. Medido num tablet
  com toque (`pointer: coarse`): AE Matriz 284 botões/campos com menos de 44 px nas 15 telas e 11 rótulos sem `for`;
  AE Pecuária 1.613 em 27 telas × 3 tamanhos. Agora, nos cinco apps (Matriz, Pecuária, Cana, Cereais, Combustível):
  - bloco `@media (pointer: coarse)` no fim do `<style>`: botão, aba, link-botão e campo com **min-height 44 px**
    (Apple 44, Material 48; WCAG 2.2 AA pede 24), caixas de marcar de 24 px; **o mouse do desktop fica como era**
    (botão pequeno com 30 px). Medida: Matriz 284 → 0; Pecuária 1.613 → 2 (link de nome estreito); 0 telas passam a
    rolar de lado. Classe nova que seja botão pequeno precisa entrar na lista desse bloco.
  - rótulo solto liga ao campo (`ligarRotulosAosCampos` no Matriz; `MutationObserver` nos outros): só quando há um
    rótulo e um campo com id no mesmo bloco; sem dúvida nenhuma, não chuta.
  - contraste de texto: `--bom` #007A2B (5,5:1; era 4,4:1), `--alerta` #B03A24 (6,0:1; era 4,4:1 no fundo de alerta) e
    `--ambar-texto` #7A4F08 (7,1:1; o âmbar #C98A2B dava 2,9:1) para TEXTO em âmbar; o âmbar continua para fundos.
  - `orientation` dos 6 manifestos virou `any` (o tablet gira). O AE Combustível não tem esses tokens (não trocados).
  - **Avisos na tela no lugar do `alert()` (07/11/2026; `teste_avisos_pecuaria.py` 25 checagens)**: `window.alert = avisar` no AE Pecuária
    (um bloco no começo do `<script>`, antes do cliente do Supabase). Os 137 `alert()` continuam no código e viram um aviso no TOPO
    da tela (não cobre o Salvar nem o botão +): não trava, botão ×, Esc fecha, até 4 ao mesmo tempo, some sozinho (9 s, mais para
    texto longo; `let TEMPO_AVISO_MS`) **menos o de erro** (texto começa com "Não foi possível", "Erro", "Falha", "Ocorreu um erro" ou
    "Os dados não carregaram": fica até fechar). Texto entra como TEXTO (HTML digitado aparece escrito), quebra de linha mantida,
    `role=alert` no erro e `role=status` no resto, botão de fechar de 44 px no toque, fica fora do `#root` (redesenhar não apaga).
    Cada aviso vai para `window.__AVISOS__` e para `console.info('[aviso] ...')`: **é por aí que os testes leem** (`teste_carga_pecuaria`,
    `teste_lote_racao`, `teste_parto_aborto_lote_numero` e `teste_qual_animal` ganharam um `page.on("console")`; o `page.on("dialog")`
    segue valendo para os `confirm()`, que continuam nativos: 21, pergunta que precisa de resposta). Pecuária nova com `alert()`
    novo já funciona sozinha. **Nos outros quatro apps também (07/11/2026, `teste_avisos_apps.py` 88 checagens, 22 por app)**: o MESMO
    bloco de JavaScript (`avisar`, logo depois da biblioteca do Supabase) e de CSS (`.avisos`, `.aviso`, antes do `</style>`; usa os
    tokens `--branco`, `--grafite`, `--cinza-claro`, `--ambar`, `--alerta`, `--alerta-bg`, que os cinco apps têm) em Matriz, Cana,
    Cereais e Combustível; `.aviso-fechar` entrou no bloco do toque (44 px). Quem mexer num bloco, mexa nos cinco. Os testes que
    liam o texto do `alert()` pela janela nativa (`teste_financiamentos_editar`, `_erp`, `teste_saldo_banco`, `teste_titulo_atomico`,
    `teste_venda_atomica`) ganharam um `page.on("console")` que lê o `[aviso] ...`; teste novo que precise do texto de um aviso lê
    por ali (ou por `window.__AVISOS__`), nunca pelo evento `dialog`. Nenhum `alert()` dos quatro apps é seguido de redirecionamento
    ou logout (conferido), então a faixa não some antes de ser lida.
- **Menu lateral do AE Matriz (06/11/2026; tablet e janelinhas em 08/11/2026; `teste_menu_lateral.py` 85 checagens)**. Pedido do Eduardo ("não gosto muito deste
  formato; quero as opções da barra maiores..."; ele viu as imagens e disse "ficou ótimo"). Em 08/11/2026, vendo o Painel no iPad
  dele (1180 px, que estava na faixa da barra de cima): "gostaria que as abas em cima ficassem em uma coluna lateral e os apps em
  quatro janelinhas ao lado direito" e, sobre a lista pequena de apps no pé da barra: "pode tirar". Três modos, só CSS:
  - **1160 px ou mais**: a barra vira uma coluna à esquerda (verde escuro) com o menu principal GRANDE (letra 16 px, botão de 54 px;
    15,5 px/48 px se a altura for menor que 900 px), usuário, Trocar senha e Sair no rodapé. **232 px de 1280 para cima; 196 px de
    1160 a 1279** (iPad deitado, 1180 e 1194): nessa faixa a letra é de 15 px, o conteúdo ganha padding menor (14 px) e as células
    das tabelas ficam mais justas (8 px; 5 px nas `tabela-compacta`) para o conteúdo (~940 px) mostrar as tabelas largas da Empresa e
    dos Financiamentos inteiras (`teste_empresa`, `teste_divida_empresa`, `teste_saldo_banco` medem 1280, 1194, 1180, 1160). **O corte é
    1160 de propósito:** em 1133 e 1100 a mesma coluna estourava os cards em 44 e 77 px; ali a barra de cima fica. O `.topbar` usa
    `display:contents` para a marca e o usuário virarem peças da coluna, então botões, `data-*` e a ordem do HTML não mudaram.
  - **760 a 1159 px** (tablet em pé, iPad mini): continua a barra de cima, com o menu maior (15 px, 46 px).
  - **menos de 760 px**: menu de celular (botão de menu) como antes.
  **Painel no celular (ate 760 px, 09/11/2026, pedido dele)**: os apps viram icones grandes (76 px), um embaixo do outro, com o nome ao lado (`AppIcone`, `.app-icones`; a linha inteira abre o app), sem as janelinhas, sem numeros e sem o aviso da copia de seguranca (`.painel-cartoes` e `.aviso-copia` escondidos so nessa largura). Do tablet para cima nada muda. **Indicadores do AE Combustivel no Painel** (08/11/2026, pedido dele; `carregarIndicadoresCombustivel`, `indicadoresCombustivelDe`): estoque nos tanques (entradas - abastecimentos + ajustes, tanques ativos), consumo no mes (L), custo no mes (L x custo medio ponderado das notas do tanque ate o dia; posto sem custo) e alertas abertos, as mesmas contas do Painel do AE Combustivel. Cada numero pede a permissao do modulo correspondente do Combustivel (sem ela, "—", porque o banco devolveria vazio e mostraria 0 falso). So informativo: o custo NAO entra em Resultados (`combustivelPorFrente` segue vazio; a compra do diesel ja e lancamento). **A lista pequena de apps (`AppsNaBarra()`, `.side-apps`) SAIU** (08/11/2026): os 4 apps são janelinhas no Painel, **duas por linha**
  a partir de 900 px (`.app-grid` em 2 colunas, cada janelinha com ícone, nome, status, o que o app faz, os números e "Abrir app";
  uma coluna abaixo de 900 px). Ícones próprios para Financeiro, Centros de Custo, Pagar/Receber e Usuários (antes quatro itens
  usavam o mesmo desenho de pessoa). O item "Pagar/Receber" quebra depois da barra (`<wbr>`) quando a setinha aperta o nome.
- **Menu lateral nos outros 4 apps (07/11/2026; tablet 08/11/2026; `teste_menu_lateral_apps.py` 79 checagens)**. Ele aprovou o desenho do Matriz e pediu
  nos outros. **AE Pecuária, AE Cana e AE Cereais** têm a mesma estrutura (`.topbar` + `.tabsrow` + `.main`) e ganharam o MESMO bloco
  de CSS (fim do `<style>`, "MENU LATERAL (tela larga, 07/11/2026; tablet deitado 08/11/2026)"): **de 1160 px** (como o Matriz; 196 px de 1160 a 1279 para o iPad deitado, onde ele pediu em 08/11/2026 todos os apps "dessa maneira"), coluna à esquerda de 232 px com o menu grande (os
  grupos `data-nav-group`; nome comprido quebra em duas linhas, ex.: "Formulação de Dietas") e, no rodapé, usuário, "← Painel" (link
  para o AE Matriz), Trocar senha e Sair; de 760 a 1159 px a barra de cima com o menu maior; celular como era. Medido em 08/11/2026 com `auditoria_1180` (scratchpad, não versionado): as 70 telas dos quatro apps em 1180 e 1194 px não rolam de lado; só o card "Por Lote" da Pecuária já rolava por dentro do próprio card antes (197 px; agora 261 px, a página não rola). A marca desenhada em
  verde escuro (cabeça de boi, haste da cana) ficava invisível no fundo verde escuro: CSS `.topbar .brand-mark [stroke=...]` troca
  para cor clara. O link `a.btn-sair` virou `inline-flex` (com o min-height do toque o texto ficava no topo). **AE Combustível** já
  tinha barra lateral própria (azul, `Sidebar()`): ficou com 244 px, menu grande (16 px, 54 px), usuário e botões embaixo
  (`order`), barra `sticky` na altura da tela. Nos apps de grade o `.tabsrow` rola por dentro quando há muitos grupos (Pecuária tem
  12), com o rodapé do usuário fixo. Sem a lista pequena de apps da barra: nesses apps o atalho é o "← Painel" (o hub é o Matriz).
- **Coluna do menu do AE Combustivel em tela baixa (09/11/2026, pedido dele)**: com 10 itens e um aberto (Frota tem 5 sub-abas), a coluna passava ate ~300 px da altura do iPad deitado e Rateio/Alertas/Administracao so apareciam rolando. Ate 900 px de altura: itens e sub-abas de 44 px, menos espaco, sem o texto "MVP" do rodape, e "← Painel", "Trocar senha" e "Sair" numa linha so (o nome do usuario vai para a dica do Sair); ate 800 px, sub-abas de 34 px. `teste_combustivel_menu_cabe.py`; o criterio de "menu grande" do Combustivel em `teste_menu_lateral_apps.py` passou de 46 para 44 px.
- **Menu do celular (☰) em Pecuaria, Cana, Cereais e Combustivel (09/11/2026, pedido dele: "3 risquinhos... todos com a mesma cara")**: ate 760 px a faixa de abas sumiu; o botao `BotaoMenuCelular()` (core.js) mostra "Grupo · Tela" e abre o menu inteiro numa coluna (com a setinha das sub-abas); escolher uma tela fecha. Aberto/fechado = classe `html.menu-celular-aberto` (sobrevive ao redesenho; fecha na fase de captura do clique). CSS no bloco "MENU DO CELULAR" dos quatro apps (muda so `--menu-sub-ativo`), o botao + da Pecuaria some com o menu aberto. O AE Matriz tem o dele (`state.mobileNavAberto`), mesmo desenho. Teste que toca no menu no celular tem de abrir o ☰ antes.
- **AE Combustivel no celular igual aos outros (09/11/2026, pedido dele)**: ate 760 px a barra azul virava uma faixa so de ~1.860 px (marca, botoes e os 10 itens do menu): o menu comecava fora da tela e o Sair saia cortado. Agora marca em cima, "← Painel"/"Trocar senha"/"Sair" inteiros embaixo dela e o menu numa faixa branca propria que se arrasta para o lado (item ativo em azul), como Pecuaria/Cana/Cereais. Ja era assim antes do menu lateral de 08/11. `teste_celular_topo_apps.py`.
- **Setinha com as sub-abas no menu, nos 5 apps (08/11/2026; `teste_menu_setinha.py` 173 checagens)**. Pedido do Eduardo: "uma setinha para ter a
  opção de clicar nas sub abas direto". `ItemDoMenu({chave, rotulo, icone, ativo, botao, subs})` em `core.js` desenha o item do menu: com **2 ou
  mais sub-abas** vira `.nav-grupo` > `.nav-linha` (o botão do item, que continua com o mesmo `data-nav-group`/`data-nav` de sempre, e a setinha
  `[data-nav-seta]`) + `.nav-sub` com um `[data-menu-sub]` por sub-aba; com uma página só devolve o botão sozinho, como era. **Sanfona: um item
  aberto por vez**; sem nada guardado abre o item da tela atual; o que ficou aberto (ou `''` = tudo fechado) vai para o `localStorage`
  (`ae_menu_aberto_v1_<NOME_DO_APP>`). Clicar no **nome** do item guarda aquele item como aberto (ouvinte de captura, antes do clique do app, que
  já redesenha); a setinha só abre/fecha a lista e **não troca de tela**; clicar numa sub-aba vai direto (ouvinte delegado em `core.js`:
  `state.page = valor`, ou `irParaSubAbaDoApp(valor)` se o app definir). **Atributo próprio `data-menu-sub`, não `data-subnav`**: os testes e
  os botões de dentro da tela usam `[data-subnav="x"]` e uma segunda cópia quebraria o modo estrito do Playwright.
  - Pecuária, Cana, Cereais e Combustível: as sub-abas são as páginas do grupo (as mesmas `.subtabs` de dentro da tela, que continuam lá).
  - **Matriz** (`SUBABAS_DO_MENU`, `irParaSubAbaDoApp`): Resultados (Geral, Operacional, Relatórios, Empresa), Financeiro (Despesas, Receitas,
    Investimentos, Custo por hectare) e Pagar/Receber (A Pagar, A Receber); o valor é `pagina|aba` e escolhe a tela **e** a aba de dentro
    (`subAbaResultados`, `abaFinanceiro`, `abaContas`; trocar de aba limpa o que a aba limpa: limite da lista, contas marcadas).
  - **Onde aparece**: só onde o menu é coluna (1160 px para cima; Combustível de 761 px) e no painel do celular do Matriz (claro, fecha ao escolher).
    Na barra de cima (tablet em pé) e na barra rolável dos outros apps no celular a setinha e a lista ficam escondidas e os envoltórios são
    `display:contents` (a barra se desenha como antes). O item ativo e a setinha formam uma pílula só (cor do app: verde; azul no Combustível).
    CSS do bloco "SETINHA COM AS SUB-ABAS" copiado nos 5 apps (`core.css` segue sendo uma etapa futura): quem mexer num, mexa nos cinco.
- **Política de segurança de conteúdo (CSP, 06/11/2026; `teste_csp.py` 43 checagens)**: `<meta http-equiv=Content-Security-Policy>`
  no `<head>` dos cinco apps. Cada app só pode falar com o Supabase do projeto (`connect-src` https e wss
  `kmkystqgpvmzrccxvyaz.supabase.co`), carregar script da `cdn.jsdelivr.net` (a biblioteca fixa em 2.118.0), css do
  `fonts.googleapis.com` e fonte do `fonts.gstatic.com`; `default-src 'none'`, `object-src 'none'`, `base-uri` e
  `form-action` 'self'. **Sem `'unsafe-eval'`** (script injetado não manda dado para fora, não faz eval); `'unsafe-inline'`
  continua em script e estilo porque cada app é um arquivo só com tudo embutido. **Se um dia o app precisar de outro
  serviço (mapa, clima, WhatsApp API...), o endereço entra nessa política nos cinco apps.** Provado: página de controle sem
  política deixa passar fetch/imagem/script/eval de outra origem, e o app barra os quatro com a violação registrada pelo
  navegador; os cinco apps percorrem as telas sem violar a própria política; e, com a biblioteca REAL do supabase-js 2.118.0
  (baixada só para esse teste, fora do repo), `createClient`, `auth.getSession`, consulta e `rpc` funcionam dentro da política.
  **Decidido por ele em 07/11/2026: a senha fica com mínimo de 6 caracteres** (não mudar para 10); o mínimo é 6 em 4 telas por app, e o mínimo
  do Auth do Supabase é uma configuração do painel dele (Authentication > Policies). SRI/auto-hospedar o supabase-js: não
  feito (mexeria no cache offline do service worker e nos ~50 testes).
- **Compra de animais (decisões dele, 06/11/2026)**: matriz só é reconhecida no DESCARTE (sem depreciar: "ela vale o
  valor dela em carne"); o formulário de compra ganha lote e nº de cabeças (colunas `lote_id` e `quantidade` já
  existem); ele pediu a LISTA das compras para separar matriz de giro: `compra_animais_01_lista.sql` (só leitura,
  ensaiado), a sugestão vem do centro (COMPRA DE MATRIZES = matriz; COMPRA DE ANIMAIS = giro). Custeio que pagou os
  animais é dívida em Financiamentos (juros é a despesa).

### Pecuária: fila offline sem duplicar (client_uuid)

Pedido do Eduardo em 02/11/2026 (achado da revisão). Com sinal fraco, o banco
gravava o lançamento e a resposta se perdia: o app guardava na fila e
reenviava, e o lançamento (e a baixa de estoque) ficava em dobro. Agora
`salvarOuEnfileirar` cria uma chave no 1º envio (`campos._chave`, viaja na
fila) e `inserirUmaVez()` grava em `client_uuid`; o banco recusa chave
repetida (índice único parcial, `pecuaria_fila_offline_sem_duplicar.sql`,
10 tabelas: saidas_racao, leituras_cocho, pasto, producoes_racao, abates,
reproducao_custos, diagnosticos_gestacionais, partos, desmamas, pesagens) e
o app pega a linha que já existe e **só completa o que faltou**: baixa de
estoque (`movimentos` pela FK), receita da venda (`abate_id`), pesos por
animal (`pesagem_id`). O desfazer de cada tipo também apaga a parte que pode
ter entrado com a resposta perdida (baixa órfã). Antes do SQL (coluna não
existe) grava como antes (`tabelasSemChave`). Venda: com a receita já
gravada, conta como terminada (a baixa do lote vem logo depois; se só ela
faltou, não se refaz). `teste_fila_sem_duplicar.py` (falha no código antigo).
**SQL rodado pelo Eduardo em 02/11/2026**: as 10 tabelas com coluna e índice.

### Pecuária sem internet (07/11/2026)

Pedido do Eduardo: "preciso que os funcionários consigam lançar com o app off-line". A fila de lançamentos (abaixo) já
existia, mas o app só abria com lotes, dietas, ingredientes e animais se a internet respondesse; sem sinal na abertura as listas
dos formulários ficavam vazias. Agora (`AEpecuaria.html`, `loadAll` = `carregarTudo`):
- **Cópia no aparelho** (`DADOS_OFFLINE_KEY`, `lerDadosOffline`/`guardarDadosOffline`): toda carga que termina bem guarda os
  cadastros crus (ingredientes, dietas, lotes, animais, perfis já mapeados: sem e-mail nem telefone) e o histórico pequeno de
  reprodução (partos, desmamas, diagnósticos, inseminações, pesagens, preços da @), **por usuário** (`uid`). Aparelho sem espaço
  guarda só os cadastros. **Sair apaga a cópia.** Estoque, custo e resultado dependem do histórico pesado e só aparecem completos
  com internet (o aviso diz isso).
- **Abertura**: com a tela vazia e uma cópia do mesmo usuário, mostra a cópia NA HORA e atualiza por cima quando a rede responde
  (`state.dadosDoAparelho`). Aparelho sem rede (`navigator.onLine` falso) nem tenta (com login vencido a biblioteca esperaria
  ~25 s). Rede que não responde em 25 s, ou consulta que falha por rede, com algo na tela: fica em **`state.semSinal`**, sem
  apagar as listas e sem o aviso vermelho. Falha que não é de rede com algo na tela mantém as listas e mostra o aviso vermelho.
  Sem cópia e sem nada na tela, tudo como era (aviso vermelho com "tente de novo"). Cópia de outro usuário não é usada.
- **Janela aberta não é redesenhada** por baixo de quem digita quando a carga termina (só no modo cópia/sem sinal).
- **Volta o sinal**: `aoVoltarSinal()` (evento `online`, a cada 30 s e 3 s depois de abrir) sobe a fila e, se estava na cópia,
  recarrega, **sem janela aberta e sem empilhar cargas** (`cargasEmCurso`). "Tentar agora" avisa se ainda não tem sinal.
- **Entram na fila** (e portanto funcionam sem sinal): saída de ração (confinamento, cria, pasto), leitura de cocho, produção de
  ração, inseminação, diagnóstico, parto, desmama, pesagem e venda. **Não funcionam sem sinal: Manejo (sessão animal a animal),
  cadastro de lote/animal, edições e exclusões** (a mensagem diz "sem internet", `textoErroBanco`).
- Quem usa o app tem de ter aberto **com internet pelo menos uma vez** depois desta versão para existir a cópia.
- `teste_stub_supabase.js` ganhou rede caída (`window.__SEM_REDE__` ou `localStorage.__sem_rede = '1'`, que sobrevive a
  recarregar). `teste_offline_lancar.py` (47). `teste_carga_pecuaria.py` passou a abrir "a frio" (sem cópia, tela vazia) nos casos
  de aviso vermelho: com dados na tela a falha de rede agora vira "sem internet".

### Matriz: custo dos animais por lote, o resultado econômico da Pecuária (07/11/2026)

Continuação das decisões de 06/11 (matriz só no descarte; lote e nº de cabeças na compra). **Sem SQL novo**: usa `lote_id` e `quantidade`
de `lancamentos_financeiros`, que já existiam (e a visão `lancamentos_rateados` já as expõe).
- **Compra de animais ganhou lote e nº de cabeças** (`mostraCamposCompra`: lançamento do tipo investimento cujo centro é compra de
  animais/matrizes/"a classificar", `ehCompraDeAnimais`). Escolher o centro mostra ou esconde os campos (a tela redesenha só quando muda).
  **Lote e cabeças andam juntos** (um sem o outro é barrado), cabeça é número **inteiro** ≥ 1, a unidade grava `'cab'`. Compra sem os campos
  segue valendo (as antigas ficam como estão); editar a antiga mostra os campos para ligar a um lote.
- **Bloco "Custo dos animais por lote"** (Resultados > Operacional > Pecuária, `custoAnimaisPorLote`, `BlocoCustoAnimaisPorLote`): por
  lote com compra ligada, **R$ por cabeça = custo das compras ÷ cabeças compradas; custo dos vendidos = R$ por cabeça × vendidos (no máximo
  as compradas); margem sobre o animal = receita das vendas do lote − custo dos vendidos**; mais cabeças e valor a custo em estoque. Vale a
  **vida inteira do lote** (não segue o filtro de período) e é **antes** de ração, custo fixo e juros (o custo completo do lote está no
  Painel de Resultado dos Lotes do AE Pecuária). Animal vendido além do comprado (cria da fazenda) entra na receita sem custo e a tela
  avisa. **Matriz ligada a lote fica à parte** (ativo; só vira resultado no descarte). Compras de giro sem lote ou sem cabeças ficam numa
  lista recolhível com Editar (as 15 mais recentes). Lê `state.lancamentos` (precisa do Financeiro), `state.vendasPec` e `state.lotesPec`.
- Não está nem estará nesta conta: variação do rebanho sem inventário, depreciação, o custo da matriz no descarte (a compra de matriz não
  é por animal). `teste_custo_animais_lote.py` (27): contas à mão com dois lotes, matriz, compras sem lote, formulário e ligar uma compra antiga.
- **Decisão dele (07/11/2026): custo por MÁQUINA só daqui para a frente**; o histórico (despesas antigas, ERP) não será ligado a
  equipamento ("o que passou dá para ver como um todo").

### Combustível: custo por hora (ou km) de cada equipamento (07/11/2026)

O AE Combustível já tinha equipamentos (horímetro/hodômetro), manutenção preventiva (troca de óleo/filtro, com alertas) e consumo por
equipamento; faltava o **custo por hora**, que o Inttegra e os outros trazem em "Máquinas". Rateio > Por Equipamento agora mostra, no
período do filtro: litros, consumo (L/h ou L/km), **horas/km** (maior menos menor leitura do medidor nos abastecimentos do período),
combustível (R$, custo médio do tanque), **manutenção** (soma do **custo** preenchido na aba Manutenção, por data), custo total e
**R$ por hora/km = (combustível + manutenção) ÷ horas/km**. Equipamento só com manutenção no período também aparece; sem medidor ou
com menos de 2 leituras fica sem custo por hora. **Não inclui** depreciação, financiamento da máquina nem mão de obra.
- **Peças e serviços do Financeiro (07/11/2026, pedido dele: "sim")**: a despesa do AE Matriz ganhou o campo opcional **Equipamento**
  (só despesa; lista os equipamentos ativos do Combustível, mais o inativo que já estava ligado), gravado em
  **`lancamentos_financeiros.equipamento_id`** (FK para `equipamentos`, índice parcial; SQL `lancamentos_equipamento_01.sql`, ensaiado num
  Postgres descartável, repetível, **ele ainda precisa rodar**). Fora da conta: o resultado, o rateio e as políticas de acesso não mudam
  (a coluna herda as da tabela). `lancamentoToRow` só manda `equipamento_id` quando há equipamento, ou `null` quando se TIRA um que o
  lançamento já tinha (`_equipamentoOriginal`): o app funciona antes do SQL (a coluna nem é enviada). "Dividir entre as atividades" leva o
  equipamento para cada parte; baixa de conta a pagar NÃO leva (a conta a pagar não tem o campo): para ligar um gasto que nasceu de uma
  baixa, edite o lançamento em Financeiro. O Matriz lê `equipamentos` (`state.equipamentos`, fora do alerta de erro de carga: sem acesso
  à tabela o campo só não aparece). No Combustível, `carregarPecasEquipamento()` lê as despesas ligadas (RLS do Financeiro: quem não tem
  acesso vê a coluna vazia; antes do SQL a consulta falha e a coluna fica vazia, sem erro) e soma ao custo total e ao R$ por hora; lançamento
  só com o mês conta no dia 1; receita e gasto sem equipamento não entram. **Mesmo gasto lançado na Manutenção (custo) e no Financeiro
  conta duas vezes**: a tela avisa. Lançamentos antigos (ERP, 25 mil) não têm equipamento: o custo por hora só se completa daqui para a
  frente ou ligando os antigos à mão. Colunas de Por Equipamento, na ordem: R$ por hora/km, custo total, combustível, manutenção, peças e
  serviços, horas/km, consumo, volume (o que mais importa à esquerda). `.main{min-width:0}` no Combustível: tabela larga rola dentro do card.
- SQL **`combustivel_manutencao_02_custo.sql`** (`manutencoes.custo`, opcional, com trava de não negativo; ensaiado num Postgres
  descartável, repetível): **ele ainda precisa rodar**. O app funciona antes: o campo de custo só vai ao banco quando tem valor
  (`soSeTiverValor`; limpar um custo que já existia manda null) e o erro de coluna faltando vira "Rode combustivel_manutencao_02_custo.sql".
- `teste_custo_hora_equipamento.py` (20): contas à mão com trator (horímetro), caminhão (hodômetro), gerador (sem medidor), colhedora
  (só manutenção) e um abastecimento de setembro que não entra; peças e serviços do Financeiro ligados ao equipamento.

### Pecuária: planilha de manejo para o curral sem sinal (07/11/2026)

Ideia do Eduardo no lugar de fazer o Manejo (sessão animal a animal, cheia de gravações em cadeia) funcionar sem internet:
o funcionário preenche **`Planilha_de_Manejo.xlsx`** (modelo na raiz do site, gerado por `gerar_planilha_manejo.py`: listas de
escolha, colunas cinza nas ações em "Não") no celular, e com internet o app **importa** em Manejo > "Importar planilha de manejo".
- **Leitura**: SheetJS 0.20.3 em `vendor/xlsx.full.min.js` (servido pelo próprio site, `script-src 'self'` da CSP; só é carregado
  quando se escolhe um arquivo). A planilha é lida pelos **textos dos rótulos** (`PLANILHA_MANEJO_ROTULOS`/`_COLUNAS`), não pela
  posição das células: pode inserir linha, **não renomear títulos**. Mudou um rótulo no gerador, mude no app e no teste.
- **Validação com as mesmas regras do Manejo ao vivo** (`montarPlanoManejo`): número só com algarismos, zero à esquerda não conta
  (57 usa o cadastro 057), animal novo pede raça (e sexo no lote misto), peso, raça do touro, diagnóstico, desmama (acha o bezerro
  sem desmama pelo número da mãe; recusa mãe sem bezerro, já desmamado ou repetida), permissão por ação, lote encerrado, destino
  diferente da origem. 4ª inseminação, número repetido e brinco parecido (11 x 11099) são **aviso**, não impedem.
- **Prévia antes de gravar**; qualquer erro desliga o botão ("corrija a planilha e carregue de novo", nada foi gravado): não existe
  importação parcial, para não duplicar ao reimportar a planilha corrigida.
- **Gravação** com `gravarAnimalDoManejo(m, d)`, a função **extraída de `salvarAnimalManejo`** (cadastro, contagem dos lotes, peso,
  IATF, diagnóstico, protocolo, desmama) que o Manejo ao vivo também usa: um manejo novo, uma pesagem com a média, finalizado no fim.
  Rede que cai no meio: para, diz a linha, e **Continuar** retoma sem repetir (o manejo fica aberto até terminar). Sem internet ao
  importar: avisa, não grava nada.
- **Mesma planilha duas vezes**: o app lembra o conteúdo escrito (carimbo `aepecuaria_manejos_importados_v1`, por aparelho) e pede
  confirmação. Não depende do que o app deduz (animal novo muda depois de importar).
- Fora de escopo: o Manejo ao vivo continua pedindo sinal. `teste_manejo_planilha.py` (64, usa a planilha modelo de verdade e o app
  servido por http).

### Matriz: cópia de segurança e curva ABC (07/11/2026)

Pesquisa de mercado (Inttegra, Aegro; relatório na pasta privada, `pesquisa_mercado_2026-11-07`): o que o AE não tinha e os
concorrentes têm era **backup** e **curva ABC**. O plano gratuito do Supabase provavelmente não guarda cópia automática (as fontes
divergem: conferir no painel). Por isso:
- **Cópia de segurança** (AEMatriz.html, Usuários, **só admin**; `TABELAS_COPIA`, `baixarCopiaDeSeguranca`): baixa UM arquivo
  `AE_copia_AAAA-MM-DD.json` com as tabelas que os cinco apps leem (financeiro, contas, financiamentos, fazendas, funcionários,
  pecuária, cana, cereais, combustível), paginadas de 1000 em 1000, e o resumo com a contagem de cada uma. Tabela que não existe
  ou que a permissão não deixa ler fica de fora e aparece no aviso (não derruba a cópia). **Não entram** `lancamento_rateios`
  (fechada a quem está logado; a visão `lancamentos_rateados` leva o resultado do rateio), `contas_bancarias` e `log_alteracoes`.
  O segundo botão baixa os lançamentos carregados em **CSV** (BOM, ponto e vírgula, vírgula decimal, data dd/mm/aaaa, recorrente
  marcado, texto que o Excel leria como fórmula neutralizado) para o contador. A tela guarda a data da última cópia deste aparelho
  (`ae_matriz_ultima_copia_v1`) e o **Painel lembra o admin** (`AvisoCopiaDeSeguranca`, `DIAS_AVISO_COPIA` = 8) quando não há cópia ou ela é antiga. O arquivo tem valores e nomes: guardar em lugar seguro, nunca no repositório. Tabela nova que o
  app passe a ler entra em `TABELAS_COPIA`. Restaurar é por script (não há botão de restaurar). `teste_copia_seguranca.py` (32).
- **Curva ABC das despesas** (Resultados > Relatórios, `curvaAbcDespesas`): por centro de custo e por fornecedor (os 25 maiores),
  da maior para a menor, com % e % acumulado; **A = até 80% do gasto** (um item é A se o acumulado ANTES dele ainda é menor que
  80%), **B até 95%, C o resto**. Só despesa (investimento e receita ficam de fora); segue o período e os filtros da aba;
  fornecedores com nome igual (maiúscula, acento, espaço) somam juntos. `teste_curva_abc.py` (18).
- Ainda sem os concorrentes: depreciação e peças/serviços por máquina (custo por hora hoje = combustível + manutenção com custo), Manejo ao vivo sem internet (hoje: planilha de manejo), livro
  caixa/LCDPR (depende do escritório dele) e backup automático (GitHub Actions para repositório PRIVADO: artefato de repositório
  público é baixável por qualquer um).

### Núcleo comum dos apps (`core.js`, 07/11/2026)

**O problema**: cada app era um HTML com tudo dentro, e o que era igual entre eles estava **copiado** (mais de 90 nomes de função em 2 ou mais apps;
53 já tinham divergido). Um conserto entrava num app e ficava de fora dos outros — o mesmo tipo de erro que o `acessoTotal` e o `pareceErroDeRede` mostram.

**O que mudou** (nada na tela: 184 telas dos 5 apps, em 1280 e 390 px, comparadas byte a byte antes e depois — todas iguais):
- `core.js` (todos os 5 apps) e `core_lavoura.js` (só Cana e Cereais), classic scripts com as funções **globais**, como sempre foram. Tags logo depois da
  biblioteca do Supabase e antes do script do app: `<script src="core.js?v=...">`. A política de segurança (CSP) já aceitava (`script-src 'self'`).
- Saíram dos apps 1.793 linhas (Cana e Cereais ficaram com ~1.100 linhas cada, 38% menos); entraram 753 nos dois núcleos.
- Dentro do núcleo só se usa o que é do app **no momento da chamada** (`state`, `db`, `PERFIL_CACHE_KEY`, `CADASTROS`...): essas constantes e o estado
  continuam no script de cada app. Função nova que for **igual em 2 ou mais apps vai direto para o núcleo**, não para um app.

**O `?v=`** é a impressão digital (10 primeiros caracteres do SHA-256, fim de linha CRLF/LF não conta). Sem ele o navegador pode juntar HTML novo com
`core.js` velho do cache (GitHub Pages guarda 10 min) e o app quebra até vencer. **Depois de mexer em `core.js`/`core_lavoura.js` rode
`python atualiza_nucleo.py`** (troca o `?v=` nos apps); o `teste_nucleo.py` falha se esquecer. Quem carrega o quê está em `NUCLEOS` dentro desse script.

**Offline** (`sw.js`): `./core.js` e `./core_lavoura.js` estão na lista `SHELL`. O `sw.js` guarda cada arquivo com o `?v=` no endereço; a busca no
cache procura **primeiro o endereço exato** e só depois qualquer versão do mesmo arquivo, e ao guardar uma versão nova **apaga as velhas** do mesmo
arquivo (`limpaVersoesAntigas`). Isso foi achado pelo `teste_nucleo_offline.py`: o `sw.js` antigo (`ignoreSearch` direto) devolvia a cópia mais
ANTIGA, e depois da primeira atualização do núcleo o app offline rodaria HTML novo com núcleo velho. Versão do cache (`ae-v5`) não foi trocada.

**Fase 2 (07/11/2026): login, perfis e acesso no núcleo, e a lista de cópias zerada.** `fazerLogin`, `ModalUsuario`, `PageAdminUsuarios`, `souAdmin`,
`papelPill`, `opcoesDePapel`, `currentGroupKey`, `gruposVisiveis` e `fetchAllRows` passaram a ser uma só, em `core.js` (`DIVIDA_CONHECIDA` do `teste_nucleo.py`
ficou **vazia**). O que não era igual foi decidido assim (só o que não muda o que a pessoa vê/pode, ou conserta erro):
- **`temPermissao`** única (`acessoTotal()`), **Combustível com o proprietário em acesso total** (ele disse "Sim"; o banco já dava: `tem_permissao()` chama
  `acesso_total()` = admin ou proprietário ativo, conferido ao vivo; o app é que estava mais restrito). Tela de Usuários segue só do admin (`souAdmin()`).
- **A Pecuária não tem mais `souAdmin` próprio**: o dela era "admin ou proprietário", ou seja, `acessoTotal()`; as 14 chamadas viraram `acessoTotal()` (mesmo
  resultado). O `souAdmin()` do núcleo é só administrador, como nos outros quatro.
- **Tela de acesso não rebaixa mais ninguém** (achado e corrigido nos 5 apps): o seletor de perfil de cada app tinha uma lista própria e quem tinha perfil que
  a lista não trazia caía no PRIMEIRO item, e Salvar o rebaixava sem aviso (Pecuária: gestor/operador/encarregado viravam Colaborador; Matriz, Cana, Cereais:
  consultor virava Operador; Combustível: proprietário/colaborador/consultor). `opcoesDePapel(lista, atual)` mantém o perfil atual marcado. A lista de cada app
  não mudou (decisão de produto dele). O banco aceita 7 perfis: admin, proprietario, gestor, encarregado, colaborador, operador, consultor.
- **Escape**: `ModalUsuario` e `PageAdminUsuarios` passaram a escapar tudo (o Matriz, o Combustível e o Cana/Cereais deixavam a senha digitada e a mensagem de
  erro sem escape; o Cana/Cereais também o login digitado e o da lista). Era "auto-ataque" (só o administrador digitando), mas a senha com aspas truncava o campo.
- **`papelPill`**: gestor e consultor em amarelo em todos (na Pecuária só o consultor era; ali o gestor agora também fica amarelo).
- **Leitura de tabela inteira em páginas**: eram três códigos (`fetchAllRows(consulta)` no Matriz e no Combustível, `buscarTudo(consulta)` idêntico na Pecuária e
  `fetchAllRows(tabela, ordem)` no Cana/Cereais). Ficou só `fetchAllRows(()=>db.from(...).select(...).order(...).order('id'))` no núcleo; a Pecuária chama o mesmo
  nome (27 chamadas renomeadas) e o Cana/Cereais passa a consulta montada, com o `.order('id')` de desempate que já tinham.
- **`fazerLogin`**: igual nos 5; o passo extra do Combustível (conferir alertas depois da carga) agora é a função `aoEntrarDepoisDaCarga`, que o app define se
  precisar.
**Fase 3 (07/11/2026): abertura do app, login e sessão no núcleo.** `initAuth`, `loadPerfil`, `fazerLogout`, `LoginPage`, `AguardandoLiberacao`,
`pareceErroDeRede`, `rowToPerfil` e `DOMINIO_LOGIN` agora são os mesmos nos 5 apps (`core.js`). O que é de cada app vem por constantes e ganchos opcionais
(`typeof` antes de chamar): `NOME_DO_APP`, `SLOGAN_DO_APP` (só o Matriz), `corrigirPaginaDoPerfil()`, `aoIniciarApp()`, `aoEntrarDepoisDaCarga()`,
`aoRetomarSessao()` (fila do Combustível), `aoSair()` (Pecuária apaga a cópia offline; Combustível e Cana/Cereais voltam à 1ª tela). Achados e corrigidos,
**os dois mexem no campo**:
- **`TOKEN_REFRESHED`**: só o Matriz ignorava o evento. Nos outros quatro, a cada hora (renovação do token do supabase-js) o app recarregava o perfil, redesenhava
  a tela e baixava os dados de novo: **um formulário aberto com texto digitado e não salvo perdia o texto** (na Pecuária, um lançamento no meio). Agora só guarda
  a sessão nova.
- **Primeira abertura sem sinal** (login guardado, perfil nunca guardado neste aparelho): só Matriz e Pecuária diziam "sem conexão" com o botão "Tentar
  novamente"; **Cana, Cereais e Combustível diziam "ainda não há acesso liberado para esta conta"** (falso, sem botão). Agora os cinco dizem a verdade; o botão
  tem um ouvinte só (delegado, em `core.js`; o Matriz e a Pecuária perderam o próprio no `attachEvents`).
- `pareceErroDeRede` é a da Pecuária (aparelho sem rede, `TypeError`, "Failed to fetch"/"Load failed"/"NetworkError"): a do Matriz olhava só três palavras e a do
  Cana/Cereais/Combustível aceitava qualquer "failed" (por exemplo "authentication failed" virava "sem sinal" e usava o perfil guardado).
- Login: o texto digitado e a mensagem de erro entram escapados nos 5 (antes só na Pecuária). Visual: o texto da tela "aguardando liberação" é o da Pecuária em todos
  (o Matriz tinha outro tamanho/cor e dizia "administrador da matriz"). O `rowToPerfil` do Matriz e da Pecuária passou a guardar `frentes` (só o Combustível usa).
- O stub dos testes (`teste_stub_supabase.js`) guarda os ouvintes de `onAuthStateChange` em `window.__authCallbacks` para o teste disparar `TOKEN_REFRESHED`.
**Ainda diferentes de verdade** (cada app tem a sua, nada decidido): `loadAll`, `Header`, `Topbar`, `brandMark`, `Modal`, `attachEvents`, `PageCadastro`/`salvarCadastro`
(Cana, Cereais, Combustível), `mensagemErroSupabase`, `mesLabel`. `loadAll` e o menu são o desenho de cada app; o resto pede comparar e decidir.

**Falta** (próximas etapas): as "ainda diferentes" acima; o CSS dos avisos ainda está copiado nos 5
apps (`core.css`); `attachEvents` tem 909 a 2.206 linhas por app (separar por tela); apagar os `sw_*.js` aposentados. `Adubacao.html` não usa o núcleo (sem login,
`esc`/`fmt` próprios e diferentes).

### Verificação em duas etapas (TOTP, 07/11/2026) — telas no ar, EXIGÊNCIA NO BANCO ainda não

O Supabase já traz o TOTP ligado (conferido por ele no painel). Os 5 apps (`core.js`) ganharam:
- **Cadastro**: botão "Ativar ou gerenciar" na tela **Trocar senha**, só para quem tem acesso total (`acessoTotal()`: admin e proprietário). Janela própria por cima do app
  (`#mfa-dialogo`, `abrirSegundoFator`): botão "abrir no app autenticador" + chave para digitar (sem QR code), código de 6 números, cadastrar outro celular, remover, desistir no meio não deixa fator pela metade.
  **Sem QR code (decisão dele, 09/11/2026: "Só chave e botão").** Ele relatou "não apareceu QR Code" e, depois da primeira correção, "ainda não"; quando
  perguntei por que precisaria dele, ele disse que não precisa. O QR só serve para passar ao app autenticador a **chave secreta** (~32 letras) sem digitar. A janela
  agora mostra: o botão grande **"Estou neste celular: abrir no app autenticador"** (`a#mfa-abrir-app`, link `otpauth://` que o servidor manda ou que o app monta com a
  chave; no próprio celular é o caminho de um toque, e ali o QR nem serviria, porque o celular não lê a própria tela), a **chave em grupos de 4 letras**
  (`#mfa-chave`, `data-chave` guarda a chave sem espaços) e o botão **"Copiar a chave"** (`data-mfa-copiar`, `navigator.clipboard`; sem permissão avisa para tocar e
  segurar). Se o servidor não mandar a chave, avisa e desfaz o cadastro pela metade (`unenroll`).
  - **A causa provável do QR "sumido" era o foco automático**: `desenha()` dava `focus()` no campo do código ao desenhar o passo; no iPad e no celular o foco abre o
    teclado e **rola a janela até o campo, empurrando o conteúdo de cima para fora da vista**. Agora **nada toma foco sozinho** (a pessoa toca no campo na hora) e a
    janela volta ao topo. Regra geral: janela com campo de texto no meio de uma instrução NÃO dá `focus()` ao abrir; só tela de uma coisa só (o `#mfa-desafio` do login).
  - O código do gerador de QR (modo byte, correção M, versões 1 a 15, conferido contra a biblioteca segno nas 15 versões × 8 máscaras) foi escrito e depois **retirado**
    por esta decisão; está no histórico do git (commit 1f7bede, "QR do segundo fator gerado no proprio app...") se um dia ele quiser o QR de volta. O SVG que o servidor
    manda (GoTrue: `goqrsvg` + SVGo, bloco de 3 px, **sem `viewBox`**, um `<rect>` por quadradinho, ~280 KB) nunca foi desenhado com sucesso no iPad dele; a causa exata
    não foi provada.
  - **Prova**: `teste_segundo_fator.py` (187) abre a janela de verdade e confere o botão com o link certo, a chave em grupos, o botão de copiar, que não há `<img>`/`<svg>`, que
    o campo do código não toma o foco, que botão e chave ficam inteiros na vista (inclusive em tela de 560 px), o endereço montado quando o servidor não manda `uri` e o
    aviso quando não manda a chave. O stub (`window.__MFA_SEM_URI__`, `__MFA_NADA__`) força esses dois casos.
- **Login**: conta com celular cadastrado → depois da senha aparece a tela cheia `#mfa-desafio` e **o app não carrega nada** (nem o perfil) até o código passar; cancelar volta ao
  login. Vale no login com senha (`fazerLogin`), ao abrir o app com sessão guardada só de senha (`initAuth`) e na renovação do token de uma sessão que ganhou celular
  depois. Com mais de um celular cadastrado o código é de UM deles, então se tenta cada fator. Sem internet o código não se confere (a tela avisa); sessão já confirmada
  neste aparelho (aal2) abre sem pedir de novo, até sem sinal.
- **Como se decide** (`precisaDoSegundoFator`, local, sem rede): o JWT do login diz `aal1` (só senha) ou `aal2` (senha + código) e `session.user.factors` traz os celulares
  confirmados; pede o código se `aal1` **e** há fator confirmado. Eventos de sessão no meio da conferência são ignorados (`state.mfaEmAndamento`).
- **Quem não ativou entra como sempre.** Funcionário de campo não muda nada.
- O stub dos testes tem uma API de fator falsa (`window.__MFA__`, `window.__MFA_CODIGO__` = 123456, `window.__jwt('aal1'|'aal2')`).

**O que AINDA falta (nada disto protege o banco hoje):** a tela sozinha é aviso, não proteção — com a senha roubada alguém ainda lê o banco por fora do app. A proteção
é um SQL de RLS (`seguranca_04`, a escrever e ensaiar): política **restritiva** em toda tabela com RLS e a mesma regra nas funções/visões de permissão (a visão
`lancamentos_rateados` roda com direitos do dono e filtra por `tem_permissao`, então a RLS das tabelas não a cobre) que, para quem TEM fator confirmado, exija `aal2`; quem
não tem fator segue com `aal1`. **Ordem obrigatória:** (1) telas no ar ✓; (2) ele ativa o dele (de preferência 2 celulares) e testa entrar, fechar e abrir, abrir sem sinal;
(3) só então o SQL. Ligar o SQL antes de ele conseguir ativar pode trancá-lo para fora.
**Se alguém perder o celular**: o Supabase não dá códigos de recuperação; o dono do projeto remove o fator no SQL Editor (`delete from auth.mfa_factors where user_id =
'<uuid da pessoa>';`, a conferir quando for preciso) e a pessoa cadastra de novo.

### Centro de custo do lado certo: os 22 da A4 resolvidos e a trava (09/11/2026)

Pedido do Eduardo ("aqueles 22 lançamentos vamos resolver também!!"; ele tinha deixado como estavam em 07/11). Eram 22 receitas de 2023 (R$ 339.094,22, todas do ERP, atividade
`geral`, com as partes do rateio) presas em **três centros de SAÍDA**: 18 em "AJUSTE DE SALDO BANCÁRIO" (R$ 299.890,29), 3 em "OUTRAS MOVIMENTAÇÕES DE CAIXA" (R$ 37.203,93) e 1 em
"MANUTENÇÃO E PRESTADORES DE SERVIÇO NA CASA-SEDE" (R$ 2.000,00). Não existia centro de entrada com esses nomes: **o índice único em `lower(nome)` impede dois centros com o mesmo nome**,
e o ERP tem a conta dos dois lados. A tela de lançamento e a de contas **já** só oferecem centro de ENTRADA para receita e de SAÍDA para despesa/investimento (`ladoDoCentro`,
`tipoEsperado`); a falha vinha da importação do ERP e de SQL direto.
- **`a4_01_onde_estao_os_22.sql`** (só leitura): lista os lançamentos do lado errado, o centro do lado certo com o mesmo nome (`PAR`) e os centros de entrada ativos. Ele rodou.
- **`a4_02_corrige_os_22.sql`**, **RODADO por ele em 09/11/2026, tudo OK** (os 6 itens da conferência: 22 em centro de entrada, R$ 339.094,22 iguais, 0 receitas em centro de saída em todo o banco,
  0 despesas/investimentos em centro de entrada, 3 centros novos, 0 `geral` sem partes). Tudo ou nada; recusa se não forem exatamente esses 22 nesses centros e valores; cria 3 centros de
  ENTRADA irmãos com o **mesmo nome + " (ENTRADA)"**, copiando `subcategoria` e `classe` do centro de saída (por isso o **grupo, e o bloco do fluxo de caixa da aba Empresa, não mudam**); só o
  `centro_custo_id` muda (valor, data, atividade, tipo e rateio ficam). Cópias fechadas `zz_backup_a4_lanc_2026_11_09` e `zz_backup_a4_centros_2026_11_09` (a apagar quando ele confirmar; foi feito, desfeito sem querer e refeito no mesmo dia, 6 itens OK de novo);
  desfazer no fim do arquivo. Ensaiado num Postgres descartável (caminho feliz, recusas, rodar de novo, desfazer devolve o banco idêntico, centro irmão já existente, nome já usado do outro lado).
  **O que aconteceu depois (09/11/2026, aprendizado):** na mensagem do script eu mandei um SEGUNDO bloco de código, o "para desfazer"; ele rodou os dois ("já rodei o segundo, deu sucesso") e o conserto foi
  desfeito (os 22 voltaram aos centros de saída, os 3 centros novos foram apagados; as cópias `zz_backup_a4_*` ficaram). A `banco_travas_02` recusou instalar por isso (achou 22 do lado errado) e a
  consulta de diagnóstico mostrou o estado. **Regra: o desfazer NUNCA vai como bloco de código separado na conversa com ele (ele roda todos os blocos); fica só no fim do arquivo SQL e se oferece em
  texto quando precisar.** O `a4_02` passou a poder ser **rodado de novo depois de desfeito**: se as cópias de uma rodada anterior existem e batem com o estado de hoje, troca por cópias novas; se não
  batem, recusa (ensaiado: fez, desfez, fez de novo).
  O R$ 2.000 da casa-sede ficou num centro de entrada do grupo ADM (escolha provisória minha para não mudar número nenhum); se ele preferir, passa para "ESTORNO E/OU DEVOLUÇÃO DE PAGAMENTO".
- **`banco_travas_02_centro_do_lado_certo.sql`** (**INSTALADA por ele em 09/11/2026, conferência dos 5 itens OK**, depois de o conserto ser refeito; a 1ª tentativa recusou porque o conserto tinha sido desfeito sem querer, ver acima): receita só em centro de ENTRADA, despesa e investimento só em centro de SAÍDA, conferido ao gravar um
  lançamento novo ou ao mudar o tipo ou o centro de um (editar só valor ou descrição de um antigo não dispara); centro sem tipo vale para qualquer lado; trocar o lado de um centro que já tem
  lançamentos do outro lado é recusado (gatilho em `centros_custo`). `security definer` (quem grava pode não ler `centros_custo`). **Recusa instalar** se hoje houver lançamento do lado
  errado ou conta a pagar/receber EM ABERTO com rateio do lado errado (a baixa criaria lançamento do lado errado e seria barrada). **Se o ERP for reimportado, receita em centro de saída será
  recusada**: a importação precisa usar o centro de entrada. Desfazer no fim do arquivo. Os fluxos do app que gravam lançamento com centro fixo seguem do lado certo: o juros das parcelas ("Juros e Encargos de Financiamento", `saida`) e a venda de animais ("Vendas", `entrada`); as telas de lançamento e de contas já filtram o lado.

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

- **supabase-js com versão FIXA (2.118.0), nunca `@2`.** Em 05/11/2026 o `@2` do
  CDN passou a servir a 2.119.0 um dia depois de lançada, sem ninguém testar: a
  biblioteca cuida do login e de toda leitura/gravação, então uma versão nova
  pode quebrar os 5 apps da noite para o dia sem nenhum deploy nosso. Fixou-se na
  2.118.0 (de 15/10/2026, a que serviu o uso diário de 3 semanas). O endereço
  está nos 5 apps e em `CDN_SUPABASE` do `sw.js` (`grep supabase-js@`): trocar
  nos seis de uma vez, e só depois de testar o login, uma carga e a fila offline
  com a versão nova. Os testes trocam a biblioteca por um stub, então não pegam
  quebra dela.
- **Campo de formulário com menos de 16px no celular.** O iPhone dá zoom ao tocar
  num campo com fonte menor que 16px e a tela fica ampliada (o Android não).
  Os 5 apps têm, logo depois de `.perm-matrix select`, um
  `@media (max-width:760px){ input, select, textarea, .perm-matrix select{font-size:16px} }`
  (o desktop segue com 13,5px; `.campo-grande` da Pecuária já tem 19px). Regra
  de campo nova com `font-size` menor que 16px tem de ficar dentro desse
  breakpoint ou vir depois dele com seletor mais específico. Conferência: criar
  um campo de cada tipo dentro de cada contêiner e medir o `font-size` computado
  a 390px (nenhum abaixo de 16).

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

73 arquivos `teste_*.py`, 2.799 checagens (09/11/2026; a tabela abaixo lista os
principais, `ls teste_*.py` é a lista completa). Rodam com Playwright + Python
contra um stub do Supabase (`teste_stub_supabase.js` — `insert`/`update`/`delete`
gravam de verdade em `window.__DB__`). Neste notebook, 5 checagens de tempo de
`teste_offline.py` ("offline com login vencido: abre em menos de 3 s") falham, e
falhavam igual no código publicado antes: é a máquina, não regressão.

| Arquivo | Testes | Cobre |
|---|---|---|
| `teste_apps_lavoura.py` | 44 | AECana.html, AECereais.html |
| `teste_matriz.py` | 32 | AEMatriz.html |
| `teste_matriz_racao_nao_duplica.py` | 8 | AEMatriz.html (resultado da Pecuária conta a compra da ração, não o consumo: despesa = só o lançado, consumo fica em `consumoGerencial`, Resultados sem "Ração (Confinamento)") |
| `teste_pecuaria_custo_sem_compra_racao.py` | 20 | AEpecuaria.html (custo por animal/lote = consumo da ração + fixo sem a compra de ração; resultado financeiro segue com a compra; só centro "Nutrição animal" ou conta com esse nome exato conta como compra; a tela avisa quanto ficou de fora; sem compra lançada nada muda) |
| `teste_paginacao.py` | 2 | AEMatriz.html, AEpecuaria.html |
| `teste_financiamentos.py` | 35 | AEMatriz.html |
| `teste_venda.py` | 28 | AEMatriz.html |
| `teste_unidade.py` | 31 | AEMatriz.html |
| `teste_exclusao.py` | 20 | AEMatriz.html, AEpecuaria.html, AECana.html, AECereais.html |
| `teste_lote_racao.py` | 18 | AEpecuaria.html (lote encerrado/zerado não recebe ração; sem dieta visível, o aviso fala da dieta) |
| `teste_cereais_cultura.py` | 27 | AECereais.html |
| `teste_contas.py` | 83 | AEMatriz.html |
| `teste_offline.py` | 24 | sw.js (offline dos 5 apps), abertura offline com login vencido, botão ← Painel, cards do Painel na mesma janela |
| `teste_resultado_por_unidade_drilldown.py` | 51 | AEMatriz.html (Resultados > Operacional: por unidade produzida, Pecuária como atividade toda) |
| `teste_empresa.py` | 63 | AEMatriz.html (Resultados > Empresa: fluxo de caixa em 3 blocos, juros por ano e safra, cobertura, dívida, linha do ERP assumida por contrato, sem rolar de lado de 1280 a 320 px) |
| `teste_divida_empresa.py` | 42 | AEMatriz.html (Empresa, Fase 2: vencimentos em 12 meses/por ano/por safra, taxa média ponderada, saldo e custo médio, lançar contrato não muda o saldo médio) |
| `teste_financiamentos_erp.py` | 42 | AEMatriz.html (Financiamentos > Lançar contrato do ERP: lista, cronograma real, vínculo das linhas, divida sem contar duas vezes, Editar na lista abre a edição reduzida, cancelar devolve) |
| `teste_financiamentos_editar.py` | 40 | AEMatriz.html (Financiamentos: registrar pagamento com data/juros reais, editar parcela e contrato, quitar, cancelar; tela do contrato sem rolar de lado) |
| `teste_sem_dados_sensiveis.py` | 14 | todo arquivo versionado (repositório público: sem CPF/CNPJ, número de conta, de contrato ou de documento; sem dumps de dados) |
| `teste_site_fora_do_ar.py` | 12 | sw.js (site respondendo 404/503: o app abre da cópia guardada; endereço nunca guardado continua dando 404; online a versão nova entra na hora) |
| `teste_sem_nome_do_erp.py` | 8 | todo arquivo versionado e o nome de cada um (o nome do ERP de origem não aparece em lugar nenhum) |
| `teste_gmd_boi_a_boi.py` | 7 | AEpecuaria.html (GMD boi a boi: lote apartado, histórico do animal entre currais, vaca com o mesmo número fora, sem peso por animal cai na média) |
| `teste_contas_lote.py` | 18 | AEMatriz.html (Contas: conta repetida bloqueada, inclusive já paga e em parcelado; seleção e baixa em lote com data do vencimento ou data única) |
| `teste_layout_matriz.py` | 9 | AEMatriz.html (12 telas em 9 larguras, de 1920 a 320 px: nenhuma página ou card rola de lado) |
| `teste_area_colhida_cana.py` | 10 | AECana.html, AEMatriz.html (área colhida na colheita de cana: TCH, histórico do talhão, trava de área, produtividade do Matriz) |
| `teste_carga_pecuaria.py` | 18 | AEpecuaria.html (consulta que falha ou ainda carregando: aviso na tela, lançamento explica em vez de culpar o lote, login vencido renova e recarrega, sem rede a fila offline continua; histórico pesado parado não trava o lançamento; lotes sem resposta em 25 s viram aviso) |
| `teste_campo_moeda.py` | 16 | AEMatriz.html (campos de R$ com ponto de milhar e vírgula ao digitar; o app continua lendo e gravando o número) |
| `teste_financiamentos_periodicidade.py` | 39 | AEMatriz.html (Financiamentos: parcelas anuais/semestrais e 1º vencimento, valor e juros de cada parcela digitados, Excluir contrato, contrato que já existia fora do empréstimo recebido) |
| `teste_parto_aborto_lote_numero.py` | 89 | AEpecuaria.html (toque em Salvar logo depois de mexer no número não se perde, com mouse e toque, no parto e no Manejo; lista de partos atualiza sem esperar o histórico; update sem linha avisa; lote em branco e obrigatório em 11 lançamentos; número só com algarismos e número antigo com texto ainda editável; campo Nome do animal; app antes do SQL não manda as colunas novas; aborto; óbito do bezerro; nasceu morto; data do parto em branco e aviso de parto repetido; resumo do lote sem o bezerro morto nos vivos) |
| `teste_matriz_reproducao_operacional.py` | 15 | AEMatriz.html (Resultados > Operacional > Reprodução (Cria): custo por bezerro desmamado = inseminação + ração/pasto dos lotes de Cria + fatia do fixo sem a compra de ração; taxa de prenhez; desmamados machos/fêmeas; sem rolar de lado) |
| `teste_qual_animal.py` | 25 | AEpecuaria.html ("Qual animal é?": 11 x 11099 · ES pergunta antes de gravar inseminação/diagnóstico/parto; 57 = 057 não pergunta e usa o cadastro; o campo tira zero à esquerda; sem parecido ou editando sem mexer no número não pergunta; Voltar não grava; regra das 3 IATF: crias, IA desde o último parto, 1ª/2ª/3ª automática, aviso na 4ª que não bloqueia) |
| `teste_lavoura_texto_escapado.py` | 8 | AECana.html, AECereais.html (nome com aspas, `<` e `&`: aparece inteiro na lista, não vira HTML e volta inteiro no campo de edição) |
| `teste_fila_sem_duplicar.py` | 18 | AEpecuaria.html (resposta perdida depois de gravar: saída de ração, baixa de estoque, parto, inseminação, diagnóstico, cocho, venda e pesagem voltam da fila sem duplicar e completam só o que faltou; sem a coluna `client_uuid` grava como antes) |
| `teste_matriz_estoque_pecuaria.py` | 17 | AEMatriz.html (Rebanho estocado, só os totais: última pesagem de cada lote ativo, UA = PV/450, @ = PV×50%/15, valor pelo preço da @ por sexo, por hectare; lote sem pesagem fica de fora com aviso; sem rolar de lado) |
| `teste_lancamento_atividade.py` | 32 | AEMatriz.html (lançamento novo nasce sem atividade e não oferece "Geral"; salvar sem escolher é barrado; "Dividir entre as atividades" em partes iguais, um lançamento por atividade numa chamada só, centavos fechando (900 → 300×3, 100 → 33,33+33,33+33,34), percentual escolhido, soma errada e uma atividade só barradas; "Geral" antigo abre travado; conta a pagar pede a atividade do rateio) |
| `teste_avisos_pecuaria.py` | 25 | AEpecuaria.html (alert() vira aviso na tela: não trava, erro fica até fechar, texto seguro, Esc/×, no topo e acima de janelas, confirm() nativo) |
| `teste_avisos_apps.py` | 88 | AEMatriz.html, AECana.html, AECereais.html, AECombustivel.html (o mesmo aviso na tela, 22 checagens por app: não trava, console e `__AVISOS__`, no topo, comum some e erro fica, texto seguro, ×/Esc, no máximo 4, sobrevive ao redesenho, confirm() nativo, 44 px no toque, cabe em 360 px) |
| `teste_nucleo.py` | 34 | os cinco apps + `core*.js` (tags e `?v=` em dia e na ordem certa, app não repete o que o núcleo declara, **nenhuma função nova copiada entre apps** — lista `DIVIDA_CONHECIDA` só pode encolher —, `sw.js` guarda os núcleos, cada app enxerga as funções do núcleo) |
| `teste_nucleo_offline.py` | 6 | `sw.js` + `core.js?v=` com service worker de verdade: versão nova publicada, offline abre com o núcleo NOVO (provado que o `sw.js` antigo devolvia o velho) e o cache não guarda a cópia antiga |
| `teste_combustivel_proprietario.py` | 13 | AECombustivel.html (proprietário tem acesso total sem matriz e a tela de Usuários segue só do admin; gestor sem matriz não vê nada; "Proprietário" na lista de usuários; editar e salvar proprietário/colaborador/gestor não muda o perfil da pessoa) |
| `teste_perfis_acesso.py` | 66 | os 5 apps (tela de acesso: abrir e salvar quem é de qualquer dos 7 perfis não troca o perfil; lista com cor e texto certos; formulário de novo usuário escapa o que se digita) |
| `teste_sessao_abertura.py` | 65 | os 5 apps (tela de login com o nome do app e texto escapado; aparelho sem sinal na 1ª abertura diz "sem conexão" e o "Tentar novamente" abre o app; `TOKEN_REFRESHED` não redesenha nem recarrega; sair; `pareceErroDeRede` nos 3 navegadores) |
| `teste_segundo_fator.py` | 187 | os 5 apps (verificação em duas etapas: pede o código só de quem tem celular cadastrado, o app não carrega antes do código, cancelar, login com senha, sessão aal2 abre sem pedir de novo, renovação do token de sessão que ganhou celular, ativar/cadastrar outro/desistir/remover, botão só para acesso total, sem QR: botão de abrir no app autenticador, chave em grupos e copiar, campo do código sem foco automático, tudo inteiro na vista em tela baixa, endereço montado sem `uri`, aviso sem a chave) |
| `teste_menu_lateral_apps.py` | 79 | Pecuária, Cana, Cereais e Combustível (menu lateral de 1160 px, 196 px no iPad deitado, rodapé do usuário inteiro na tela, "← Painel" para o Matriz, marca clara, barra de cima em 1100 px, celular como era) |
| `teste_menu_lateral.py` | 85 | AEMatriz.html (menu lateral de 1160 px: coluna à esquerda, menu grande, sem lista de apps na barra, Painel com os 4 apps em janelinhas 2x2 no iPad 1180/1194, 1280 e desktop, links certos, permissão por app, barra de cima em 1100 e 820, celular) |
| `teste_combustivel_menu_cabe.py` | 35 | AECombustivel.html (coluna do menu cabe na altura da tela com cada item aberto, em 1180x820, 1194x834, 1280x800, 1366x768 e 1440x900, toque e mouse; ← Painel, Trocar senha e Sair numa linha; item de 44 px no toque) |
| `teste_celular_topo_apps.py` | 156 | Pecuaria, Cana, Cereais e Combustivel no celular (320/360/390 px): ← Painel, Trocar senha e Sair inteiros, faixa de cima sem rolar de lado, botao ☰ com a tela atual, menu fechado que abre numa coluna, setinha sem fechar, tocar num item troca de tela e fecha) |
| `teste_painel_celular.py` | 52 | AEMatriz.html (Painel no celular, ate 760 px: os 4 apps viram icones grandes (76 px), um embaixo do outro, com nome curto e link, sem janelinhas, numeros nem aviso da copia de seguranca; app em breve apagado; so os apps permitidos; de 761 px para cima nada muda) |
| `teste_painel_combustivel.py` | 18 | AEMatriz.html (indicadores do AE Combustivel no Painel: estoque dos tanques ativos, consumo e custo do mes com custo medio das notas ate o dia, alertas abertos; traco sem a permissao do modulo; custo fora de Resultados; sem rolar de lado em 1180 e 390 px) |
| `teste_botoes_rodape_menu.py` | 160 | os 5 apps (rodape do menu lateral: ← Painel, Trocar senha e Sair cabem na coluna e o texto cabe no botao com 16 px de folga, em 1180/1194/1280/1440, toque e mouse; nos apps de grade um botao por linha, porque lado a lado "Trocar senha" saia da borda no Safari do iPad, 08/11/2026) |
| `teste_menu_setinha.py` | 173 | os 5 apps (setinha com as sub-abas de cada item do menu: abre uma lista por vez, não troca de tela, vai direto na sub-aba, Matriz escolhe tela e aba, guarda o que ficou aberto, escondida na barra de cima e no celular dos outros apps, painel do celular do Matriz) |
| `teste_csp.py` | 43 | os 5 apps (política de segurança de conteúdo: hosts liberados, sem unsafe-eval, barra fetch/imagem/script/eval de fora com página de controle, nenhuma violação ao percorrer as telas) |
| `teste_campo_toque.py` | 49 | os 5 apps (alvos de toque de 44 px em tablet/celular, mouse do desktop intacto, rótulos ligados, contraste do texto, manifestos aceitam qualquer orientação, Pecuária sem rolagem lateral) |
| `teste_venda_atomica.py` | 19 | AEMatriz.html (venda de animais por uma função do banco: uma chamada, sem gravações soltas, saldo novo na tela, recusa do banco mostrada, caminho antigo se a função não existe) |
| `teste_titulo_atomico.py` | 23 | AEMatriz.html (conta a pagar/receber por uma função do banco: parcelas e partes juntas, editar com id, recusa mostrada, caminho antigo) |
| `teste_pecuaria_compra_animais.py` | 28 | AEMatriz.html (bloco "Investimentos da Pecuária" e resultado de caixa por classe de centro, aviso no Geral, só Pecuária, filtros mês/ano/safra, resultado de antes intacto) |
| `teste_carga_leve.py` | 41 | AEMatriz.html (carga por grupo, visão rateada lida uma vez, `atualizarLancamentos` igual ao recarregamento completo, `vigentesNoMes` igual à versão antiga, voltar à aba depois de 10 min) |
| `teste_financeiro_paginado.py` | 24 | AEMatriz.html (Financeiro: 100 linhas por vez e "Mostrar mais" de 200 em 200, total do filtro inteiro, busca que espera parar de digitar e devolve o foco, trocar aba/atividade/mês volta a 100, lista curta sem rodapé, Editar na linha certa) |
| `teste_saldo_banco.py` | 51 | AEMatriz.html (Financiamentos: saldo devedor segundo o banco, com data, ao lado do contrato; saldo velho; não muda dívida, vencimentos, histórico nem fluxo; editar/criar com e sem o campo; Editar na lista para todo contrato ativo; lista e contrato sem rolar de lado de 1920 a 320 px) |
| `teste_offline_lancar.py` | 47 | AEpecuaria.html (lançar sem internet: cópia dos cadastros no aparelho por usuário, abrir sem sinal e com rede que não responde, fila, sobe uma vez só, janela aberta não é redesenhada, Sair apaga a cópia, aparelho sem espaço) |
| `teste_copia_seguranca.py` | 32 | AEMatriz.html (cópia de segurança em Usuários: JSON paginado com todas as linhas, tabela sem permissão fica de fora, CSV para o contador com BOM, vírgula decimal e fórmula neutralizada, só admin, sem violar a CSP) |
| `teste_curva_abc.py` | 18 | AEMatriz.html (Curva ABC das despesas em Relatórios: classes A/B/C por centro e por fornecedor, só despesa, filtros de período e atividade, sem rolar de lado) |
| `teste_manejo_planilha.py` | 64 | AEpecuaria.html (importar a planilha de manejo preenchida no curral: previa, validação com as regras do Manejo, nada gravado com erro, desmama, mudança de lote, mesma planilha duas vezes, rede que cai e Continuar, sem rolar de lado) |
| `teste_custo_hora_equipamento.py` | 21 | AECombustivel.html (Rateio > Por Equipamento: horas/km, combustível, manutenção com custo, custo total e R$ por hora/km; período; custo da manutenção opcional que só vai ao banco com valor; sem rolar de lado) |
| `teste_lancamento_equipamento.py` | 16 | AEMatriz.html (despesa com o campo Equipamento: lista, só despesa, coluna só enviada com valor (ou null ao tirar), editar sem perder, dividir leva para cada parte, sem equipamentos não aparece) |
| `teste_custo_animais_lote.py` | 27 | AEMatriz.html (compra de animais com lote e nº de cabeças: campos que aparecem e somem com o centro, lote e cabeças juntos, inteiro, unidade cab; bloco Custo dos animais por lote: R$ por cabeça, custo dos vendidos, margem sobre o animal, estoque a custo, animais próprios, matriz à parte, compras sem lote com Editar, sem seguir o período) |

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

### Testes automáticos no GitHub (CI, 07/11/2026)

`.github/workflows/testes.yml` + `roda_testes.py`. A cada `push` (qualquer branch) e sob demanda (aba Actions > Testes > Run workflow), o GitHub
roda **todos os `teste_*.py` em 4 partes ao mesmo tempo** (`ubuntu-latest`, Python 3.12, Chromium do Playwright, `TZ=America/Sao_Paulo`).
Medido na primeira rodada boa: **61 de 61 testes passaram, cada parte em 1 a 2 minutos** (no notebook do Eduardo a bateria leva muito mais).
- **Não impede o site de atualizar**: o GitHub Pages publica a `main` por conta própria. Quebrou = ✗ vermelho na aba Actions e e-mail do
  GitHub. Para impedir a publicação seria preciso trocar o Pages para publicação por workflow (não feito: atrasaria todo envio).
- **Como ver o motivo**: abrir a rodada; cada teste que falha vira uma anotação de erro com as últimas 40 linhas da saída dele, e cada parte
  posta uma anotação-resumo (quantos testes, tempo de cada um). A mesma informação está na API pública
  (`/repos/EduardoSaquy/AEagropecuaria/actions/runs`, `/actions/runs/{id}/jobs`, `/check-runs/{job}/annotations`), que dá para ler sem login.
- **Ambiente que o CI monta** (passo "Monta o ambiente que os testes esperam"): os testes foram escritos num sandbox com caminhos fixos,
  então `/home/claude/AEagropecuaria` aponta para o repositório, `/tmp/lav_test/stub.js` é o stub do Supabase e `/opt/pw-browsers/chromium` é
  o Chromium do Playwright. Teste novo que dependa de outro caminho ou programa: acrescentar ali. Dependência de Python nova: `requirements.txt`
  (o primeiro erro real do CI foi `openpyxl` faltando, usado por `teste_manejo_planilha.py`).
- **No Linux do GitHub passam os dois que no notebook dele falham** (`teste_offline`, uma checagem de tempo, e `teste_layout_matriz`, caminho
  Linux): ali a bateria inteira é verde, então **vermelho no CI = regressão de verdade**.
- **Provado que pega erro**: uma branch descartável com o aviso do Matriz quebrado de propósito ficou vermelha, com 38 testes do Matriz
  reprovados e cada um anotado, enquanto os da Pecuária, Cana e Combustível seguiram verdes (as duas branches de ensaio foram apagadas).
- Teste novo (`teste_*.py`) é pego sozinho (o executor lista a pasta). `python roda_testes.py [--parte i --de n] [arquivo ...]` só funciona onde
  existem os caminhos acima (Linux/CI); no Windows dele continua o `prepara.py` do scratchpad. Não rodam no CI: `ensaio_sql_banco.py` e
  `conferir_chave_publica.py` (não são `teste_*`; precisam de Postgres e de internet).
- Ações usadas: `actions/checkout@v7` e `actions/setup-python@v7` (do próprio GitHub; o GitHub avisa quando uma versão fica velha).

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
