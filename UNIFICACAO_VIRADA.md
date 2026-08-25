# Roteiro da virada

Tudo que falta, na ordem. Feito para ser executado de uma vez só, num
momento combinado com a equipe.

## Onde estamos

| Passo | Status |
|---|---|
| 0. Backup de `profiles` | ✅ feito |
| 2. Estrutura da Pecuária no Lavoura | ✅ 24 tabelas, RLS e 104 políticas |
| 3. Cópia dos dados | ✅ 4.060 linhas, 24/24 conferem |
| 4. Permissões | ⏳ 4 pessoas vinculadas, faltam 5 contas |
| 5. Re-sync + virada dos apps | ⏳ scripts e HTMLs prontos |
| 6. Limpeza | ⏳ |

Enquanto a virada não acontece, **o AE Pecuária segue no ar normalmente,
gravando no banco antigo**. Nada quebrou e ninguém precisa parar.

---

## Antes do dia (pode fazer com calma)

**1. Criar as 5 contas** no AE Matriz → Usuários → + Novo usuário:

| Nome | Usuário |
|---|---|
| Creunice | `creunice` |
| Davi | `davi` |
| Gustavo | `gustavo` |
| Irlei | `irlei` |
| Joilson | `joilson` |

O nome de usuário precisa ser idêntico ao da Pecuária — é o que preserva o
histórico de quem lançou o quê. Não crie a `teste`.

**2. Rodar o `unificacao_04_permissoes.sql` de novo.** A coluna `situacao`
deve vir toda `vinculado`, menos a `teste`.

Criar as contas antes **não atrapalha nada**: elas passam a existir no banco
unificado, que nenhum app está usando ainda.

---

## No dia da virada (~20 minutos)

**3. Avisar a equipe** que a Pecuária vai ficar alguns minutos fora e que
depois todo mundo entra com o login novo.

**4. Rodar o `unificacao_05_resync_antes_da_virada.sql`** (no Lavoura, com a
senha). Ele traz os lançamentos feitos na Pecuária desde a cópia.

Leia a coluna `situacao` do resultado. Qualquer linha com `ATENCAO` merece
uma pausa — principalmente "origem tem MENOS linhas", que significa que
alguém apagou algo no banco antigo. Nesse caso me chame antes de seguir.

**5. Subir os dois HTMLs** no GitHub: `AEpecuaria.html` e `AEMatriz.html`.

**6. Conferir**, com um hard refresh (Ctrl+Shift+R):

- entrar no AE Pecuária com o login do Lavoura (`eduardo`) — tem que abrir
  normalmente e mostrar os mesmos números de antes;
- conferir Financeiro e Resultados da Pecuária, que são os módulos cujas
  permissões mudaram de nome;
- abrir o AE Matriz → Painel e comparar os números do card "AE Pecuária"
  com os de antes;
- abrir o AE Lavoura e confirmar que nada mudou por lá.

**7. Rodar o `unificacao_06_limpeza.sql`**, que derruba a ponte e apaga as
políticas de leitura anônima. Faça o teste de segurança descrito no fim dele.

**8. Avisar a equipe** que voltou, e passar as senhas novas para as 5
pessoas.

---

## Se der errado

Até o passo 5 não há risco: o banco antigo está intacto e os apps ainda
apontam para ele.

Depois de subir os HTMLs, o rollback é **subir de volta a versão anterior
dos dois arquivos** — eu guardo as duas versões no histórico. O banco antigo
continua completo e recebendo, então voltar custa uma re-publicação, não
perda de dado.

O ponto sem volta é começar a lançar coisas novas no banco unificado. A
partir daí, voltar significa perder o que foi lançado depois.

**Não apague o projeto antigo da Pecuária.** Deixe parado por pelo menos
duas semanas.

---

## O que muda para quem usa

- **Um login só.** Quem já usava os dois apps (alice, marcia, paulo,
  eduardo) mantém a senha do Lavoura. As outras 5 pessoas recebem senha
  nova.
- **As telas continuam iguais.** Nada de layout muda em nenhum dos apps.
- **Permissões preservadas.** Conferido: alice ficou com as 18 chaves (7 do
  Lavoura + 11 da Pecuária) convivendo, sem uma apagar a outra.

## O que muda por dentro

- Um banco só, em vez de dois.
- O cadastro de Funcionários passa a ter **um campo de login** e **uma
  matriz de permissões** com os módulos dos dois apps, em vez de dois de
  cada.
- A Edge Function `atualizar-permissoes`, publicada ontem, **deixa de ser
  necessária**: gravar permissão da Pecuária vira um update comum. Ela não
  atrapalha, só para de ser chamada.
- As políticas de leitura anônima somem. Hoje qualquer pessoa com a chave
  pública (que fica à vista no HTML) lê essas tabelas inteiras sem login;
  depois da limpeza, não mais. É o maior ganho de segurança da unificação.
