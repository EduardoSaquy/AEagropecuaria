-- seguranca_06_financeiro_so_para_quem_pode.sql  (12/11/2026)
--
-- Decisao do Eduardo: o financeiro e so dele e dos proprietarios.
-- O que faz (tudo ou nada; pode rodar de novo):
--  1. AUTOR DE CADA LANCAMENTO: lancamentos_financeiros.criado_por_id (uuid de
--     quem gravou). O banco preenche sozinho (um gatilho ignora o que o app
--     mandar) e ninguem troca o autor depois pela API. Os lancamentos antigos
--     feitos no app ganham o autor pelo registro de alteracoes.
--  2. LANCAMENTOS: veem e editam tudo so administrador e proprietario. Quem
--     tem "Financeiro" no Matriz e nao e proprietario ve e edita SO os
--     lancamentos que ele mesmo fez. Quem tem "Vendas" continua lancando e
--     vendo a receita da venda de animais (so as ligadas a uma venda).
--     Antes: o Financeiro do Matriz via tudo, e Financeiro, Resultados ou
--     Vendas da Pecuaria viam todos os lancamentos da Pecuaria.
--  3. VISAO RATEADA (lancamentos_rateados): so administrador e proprietario.
--     Antes: quem tinha Financeiro ou Resultados do Matriz via tudo, e quem
--     tinha Confinamento, Pasto, Cria, Lotes, Vendas ou Financeiro/Resultados
--     da Pecuaria via a parte da Pecuaria.
--  4. CONTAS A PAGAR E RECEBER: a permissao "Contas" basta (antes exigia
--     tambem o Financeiro; quem tinha so Contas via a tela vazia e nao
--     conseguia lancar). Quem tem Contas tambem le fazendas, talhoes,
--     culturas e centros de custo, que a tela da conta usa.
--  5. FINANCIAMENTOS e PRECO DA ARROBA: so administrador e proprietario.
--
-- A politica restritiva de duas etapas (seguranca_04) continua valendo junto.
-- Preco de ingrediente, de dieta e de nota de diesel ficam nas tabelas da
-- operacao: esses o app esconde so na tela.
-- Rodar DEPOIS de publicar o app de 12/11/2026 (ele ja esconde o que for de
-- quem nao tem acesso total).
-- Desfazer: no fim do arquivo, comentado.

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas')
     or not exists (select 1 from information_schema.tables where table_schema='public' and table_name='lancamentos_financeiros') then
    raise exception 'PROJETO ERRADO: rode no projeto do AE (Matriz/Pecuaria).';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'segundo_fator_ok') then
    raise exception 'Rode antes o seguranca_04_segundo_fator_no_banco.sql.';
  end if;
end $$;

-- 1. autor do lancamento
alter table public.lancamentos_financeiros add column if not exists criado_por_id uuid;
alter table public.lancamentos_financeiros alter column criado_por_id set default auth.uid();
create index if not exists lancamentos_financeiros_criado_por_id_idx
  on public.lancamentos_financeiros (criado_por_id) where criado_por_id is not null;
comment on column public.lancamentos_financeiros.criado_por_id is
  'Quem gravou (auth.uid). Preenchido pelo banco; quem nao e proprietario ve so os seus (seguranca_06).';

-- lancamentos antigos feitos no app: o autor vem do registro de alteracoes
update public.lancamentos_financeiros l
   set criado_por_id = x.quem_id
  from (select distinct on (registro_id) registro_id, quem_id
          from public.log_alteracoes
         where tabela = 'lancamentos_financeiros' and operacao = 'INSERT' and quem_id is not null
         order by registro_id, quando) x
 where l.criado_por_id is null
   and x.registro_id = l.id::text;

-- quem grava pela API nao escolhe o autor nem troca depois. Roda com os
-- direitos de quem chama: pela API e "authenticated"; dentro de funcao do
-- banco com direitos do dono (baixa de conta) ou no editor fica o padrao
-- da coluna, que ja e quem esta logado.
create or replace function public.lancamento_guarda_autor()
returns trigger
language plpgsql
set search_path = ''
as $f$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.criado_por_id := auth.uid();
    else
      new.criado_por_id := old.criado_por_id;
    end if;
  end if;
  return new;
end
$f$;
drop trigger if exists trg_lancamento_autor on public.lancamentos_financeiros;
create trigger trg_lancamento_autor
  before insert or update on public.lancamentos_financeiros
  for each row execute function public.lancamento_guarda_autor();

-- 2. lancamentos
drop policy if exists "ve lancamentos" on public.lancamentos_financeiros;
drop policy if exists "lanca" on public.lancamentos_financeiros;
drop policy if exists "edita lancamentos" on public.lancamentos_financeiros;

create policy "ve lancamentos" on public.lancamentos_financeiros
  for select to authenticated
  using (
    (select public.acesso_total())
    or (criado_por_id = (select auth.uid()) and (select public.tem_permissao('matriz_financeiro', 'visualizar')))
    or (abate_id is not null and (select public.tem_permissao('vendas', 'visualizar')))
  );

create policy "lanca" on public.lancamentos_financeiros
  for insert to authenticated
  with check (
    (select public.acesso_total())
    or (select public.tem_permissao('matriz_financeiro', 'editar'))
    or (abate_id is not null and tipo = 'receita' and atividade = 'pecuaria'
        and (select public.tem_permissao('vendas', 'editar')))
  );

create policy "edita lancamentos" on public.lancamentos_financeiros
  for update to authenticated
  using (
    (select public.acesso_total())
    or (criado_por_id = (select auth.uid()) and (select public.tem_permissao('matriz_financeiro', 'editar')))
    or (abate_id is not null and (select public.tem_permissao('vendas', 'editar')))
  )
  with check (
    (select public.acesso_total())
    or (criado_por_id = (select auth.uid()) and (select public.tem_permissao('matriz_financeiro', 'editar')))
    or (abate_id is not null and (select public.tem_permissao('vendas', 'editar')))
  );

-- 3. visao rateada
create or replace function public.ve_todo_o_financeiro()
returns boolean
language sql
stable
set search_path = 'public'
as $f$
  select current_user in ('postgres', 'supabase_admin', 'service_role')
      or (public.segundo_fator_ok() and coalesce(public.acesso_total(), false))
$f$;

create or replace function public.ve_financeiro_da_pecuaria()
returns boolean
language sql
stable
set search_path = 'public'
as $f$
  select public.ve_todo_o_financeiro()
$f$;

-- 4. contas a pagar e receber: so a permissao Contas
do $$
declare
  t text;
begin
  foreach t in array array['titulos', 'titulo_rateios', 'titulo_baixas', 'entidades', 'contas_bancarias'] loop
    execute format('drop policy if exists %I on public.%I', 've ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'cria ' || t, t);
    execute format('drop policy if exists %I on public.%I', 'altera ' || t, t);
    execute format('create policy %I on public.%I for select to authenticated using '
                   '((select public.is_dono()) or (select public.tem_permissao(''contas'', ''visualizar'')))', 've ' || t, t);
    execute format('create policy %I on public.%I for insert to authenticated with check '
                   '((select public.is_dono()) or (select public.tem_permissao(''contas'', ''editar'')))', 'cria ' || t, t);
    execute format('create policy %I on public.%I for update to authenticated using '
                   '((select public.is_dono()) or (select public.tem_permissao(''contas'', ''editar''))) with check '
                   '((select public.is_dono()) or (select public.tem_permissao(''contas'', ''editar'')))', 'altera ' || t, t);
  end loop;
end $$;
drop policy if exists "exclui titulo_rateios" on public.titulo_rateios;
create policy "exclui titulo_rateios" on public.titulo_rateios
  for delete to authenticated
  using ((select public.is_dono()) or (select public.tem_permissao('contas', 'editar')));

-- a tela da conta precisa do rateio: fazenda, talhao, cultura e centro de custo
do $$
declare
  t text;
begin
  foreach t in array array['fazendas', 'talhoes_areas', 'culturas', 'centros_custo'] loop
    execute format('drop policy if exists %I on public.%I', 'ler para contas', t);
    execute format('create policy %I on public.%I for select to authenticated using '
                   '((select public.tem_permissao(''contas'', ''visualizar'')))', 'ler para contas', t);
  end loop;
end $$;

-- 5. financiamentos e preco da arroba: so acesso total
drop policy if exists "ve financiamentos" on public.financiamentos;
drop policy if exists "lanca financiamento" on public.financiamentos;
drop policy if exists "edita financiamento" on public.financiamentos;
drop policy if exists "exclui financiamento" on public.financiamentos;
create policy "ve financiamentos" on public.financiamentos for select to authenticated using ((select public.acesso_total()));
create policy "lanca financiamento" on public.financiamentos for insert to authenticated with check ((select public.acesso_total()));
create policy "edita financiamento" on public.financiamentos for update to authenticated
  using ((select public.acesso_total())) with check ((select public.acesso_total()));
create policy "exclui financiamento" on public.financiamentos for delete to authenticated using ((select public.acesso_total()));

drop policy if exists "ve parcelas" on public.parcelas_financiamento;
drop policy if exists "lanca parcela" on public.parcelas_financiamento;
drop policy if exists "edita parcela" on public.parcelas_financiamento;
drop policy if exists "exclui parcela" on public.parcelas_financiamento;
create policy "ve parcelas" on public.parcelas_financiamento for select to authenticated using ((select public.acesso_total()));
create policy "lanca parcela" on public.parcelas_financiamento for insert to authenticated with check ((select public.acesso_total()));
create policy "edita parcela" on public.parcelas_financiamento for update to authenticated
  using ((select public.acesso_total())) with check ((select public.acesso_total()));
create policy "exclui parcela" on public.parcelas_financiamento for delete to authenticated using ((select public.acesso_total()));

drop policy if exists "ve movimentos financiamento" on public.movimentos_financiamento;
drop policy if exists "lanca movimento financiamento" on public.movimentos_financiamento;
drop policy if exists "edita movimento financiamento" on public.movimentos_financiamento;
drop policy if exists "exclui movimento financiamento" on public.movimentos_financiamento;
create policy "ve movimentos financiamento" on public.movimentos_financiamento for select to authenticated using ((select public.acesso_total()));
create policy "lanca movimento financiamento" on public.movimentos_financiamento for insert to authenticated with check ((select public.acesso_total()));
create policy "edita movimento financiamento" on public.movimentos_financiamento for update to authenticated
  using ((select public.acesso_total())) with check ((select public.acesso_total()));
create policy "exclui movimento financiamento" on public.movimentos_financiamento for delete to authenticated using ((select public.acesso_total()));

drop policy if exists "select precos_arroba" on public.precos_arroba;
drop policy if exists "inserir precos_arroba" on public.precos_arroba;
drop policy if exists "atualizar precos_arroba" on public.precos_arroba;
create policy "select precos_arroba" on public.precos_arroba for select to authenticated using ((select public.acesso_total()));
create policy "inserir precos_arroba" on public.precos_arroba for insert to authenticated with check ((select public.acesso_total()));
create policy "atualizar precos_arroba" on public.precos_arroba for update to authenticated
  using ((select public.acesso_total())) with check ((select public.acesso_total()));

-- conferencia (uma consulta so: cada linha diz OK ou o que esta errado)
with pol as (
  select c.relname as tabela, p.polname,
         coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as expr
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
)
select '1. coluna do autor' as item,
       (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'lancamentos_financeiros' and column_name = 'criado_por_id')::text as valor,
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'lancamentos_financeiros' and column_name = 'criado_por_id')
            then 'OK' else 'FALTA a coluna criado_por_id' end as situacao
union all
select '2. gatilho do autor',
       (select count(*) from pg_trigger where tgname = 'trg_lancamento_autor' and not tgisinternal)::text,
       case when exists (select 1 from pg_trigger where tgname = 'trg_lancamento_autor' and not tgisinternal)
            then 'OK' else 'FALTA o gatilho trg_lancamento_autor' end
union all
select '3. lancamentos com autor (feitos no app)',
       (select count(*) from public.lancamentos_financeiros where criado_por_id is not null)::text,
       'OK (so informativo)'
union all
select '4. regras de lancamentos_financeiros',
       (select string_agg(polname, ', ' order by polname) from pol where tabela = 'lancamentos_financeiros'),
       case when (select count(*) from pol where tabela = 'lancamentos_financeiros'
                   and polname in ('ve lancamentos', 'lanca', 'edita lancamentos', 'so dono exclui', 'exige_segundo_fator')) = 5
             and not exists (select 1 from pol where tabela = 'lancamentos_financeiros' and expr like '%pec_financeiro%')
            then 'OK' else 'ERRADO: confira as regras de lancamentos_financeiros' end
union all
select '5. contas a pagar sem exigir o Financeiro',
       (select count(*) from pol where tabela in ('titulos', 'titulo_rateios', 'titulo_baixas', 'entidades', 'contas_bancarias')
           and expr like '%matriz_financeiro%')::text,
       case when not exists (select 1 from pol where tabela in ('titulos', 'titulo_rateios', 'titulo_baixas', 'entidades', 'contas_bancarias')
                              and expr like '%matriz_financeiro%')
            then 'OK' else 'ERRADO: alguma regra das contas ainda pede o Financeiro' end
union all
select '6. financiamentos e preco da arroba so acesso total',
       (select count(*) from pol where tabela in ('financiamentos', 'parcelas_financiamento', 'movimentos_financiamento', 'precos_arroba')
           and (expr like '%tem_permissao%' or expr like '%is_admin%'))::text,
       case when not exists (select 1 from pol where tabela in ('financiamentos', 'parcelas_financiamento', 'movimentos_financiamento', 'precos_arroba')
                              and (expr like '%tem_permissao%' or expr like '%is_admin%'))
            then 'OK' else 'ERRADO: sobrou regra por permissao' end
union all
select '7. visao rateada so acesso total',
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 've_todo_o_financeiro'
           and pg_get_functiondef(p.oid) like '%acesso_total%'
           and pg_get_functiondef(p.oid) not like '%matriz_resultados%')::text,
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 've_todo_o_financeiro'
                            and pg_get_functiondef(p.oid) like '%acesso_total%'
                            and pg_get_functiondef(p.oid) not like '%matriz_resultados%')
            then 'OK' else 'ERRADO: ve_todo_o_financeiro ainda abre por permissao' end
union all
select '8. duas etapas em toda tabela com RLS',
       (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
           and not exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polname = 'exige_segundo_fator'))::text,
       case when not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                              where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
                                and not exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polname = 'exige_segundo_fator'))
            then 'OK' else 'ATENCAO: rode o seguranca_04 de novo' end;

-- DESFAZER (so se precisar; volta as regras de antes): rode as linhas abaixo sem os dois tracos do comeco.
-- drop trigger if exists trg_lancamento_autor on public.lancamentos_financeiros;
-- drop function if exists public.lancamento_guarda_autor();
-- drop policy if exists "ve lancamentos" on public.lancamentos_financeiros;
-- drop policy if exists "lanca" on public.lancamentos_financeiros;
-- drop policy if exists "edita lancamentos" on public.lancamentos_financeiros;
-- create policy "ve lancamentos" on public.lancamentos_financeiros for select using (is_admin() or tem_permissao('matriz_financeiro','visualizar') or ((atividade = 'pecuaria') and (tem_permissao('pec_financeiro','visualizar') or tem_permissao('pec_resultados','visualizar') or tem_permissao('vendas','visualizar'))));
-- create policy "lanca" on public.lancamentos_financeiros for insert with check (is_admin() or tem_permissao('matriz_financeiro','editar') or ((atividade = 'pecuaria') and (tem_permissao('pec_resultados','editar') or tem_permissao('vendas','editar'))));
-- create policy "edita lancamentos" on public.lancamentos_financeiros for update using (is_admin() or tem_permissao('matriz_financeiro','editar') or ((atividade = 'pecuaria') and (tem_permissao('pec_resultados','editar') or tem_permissao('vendas','editar')))) with check (is_admin() or tem_permissao('matriz_financeiro','editar') or ((atividade = 'pecuaria') and (tem_permissao('pec_resultados','editar') or tem_permissao('vendas','editar'))));
-- create or replace function public.ve_todo_o_financeiro() returns boolean language sql stable set search_path = 'public' as $f$ select current_user in ('postgres','supabase_admin','service_role') or (public.segundo_fator_ok() and (coalesce(public.tem_permissao('matriz_resultados','visualizar'),false) or coalesce(public.tem_permissao('matriz_financeiro','visualizar'),false))) $f$;
-- create or replace function public.ve_financeiro_da_pecuaria() returns boolean language sql stable set search_path = 'public' as $f$ select public.segundo_fator_ok() and (coalesce(public.tem_permissao('pec_financeiro','visualizar'),false) or coalesce(public.tem_permissao('pec_resultados','visualizar'),false) or coalesce(public.tem_permissao('vendas','visualizar'),false) or coalesce(public.tem_permissao('confinamento','visualizar'),false) or coalesce(public.tem_permissao('pasto','visualizar'),false) or coalesce(public.tem_permissao('cria','visualizar'),false) or coalesce(public.tem_permissao('lotesGeral','visualizar'),false)) $f$;
-- do $$ declare t text; begin foreach t in array array['titulos','titulo_rateios','titulo_baixas','entidades','contas_bancarias'] loop
--   execute format('drop policy if exists %I on public.%I', 've ' || t, t);
--   execute format('drop policy if exists %I on public.%I', 'cria ' || t, t);
--   execute format('drop policy if exists %I on public.%I', 'altera ' || t, t);
--   execute format('create policy %I on public.%I for select using (is_dono() or (tem_permissao(''matriz_financeiro'',''visualizar'') and tem_permissao(''contas'',''visualizar'')))', 've ' || t, t);
--   execute format('create policy %I on public.%I for insert with check (is_dono() or (tem_permissao(''matriz_financeiro'',''visualizar'') and tem_permissao(''contas'',''editar'')))', 'cria ' || t, t);
--   execute format('create policy %I on public.%I for update using (is_dono() or (tem_permissao(''matriz_financeiro'',''visualizar'') and tem_permissao(''contas'',''editar''))) with check (is_dono() or (tem_permissao(''matriz_financeiro'',''visualizar'') and tem_permissao(''contas'',''editar'')))', 'altera ' || t, t);
--   end loop;
--   foreach t in array array['fazendas','talhoes_areas','culturas','centros_custo'] loop execute format('drop policy if exists %I on public.%I', 'ler para contas', t); end loop; end $$;
-- drop policy if exists "exclui titulo_rateios" on public.titulo_rateios;
-- create policy "exclui titulo_rateios" on public.titulo_rateios for delete using (is_dono() or (tem_permissao('matriz_financeiro','visualizar') and tem_permissao('contas','editar')));
-- drop policy if exists "ve financiamentos" on public.financiamentos; create policy "ve financiamentos" on public.financiamentos for select using (is_admin() or tem_permissao('matriz_financiamentos','visualizar'));
-- drop policy if exists "lanca financiamento" on public.financiamentos; create policy "lanca financiamento" on public.financiamentos for insert with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "edita financiamento" on public.financiamentos; create policy "edita financiamento" on public.financiamentos for update using (is_admin() or tem_permissao('matriz_financiamentos','editar')) with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "exclui financiamento" on public.financiamentos; create policy "exclui financiamento" on public.financiamentos for delete using (is_dono() or is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "ve parcelas" on public.parcelas_financiamento; create policy "ve parcelas" on public.parcelas_financiamento for select using (is_admin() or tem_permissao('matriz_financiamentos','visualizar'));
-- drop policy if exists "lanca parcela" on public.parcelas_financiamento; create policy "lanca parcela" on public.parcelas_financiamento for insert with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "edita parcela" on public.parcelas_financiamento; create policy "edita parcela" on public.parcelas_financiamento for update using (is_admin() or tem_permissao('matriz_financiamentos','editar')) with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "exclui parcela" on public.parcelas_financiamento; create policy "exclui parcela" on public.parcelas_financiamento for delete using (is_dono() or is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "ve movimentos financiamento" on public.movimentos_financiamento; create policy "ve movimentos financiamento" on public.movimentos_financiamento for select using (is_admin() or tem_permissao('matriz_financiamentos','visualizar') or tem_permissao('matriz_resultados','visualizar'));
-- drop policy if exists "lanca movimento financiamento" on public.movimentos_financiamento; create policy "lanca movimento financiamento" on public.movimentos_financiamento for insert with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "edita movimento financiamento" on public.movimentos_financiamento; create policy "edita movimento financiamento" on public.movimentos_financiamento for update using (is_admin() or tem_permissao('matriz_financiamentos','editar')) with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "exclui movimento financiamento" on public.movimentos_financiamento; create policy "exclui movimento financiamento" on public.movimentos_financiamento for delete using (is_admin() or tem_permissao('matriz_financiamentos','editar'));
-- drop policy if exists "select precos_arroba" on public.precos_arroba; create policy "select precos_arroba" on public.precos_arroba for select using (tem_permissao('pec_financeiro','visualizar'));
-- drop policy if exists "inserir precos_arroba" on public.precos_arroba; create policy "inserir precos_arroba" on public.precos_arroba for insert with check (tem_permissao('pec_financeiro','editar'));
-- drop policy if exists "atualizar precos_arroba" on public.precos_arroba; create policy "atualizar precos_arroba" on public.precos_arroba for update using (tem_permissao('pec_financeiro','editar')) with check (tem_permissao('pec_financeiro','editar'));
-- (a coluna criado_por_id pode ficar: sem as regras acima ela nao muda nada)
