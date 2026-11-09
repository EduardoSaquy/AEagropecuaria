# Backup automático do banco (Supabase gratuito)

O plano gratuito do Supabase **não guarda cópia do banco** (a documentação deles recomenda exportar com `pg_dump` e guardar fora). O app tem um botão
"Baixar cópia" (Usuários), mas depende de alguém lembrar. Aqui o GitHub faz sozinho, todo dia, de graça.

## O que fica pronto e o que cada coisa faz

- `backup.yml`: a tarefa que roda todo dia às 03:00 (Brasil) e quando você mandar. Copia o schema `public` (todas as tabelas dos apps, as visões, as
  funções e as regras de segurança) e, à parte, o schema `auth` (as contas de login), confere que o arquivo saiu inteiro e guarda por **14 dias**.
- **Tem que ir para um repositório PRIVADO**, nunca para este (público): o arquivo de backup fica como "artefato" da execução, e artefato de repositório
  público pode ser baixado por qualquer pessoa.
- Custa R$ 0: GitHub gratuito dá 2.000 minutos por mês (o backup usa 2 a 3 minutos por dia) e 500 MB de artefatos (por isso 14 dias; com o tamanho do
  banco dá para calcular quantos dias cabem).

## Passo a passo (uma vez só, uns 15 minutos)

1. **No Supabase, SQL Editor**, rode e me mande o resultado (só leitura): `select version() as versao, pg_size_pretty(pg_database_size(current_database())) as tamanho_do_banco;`
   A versão decide o número `VERSAO_PG` do `backup.yml` e o tamanho decide quantos dias cabem em 500 MB.
2. **No Supabase, botão "Connect" (topo da página) → "Session pooler" → copie a "URI"**. Ela tem um `[YOUR-PASSWORD]`: troque pela senha do banco.
   Se não lembra a senha: Project Settings → Database → "Reset database password" e escolha uma senha longa (guarde num gerenciador de senhas).
   Os apps não usam essa senha (eles usam as chaves da API), então trocá-la não derruba nada. **Não cole a senha nem a URI no chat.**
   (Tem que ser o "Session pooler" e não a conexão direta: a direta só funciona por IPv6 e o GitHub só fala IPv4.)
3. **No GitHub, crie um repositório PRIVADO** chamado `AEagropecuaria-backup` (marque "Private").
4. **Nesse repositório novo**: Add file → Create new file → nome `.github/workflows/backup.yml` → cole o conteúdo do `backup.yml` desta pasta → Commit.
5. **Settings → Secrets and variables → Actions → New repository secret**: nome `DATABASE_URL`, valor = a URI do passo 2 (com a senha). O GitHub não mostra
   esse valor depois nem nos registros.
6. **Aba Actions → "Backup do banco" → Run workflow.** Em 1 a 2 minutos fica verde. Abra a execução: o passo "Confere que o backup dos apps saiu inteiro" mostra
   `tabelas com dados: N` e o tamanho; no fim da página, o artefato `backup-banco` (baixe e confira que não é um arquivo de poucos KB).
7. **Recomendado:** ligar a verificação em duas etapas na sua conta do GitHub (o backup tem todos os dados da empresa).

Se qualquer execução falhar, o GitHub manda e-mail. Se o e-mail passar batido, a aba Actions mostra o X vermelho.

## Como restaurar (se um dia precisar)

Num projeto Supabase **novo e vazio** (ou no mesmo, depois de apagar o que estiver errado), com o `pg_restore` da mesma versão do banco:

```
pg_restore --no-owner --no-privileges --clean --if-exists --dbname="URI_DO_SESSION_POOLER" apps_AAAA-MM-DD_HHMM.dump
pg_restore --no-owner --no-privileges --data-only --dbname="URI_DO_SESSION_POOLER" login_AAAA-MM-DD_HHMM.dump
```

O primeiro traz tudo dos apps; o segundo traz as contas de login. Depois, conferir no app: entrar, abrir o Financeiro e a Pecuária. Os apps leem o endereço do
projeto dentro do código (`AEMatriz.html` e os outros): um projeto novo tem endereço e chaves novos, e é preciso trocar nos 5 apps.

## O que foi e o que NÃO foi testado

- **Testado** (09/11/2026, num Postgres descartável): os mesmos comandos do `backup.yml` (`pg_dump` em formato custom dos dois schemas, `pg_restore --list`
  contando as tabelas) e a restauração num banco novo: as linhas voltam, a segurança por linha volta ligada, a visão e a função voltam, e as contas de login.
- **Não testado**: a conexão de verdade pelo Session pooler do Supabase (só se vê na primeira execução), e se o schema `auth` do Supabase deixa o `pg_dump`
  ler tudo (por isso o passo do `auth` é "continuar mesmo se falhar": o dos apps vale sozinho). A primeira execução é o teste.
- **Limites**: não copia arquivos do Storage (o app não usa); o backup é de 1 vez por dia (você pode perder até 1 dia de lançamentos); 14 dias de histórico.

## Manutenção

- Se o Supabase trocar a versão do Postgres, troque `VERSAO_PG` no `backup.yml` (um `pg_dump` mais velho que o banco recusa).
- Se a senha do banco mudar, atualize o segredo `DATABASE_URL`.
- O arquivo tem senhas de login em forma de hash e todos os dados financeiros: baixe só quando precisar e apague depois.
