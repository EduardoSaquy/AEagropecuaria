# AE Agropecuária — contexto do projeto

Família de apps HTML de arquivo único (JS puro + Supabase) que administram uma
operação agropecuária: gado (Pecuária), cana (Cana), grãos (Cereais) e um app
consolidador (Matriz). Sem build, sem framework, sem npm. Cada `.html` é o app
inteiro e é aberto direto no navegador ou instalado como PWA.

| Arquivo | O que é |
|---|---|
| `AEMatriz.html` | consolidação: financeiro, centros de custo, usuários, resultados |
| `AEpecuaria.html` | gado: lotes, pesagens, ração, reprodução, abate |
| `AECana.html` | cana: talhões, safras, aplicações, colheitas |
| `AECereais.html` | grãos: mesma estrutura da cana, outra frente |
| `AELavoura.html` | página de redirecionamento para os dois acima (o app antigo foi dividido) |
| `sw.js` | service worker único de todos os apps (cache `ae-v3`) |
| `gerar_apps_lavoura.py` | gera AECana e AECereais a partir de `AELavoura_app_completo.html.bak` |

Cana e Cereais são propositalmente separados: ficam em estados diferentes do
país e a operação é independente. Não voltar a unificá-los.

## Banco

Projeto Supabase único: `kmkystqgpvmzrccxvyaz`.
O projeto antigo da Pecuária (`leojfqlbdtlriemdgnyw`) está parado mas AINDA tem
leitura anônima em 10 tabelas — pendência de segurança em aberto.

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

### A regra do recorrente tem uma implementação só

`vigentesNoMes(despesas, mesStr)`. Um recorrente vale no mês **a menos que**
exista lançamento próprio com a mesma chave:
`` `${descricao}||${centroCustoId}||${atividade}||${fazendaId ?? ''}||${areas}` ``
Se precisar da mesma lógica em outro lugar, chame a função. Não reescreva.

### Plano de contas

`centros_custo.tipo` ('entrada'/'saida') e `.subcategoria` ('GRUPO | Subcategoria'),
seguindo o DFC do Conag. 63 centros, 7 grupos, sem duplicados — há índice único
em `lower(nome)` impedindo recriação. Centro de custo é **sempre global**: nunca
amarrar centro a fazenda específica.

### O custo do insumo NÃO entra no resultado

A compra do adubo já é despesa lançada. A aplicação no talhão serve para
**repartir** esse custo entre talhões, nunca para somar ao total. A tela de
Resultados já somou as duas coisas — foi corrigido. Não reintroduzir.

## Armadilhas que já custaram caro

- **Leia o catálogo vivo, não os arquivos de schema.** `cana_schema.sql` e
  `supabase_schema.sql` estão desatualizados e já enganaram quatro vezes.
  `schema_real.txt` é a referência.
- **O Supabase trunca em 1000 linhas sem avisar.** Há 2.759 lançamentos. Toda
  consulta que pode passar de mil linhas usa `fetchAllRows(...)`.
- **Nada de acentos em comentário de SQL.** O separador de statements do editor
  do Supabase não ignora comentários e quebra o arquivo.
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

`teste_apps_lavoura.py` (44), `teste_matriz.py` (34), `teste_paginacao.py` (2).
Rodam com Playwright + Python contra um stub do Supabase. 80 testes.
Rodar todos antes de entregar qualquer alteração.

## Restrições de segurança permanentes

- **Nunca** guardar CPF, salário ou Pix em tabela com leitura pela chave anônima.
- Senha do banco e credenciais são preenchidas pelo Eduardo, nunca pedidas nem
  digitadas pelo assistente.
- Contas de usuário são criadas por ele na tela de Usuários do AE Matriz.

## Como o Eduardo trabalha

Respostas diretas, técnicas, com número e tabela quando couber. Discordar
abertamente quando a premissa dele estiver errada. Não enfeitar. Português do
Brasil.
