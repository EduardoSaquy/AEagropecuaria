# Unificação dos projetos Supabase — plano de execução

> Juntar o projeto da **Pecuária** (`leojfqlbdtlriemdgnyw`) dentro do projeto do
> **Lavoura/Matriz** (`kmkystqgpvmzrccxvyaz`), deixando um único banco, um único
> login e uma única tabela de permissões.

> **Status (25/08/2026): unificação concluída** — `AEpecuaria.html` e
> `AEMatriz.html` já apontam só para o projeto único, e `UNIFICACAO_VIRADA.md`
> tem o roteiro que foi de fato seguido. Este documento é o plano original;
> nomes de arquivo abaixo não batem mais com os scripts reais do repo:
> `unificacao_01_gerar_ddl.sql` (Passo 1) foi substituído pela cópia
> automática via `dblink` em `unificacao_02_estrutura_automatica.sql`, e
> `unificacao_02_copiar_dados.sql` (Passo 3) é hoje
> `unificacao_03_copiar_dados.sql` (os scripts foram renumerados). O único
> passo ainda pendente é o do repositório: pausar o projeto antigo da
> Pecuária no painel do Supabase — ver CLAUDE.md.

---

## 1. Levantamento (feito, com dados reais dos dois bancos)

Não é opinião — foi medido nos schemas e no banco ao vivo.

| O que | Resultado | Impacto |
|---|---|---|
| Tabelas da Pecuária | 26 | — |
| Tabelas do Lavoura/Matriz | 21 | — |
| **Colisão de nome de tabela** | **só `profiles`** | Ótimo. As outras 25 entram sem renomear. |
| FK de dados da Pecuária → `profiles` | **nenhuma** | Ótimo. Dado move sem remapear ID nenhum. |
| Autoria dos lançamentos (`criado_por`) | **texto** (nome de usuário) | Ótimo. Preservando o login, o histórico de "quem lançou" continua válido sozinho. |
| `is_admin()` e `tem_permissao()` | **idênticas** nos dois projetos | Ótimo. Uma definição serve os dois. |
| Pessoas nos dois projetos | 4 (alice, eduardo, marcia, paulo) — **mesmo papel nos dois** | Ótimo. Zero conflito, mantêm a senha atual. |
| Pessoas só na Pecuária | 6 (creunice, davi, gustavo, irlei, joilson, teste) | 5 pessoas reais + 1 conta de teste precisam de conta nova e senha nova. |
| **Colisão de chave de permissão** | **`financeiro` e `resultados`** | Único conflito de verdade. Resolvido renomeando o lado da Pecuária. |

### O único conflito real

`permissoes` é um JSON só. Hoje as chaves são:

- Lavoura: `cadastros`, `operacoes`, `financeiro`, `resultados`, `operacoes_graos`, `financeiro_graos`, `resultados_graos`
- Pecuária: `manejo`, `cadastro`, `insumos`, `dietas`, `lotesGeral`, `confinamento`, `pasto`, `cria`, `vendas`, `financeiro`, `resultados`

`financeiro` e `resultados` existem nos dois com **significados diferentes**. Se
juntar sem tratar, um sobrescreve o outro e alguém ganha ou perde acesso errado.

**Solução:** renomear só esses dois no lado da Pecuária → `pec_financeiro` e
`pec_resultados`. As outras 9 chaves da Pecuária não colidem com nada e ficam
como estão. Isso limita a alteração a **8 tabelas** (`config_financeiro`,
`custos_fixos`, `investimentos`, `precos_arroba`, `receitas`, `abates`,
`config_fazenda`, `fazendas`) em vez de mexer nas 143 políticas.

---

## 2. Premissas assumidas

Se alguma estiver errada, avise **antes** de rodar — muda o script.

1. **Sobrevive o projeto do Lavoura/Matriz.** É onde já estão Matriz, fazendas,
   funcionários e onde o Combustível já estava planejado para entrar.
2. **A conta `teste` não migra.** É conta de teste; recriar não custa nada.
3. **Os 4 que já existem nos dois mantêm a senha atual do Lavoura.** Só as 5
   pessoas novas (creunice, davi, gustavo, irlei, joilson) recebem senha nova.
4. **O projeto antigo da Pecuária não é apagado no dia.** Fica intacto e
   desligado dos apps por pelo menos 2 semanas, como rede de segurança.

---

## 3. Ordem de execução

Cada passo tem uma verificação. **Não avance sem a verificação passar.**

### Passo 0 — Backup (obrigatório, não pule)

No plano gratuito não existe restauração automática confiável. Antes de
qualquer coisa, exporte os dois bancos.

- Em cada projeto: *Database → Backups* (se disponível) **e** exporte CSV de
  cada tabela por *Table Editor → Export*.
- Guarde fora do Supabase (Drive/computador).

✅ **Verificação:** você consegue abrir os CSVs e eles têm linhas.

### Passo 1 — Gerar o DDL da Pecuária a partir do banco vivo

Rode `unificacao_01_gerar_ddl.sql` **no projeto da Pecuária**. Ele lê o catálogo
do Postgres e devolve o texto pronto de: tabelas, chaves, índices e políticas.

> Por que não usar o `supabase_schema.sql` que já temos: ele está **desatualizado**.
> Conferi — o `check` de `papel` lá diz `('admin','funcionario')`, mas o banco
> vivo usa `('admin','proprietario','colaborador','consultor')`. Gerar do banco
> elimina esse risco.

✅ **Verificação:** o resultado lista as 26 tabelas.

### Passo 2 — Criar a estrutura no projeto do Lavoura

Cole o resultado do Passo 1 no SQL Editor do **Lavoura**, com dois ajustes que o
script já sinaliza:

- **Não** crie `profiles` (já existe lá).
- **Não** crie `fazendas` (já existe lá, e a da Pecuária está morta desde a
  centralização do cadastro).

✅ **Verificação:** `select count(*) from information_schema.tables where
table_schema='public'` sobe de 21 para ~45.

### Passo 3 — Copiar os dados

Rode `unificacao_02_copiar_dados.sql` **no Lavoura**. Ele usa `postgres_fdw`
para ler direto do banco da Pecuária e copiar tudo na ordem certa (pai antes de
filho), depois acerta as sequências de `id`.

> ⚠️ Você vai precisar da **senha do banco** da Pecuária (*Project Settings →
> Database*). Ela vai num placeholder dentro do script — **preencha você mesmo,
> não me mande essa senha**.

✅ **Verificação:** o script termina imprimindo a contagem de linhas por tabela
nos dois lados. **Os números têm que bater exatamente.**

### Passo 4 — Juntar usuários e permissões

1. Crie as 5 contas novas pela tela de Usuários do AE Matriz (que já usa a Edge
   Function `criar-usuario-cana`): creunice, davi, gustavo, irlei, joilson —
   **usando exatamente os mesmos nomes de usuário de hoje** (isso é o que
   preserva o histórico de `criado_por`).
2. Rode `unificacao_03_permissoes.sql` no Lavoura. Ele copia as permissões da
   Pecuária para cada pessoa, já renomeando `financeiro`→`pec_financeiro` e
   `resultados`→`pec_resultados`, e **sem apagar** as permissões de Lavoura de
   quem já tinha.

✅ **Verificação:** o script imprime, por pessoa, as permissões antes e depois.
Confira alice e paulo (que têm os dois lados).

### Passo 5 — Apontar os apps para o banco único

Eu troco no código: `AEpecuaria.html` passa a usar a URL/chave do Lavoura e as
chaves `pec_*`; `AEMatriz.html` perde o cliente `dbPecuaria` e passa a ler tudo
localmente. **Esse passo é meu — faço assim que você confirmar o plano.**

✅ **Verificação:** abrir os 3 apps, logar, e conferir os números do Painel do
Matriz contra os de hoje (anotados antes).

### Passo 6 — Limpeza

Rode `unificacao_04_limpeza.sql`: remove o FDW e **apaga todas as políticas de
leitura anônima** que só existiam por causa da separação.

✅ **Verificação:** um `select` na tabela `lotes` com a chave pública, sem login,
deve retornar **0 linhas** (hoje retorna tudo).

---

## 4. Rollback

Até o Passo 5, o rollback é trivial: os apps ainda apontam para os bancos
antigos, e o banco da Pecuária está **intocado** (só foi lido).

- Falhou no Passo 3 ou 4 → apague as tabelas novas no Lavoura e recomece. Nada
  de produção foi afetado.
- Falhou depois do Passo 5 → suba de volta a versão anterior dos HTMLs (eu
  guardo). O banco antigo continua lá, completo.

O ponto sem volta é começar a **lançar dados novos** no banco unificado. A partir
daí, voltar significa perder o que foi lançado. Por isso o Passo 5 é o último.

---

## 5. Riscos honestos

| Risco | Gravidade | Mitigação |
|---|---|---|
| `postgres_fdw` bloqueado ou conexão entre projetos recusada | Média — é a peça que **não consigo testar daqui** | Plano B pronto: exportar/importar CSV tabela a tabela pelo Table Editor. Mais chato, funciona igual. |
| 5 pessoas ficam sem conseguir entrar até receberem a senha nova | Alta se pegar todo mundo de surpresa | Avise antes. Faça num horário de baixo movimento. |
| Alguém com papel `proprietario` na Pecuária ganha acesso total ao Lavoura | Média | Já conferi: os 4 que têm os dois lados **já têm o mesmo papel** nos dois. Ninguém sobe de nível. |
| Algum `check`/índice se perder na recriação | Baixa | O DDL sai do catálogo vivo, não de arquivo velho. |
| Eu não consigo testar nada disso contra o banco de vocês | **Alta — limitação real** | Toda verificação é você rodando os `select` de conferência. Não pule nenhum. |

---

## 6. Cronograma realista

Não é "roda tudo em 10 minutos".

| Passo | Tempo estimado |
|---|---|
| 0. Backup | 20–30 min |
| 1–2. Estrutura | 15 min |
| 3. Dados | 15–30 min |
| 4. Usuários e permissões | 20 min |
| 5. Apps | 10 min (o código já estará pronto) |
| 6. Limpeza e conferência | 20 min |
| **Total** | **~2h**, com folga pra imprevisto |

Faça num período em que ninguém precise lançar nada. Não emende com a
importação do Conag no mesmo dia — uma coisa de cada vez.
