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

O projeto antigo da Pecuária (`leojfqlbdtlriemdgnyw`) está parado mas AINDA tem
leitura anônima em 10 tabelas, e a Edge Function `atualizar-permissoes` (que
faz UPDATE em `profiles` com a chave de serviço sem checar quem chamou)
continua publicada lá — órfã (nenhum app mais chama), mas exposta a quem tiver
a anon key antiga, recuperável no histórico do git. Pendência de segurança em
aberto: pausar o projeto no painel do Supabase.

### Registro de alterações

`log_alteracoes`, ligado por gatilho em `lancamentos_financeiros`, `abates`,
`profiles` e `centros_custo` (`auditoria_05_registro_de_alteracoes.sql`).
Só admin lê, ninguém grava pela API (só o gatilho, `security definer`).
Confirme que rodou antes de assumir que existe — não estava no
`schema_real.txt` de 22/08.

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
- Senha do banco e credenciais são preenchidas pelo Eduardo, nunca pedidas nem
  digitadas pelo assistente.
- Contas de usuário são criadas por ele na tela de Usuários do AE Matriz.

## Como o Eduardo trabalha

Respostas diretas, técnicas, com número e tabela quando couber. Discordar
abertamente quando a premissa dele estiver errada. Não enfeitar. Português do
Brasil.
