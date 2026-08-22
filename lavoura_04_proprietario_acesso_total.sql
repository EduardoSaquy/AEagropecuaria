-- ============================================================
-- PROPRIETARIO PASSA A TER ACESSO TOTAL NO BANCO, COMO O APP JA PROMETE
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Rode ANTES de subir os HTMLs.
--
-- ------------------------------------------------------------
-- O PROBLEMA
--
-- Os apps tratam admin e proprietario como equivalentes desde sempre. A
-- propria tela de permissoes do Matriz diz, em cima da tabela: "Admin e
-- Proprietario tem acesso total; esta matriz so vale para os outros
-- papeis" - e por isso ela nao desenha as caixinhas para esses dois.
--
-- O banco discorda. A funcao is_admin() so aceita papel = 'admin':
--
--   select exists(select 1 from profiles
--                  where id = auth.uid() and papel = 'admin' and ativo = true)
--
-- E tem_permissao() delega para ela. Resultado: proprietario so consegue o
-- que estiver escrito na coluna permissoes dele - e o diagnostico mostrou
-- que NINGUEM tem chave matriz_*, porque a tela nunca ofereceu essas
-- caixinhas para quem e proprietario.
--
-- Na pratica, hoje, Alice, Marcia e Paulo:
--
--   lancamentos_financeiros   nao leem nem escrevem (Financeiro do Matriz)
--   fazendas                  nao cadastram nem editam
--   centros_custo             nao cadastram nem editam
--
-- ISSO NAO VEIO DA SEPARACAO DOS APPS. O bloqueio do financeiro nasceu no
-- meu financeiro_01_modelo_unico.sql, semanas atras, quando escrevi as
-- politicas como "is_admin() or tem_permissao('matriz_financeiro',...)"
-- sem conferir se proprietario passava em alguma das duas. Passou
-- despercebido porque voce e admin: funciona para voce e nao para eles.
--
-- ------------------------------------------------------------
-- O CONSERTO
--
-- Uma funcao nova, acesso_total(), que vale para admin E proprietario.
-- tem_permissao() passa a chamar ela no lugar de is_admin().
--
-- POR QUE NAO SIMPLESMENTE ALARGAR is_admin()
--
-- Porque existe coisa que e mesmo so de admin - criar conta de usuario e
-- mexer em permissao dos outros - e os apps ja tratam assim (a aba
-- Usuarios usa souAdmin(), nao acessoTotal()). Alargar is_admin() daria
-- isso ao proprietario de lambuja. Com duas funcoes, cada politica continua
-- dizendo exatamente o que queria dizer:
--
--   is_admin()      so administrador  -> continua valendo onde ja esta
--   acesso_total()  admin ou dono     -> passa a valer via tem_permissao
--
-- Nenhuma politica precisa ser reescrita: todas que dizem
-- "is_admin() or tem_permissao(...)" passam a aceitar proprietario pelo
-- segundo termo.
--
-- COMO O SCRIPT EVITA CHUTAR
--
-- Ele nao redigita as funcoes a partir do que eu acho que elas sao. Le a
-- definicao real com pg_get_functiondef e troca so o pedaco necessario,
-- preservando linguagem, volatilidade, security definer e search_path
-- exatamente como estao. Se o texto nao for o esperado, PARA e avisa, em
-- vez de gravar uma versao inventada por cima.
-- ============================================================

do $acesso$
declare
  def_admin text;
  def_perm  text;
  novo      text;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- ---------- 1) acesso_total(), clonada de is_admin() ----------
  select pg_get_functiondef(p.oid) into def_admin
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'is_admin' and p.pronargs = 0;

  if def_admin is null then
    raise exception 'Nao achei a funcao is_admin() no schema public.';
  end if;
  if position('papel = ''admin''' in def_admin) = 0 then
    raise exception
      'is_admin() nao tem o trecho "papel = ''''admin''''" que eu esperava. Nao vou adivinhar o conserto. Me mande: select pg_get_functiondef(oid) from pg_proc where proname = ''is_admin'';';
  end if;

  novo := replace(def_admin, 'papel = ''admin''', 'papel in (''admin'', ''proprietario'')');
  novo := replace(novo, 'FUNCTION public.is_admin(', 'FUNCTION public.acesso_total(');
  if position('acesso_total' in novo) = 0 then
    raise exception 'Nao consegui renomear a funcao clonada. Definicao inesperada.';
  end if;
  execute novo;
  raise notice 'acesso_total() criada a partir de is_admin(), preservando os atributos dela.';

  -- ---------- 2) tem_permissao() passa a chamar acesso_total() ----------
  select pg_get_functiondef(p.oid) into def_perm
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'tem_permissao';

  if def_perm is null then
    raise exception 'Nao achei a funcao tem_permissao() no schema public.';
  end if;

  if position('acesso_total()' in def_perm) > 0 then
    -- Ja foi ajustada numa rodada anterior. Rodar de novo nao e erro.
    raise notice 'tem_permissao() ja chamava acesso_total(). Nada a fazer.';
  elsif position('is_admin()' in def_perm) = 0 then
    raise exception
      'tem_permissao() nao chama is_admin() nem acesso_total(), ao contrario do que eu vi. Nao vou reescrever no escuro. Me mande: select pg_get_functiondef(oid) from pg_proc where proname = ''tem_permissao'';';
  else
    execute replace(def_perm, 'is_admin()', 'acesso_total()');
    raise notice 'tem_permissao() agora aceita admin e proprietario.';
  end if;
end
$acesso$;


-- ============================================================
-- CONFERENCIA 1 - AS DUAS FUNCOES FICARAM COMO DEVIAM
--
-- is_admin  tem que continuar so com 'admin'.
-- acesso_total  tem que ter 'admin' e 'proprietario'.
-- tem_permissao  tem que chamar acesso_total, e nao mais is_admin.
-- ============================================================
select p.proname as funcao,
       case when p.prosrc like '%proprietario%' then 'inclui proprietario'
            when p.prosrc like '%acesso_total%' then 'chama acesso_total'
            when p.prosrc like '%is_admin%'     then '*** ainda chama is_admin ***'
            else 'so admin' end as situacao
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('is_admin', 'acesso_total', 'tem_permissao')
order by p.proname;


-- ============================================================
-- CONFERENCIA 2 - QUEM GANHA ACESSO COM ISSO
--
-- Os proprietarios tem que aparecer com acesso_total = true. Se algum
-- continuar false, ele esta inativo.
-- ============================================================
select nome, papel, ativo,
       (papel in ('admin','proprietario') and ativo) as acesso_total,
       coalesce(array_length(array(select jsonb_object_keys(coalesce(permissoes,'{}'::jsonb))), 1), 0) as chaves_soltas
from profiles
order by papel, nome;
