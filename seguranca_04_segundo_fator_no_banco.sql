-- seguranca_04_segundo_fator_no_banco.sql  (12/11/2026, revisao geral de 10/11/2026)
--
-- O que faz (tudo ou nada; pode rodar de novo):
--  1. VERIFICACAO EM DUAS ETAPAS NO BANCO. Quem tem celular cadastrado
--     (fator TOTP confirmado) so le e grava com a sessao confirmada pelo
--     codigo (aal2). Quem nao tem celular cadastrado segue como hoje. Sem isto
--     a tela do app pede o codigo, mas com a senha roubada da para ler o banco
--     por fora do app. Feito com:
--       - funcao segundo_fator_ok();
--       - politica RESTRITIVA "exige_segundo_fator" em toda tabela do public
--         com RLS (restritiva = vale junto com as outras, nunca abre nada);
--       - a mesma regra em ve_todo_o_financeiro() e
--         ve_financeiro_da_pecuaria(), que filtram a visao
--         lancamentos_rateados (a visao roda com os direitos do dono e a RLS
--         das tabelas nao a cobre).
--  2. FUNCIONARIOS, ALOCACAO E AREA POR ATIVIDADE: hoje qualquer usuario
--     logado (ate operador de campo) altera e apaga funcionarios,
--     funcionario_atividades e fazenda_atividades. A leitura continua aberta a
--     quem esta logado (Combustivel, Pecuaria, Cana e Cereais leem); gravar
--     passa a pedir a mesma permissao que a tela do Matriz ja pede
--     (matriz_funcionarios ou matriz_fazendas, editar; ou admin).
--  3. Tira as extensoes dblink e postgres_fdw (sem uso: nenhum servidor
--     externo, nenhuma funcao cita). Com elas qualquer usuario logado podia
--     abrir conexao do banco para fora. Se o Supabase nao deixar apagar, o
--     resto do script vale mesmo assim e a conferencia avisa.
--
-- Funcao de criar usuario (Edge Function criar-usuario-cana): a versao 4 exige
-- o codigo de quem tem celular cadastrado; publicar junto com este script.
--
-- Tabela nova com RLS daqui para frente: rodar este script de novo (ele poe a
-- politica restritiva nas que faltarem). A conferencia (item 3) lista as que
-- estao sem.
-- Desfazer: no fim do arquivo, comentado.

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas')
     or not exists (select 1 from information_schema.tables where table_schema='public' and table_name='lancamentos_financeiros') then
    raise exception 'PROJETO ERRADO: rode no projeto do AE (Matriz/Pecuaria).';
  end if;
  if not exists (select 1 from information_schema.tables where table_schema='auth' and table_name='mfa_factors') then
    raise exception 'auth.mfa_factors nao existe: este banco nao e o do Supabase.';
  end if;
end $$;

-- 1. funcao: true se a sessao pode ler/gravar
create or replace function public.segundo_fator_ok()
returns boolean
language sql
stable
security definer
set search_path = ''
as $f$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f
                      where f.user_id = auth.uid() and f.status = 'verified')
$f$;
revoke all on function public.segundo_fator_ok() from public, anon;
grant execute on function public.segundo_fator_ok() to authenticated;

-- 1b. politica restritiva em toda tabela do public com RLS
do $$
declare t record;
begin
  for t in select c.relname
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind in ('r','p') and c.relrowsecurity
  loop
    execute format('drop policy if exists exige_segundo_fator on public.%I', t.relname);
    execute format('create policy exige_segundo_fator on public.%I as restrictive for all to authenticated
                    using ((select public.segundo_fator_ok())) with check ((select public.segundo_fator_ok()))', t.relname);
  end loop;
end $$;

-- 1c. a visao lancamentos_rateados
create or replace function public.ve_todo_o_financeiro()
returns boolean
language sql
stable
set search_path = public
as $f$
  select current_user in ('postgres', 'supabase_admin', 'service_role')
      or (public.segundo_fator_ok()
          and (coalesce(public.tem_permissao('matriz_resultados', 'visualizar'), false)
               or coalesce(public.tem_permissao('matriz_financeiro', 'visualizar'), false)))
$f$;

create or replace function public.ve_financeiro_da_pecuaria()
returns boolean
language sql
stable
set search_path = public
as $f$
  select public.segundo_fator_ok()
     and (coalesce(public.tem_permissao('pec_financeiro', 'visualizar'), false)
       or coalesce(public.tem_permissao('pec_resultados', 'visualizar'), false)
       or coalesce(public.tem_permissao('vendas', 'visualizar'), false)
       or coalesce(public.tem_permissao('confinamento', 'visualizar'), false)
       or coalesce(public.tem_permissao('pasto', 'visualizar'), false)
       or coalesce(public.tem_permissao('cria', 'visualizar'), false)
       or coalesce(public.tem_permissao('lotesGeral', 'visualizar'), false))
$f$;

-- 2. funcionarios, alocacao e area por atividade: ler aberto a quem esta
--    logado, gravar so com a permissao da tela do Matriz
do $$
declare t record;
begin
  for t in select * from (values ('funcionarios', 'matriz_funcionarios'),
                                 ('funcionario_atividades', 'matriz_funcionarios'),
                                 ('fazenda_atividades', 'matriz_fazendas')) v(tabela, modulo)
  loop
    execute format('drop policy if exists "leitura/escrita autenticado" on public.%I', t.tabela);
    execute format('drop policy if exists ler_logado on public.%I', t.tabela);
    execute format('drop policy if exists inserir_com_permissao on public.%I', t.tabela);
    execute format('drop policy if exists atualizar_com_permissao on public.%I', t.tabela);
    execute format('drop policy if exists excluir_com_permissao on public.%I', t.tabela);
    execute format('create policy ler_logado on public.%I for select to authenticated using (true)', t.tabela);
    execute format('create policy inserir_com_permissao on public.%I for insert to authenticated
                    with check (public.is_admin() or public.tem_permissao(%L, ''editar''))', t.tabela, t.modulo);
    execute format('create policy atualizar_com_permissao on public.%I for update to authenticated
                    using (public.is_admin() or public.tem_permissao(%L, ''editar''))
                    with check (public.is_admin() or public.tem_permissao(%L, ''editar''))', t.tabela, t.modulo, t.modulo);
    execute format('create policy excluir_com_permissao on public.%I for delete to authenticated
                    using (public.is_admin() or public.tem_permissao(%L, ''editar''))', t.tabela, t.modulo);
  end loop;
end $$;

-- 3. extensoes sem uso (se o Supabase recusar, segue sem elas e a conferencia avisa)
do $$
begin
  begin
    drop extension if exists dblink;
  exception when others then
    raise notice 'dblink nao foi apagada: %', sqlerrm;
  end;
  begin
    drop extension if exists postgres_fdw;
  exception when others then
    raise notice 'postgres_fdw nao foi apagada: %', sqlerrm;
  end;
end $$;

-- conferencia
select 1 as ordem, 'funcao segundo_fator_ok' as item,
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'segundo_fator_ok' and p.prosecdef) then 'existe' else 'NAO existe' end as valor,
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'segundo_fator_ok' and p.prosecdef) then 'OK' else 'ERRO' end as situacao
union all
select 2, 'tabelas com RLS e com a politica exige_segundo_fator',
       (select count(*) from pg_policies where schemaname = 'public' and policyname = 'exige_segundo_fator' and permissive = 'RESTRICTIVE')::text
         || ' de ' || (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                        where n.nspname = 'public' and c.relkind in ('r','p') and c.relrowsecurity)::text,
       case when (select count(*) from pg_policies where schemaname = 'public' and policyname = 'exige_segundo_fator' and permissive = 'RESTRICTIVE')
               = (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relkind in ('r','p') and c.relrowsecurity) then 'OK' else 'ERRO' end
union all
select 3, 'tabelas com RLS sem a politica',
       coalesce((select string_agg(c.relname, ', ') from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relkind in ('r','p') and c.relrowsecurity
                    and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname and p.policyname = 'exige_segundo_fator')), 'nenhuma'),
       case when exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                          where n.nspname = 'public' and c.relkind in ('r','p') and c.relrowsecurity
                            and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname and p.policyname = 'exige_segundo_fator'))
            then 'ERRO' else 'OK' end
union all
select 4, 'visao rateada exige o codigo',
       case when pg_get_functiondef('public.ve_todo_o_financeiro()'::regprocedure) like '%segundo_fator_ok%'
             and pg_get_functiondef('public.ve_financeiro_da_pecuaria()'::regprocedure) like '%segundo_fator_ok%' then 'sim' else 'NAO' end,
       case when pg_get_functiondef('public.ve_todo_o_financeiro()'::regprocedure) like '%segundo_fator_ok%'
             and pg_get_functiondef('public.ve_financeiro_da_pecuaria()'::regprocedure) like '%segundo_fator_ok%' then 'OK' else 'ERRO' end
union all
select 5, 'funcionarios/alocacao/area: gravar so com permissao',
       coalesce((select string_agg(tablename || ' ' || cmd, ', ' order by tablename, cmd) from pg_policies
         where schemaname = 'public' and tablename in ('funcionarios','funcionario_atividades','fazenda_atividades')
           and coalesce(qual,'') || coalesce(with_check,'') like '%auth.role()%'), 'nenhuma aberta a qualquer logado'),
       case when exists (select 1 from pg_policies where schemaname = 'public'
                          and tablename in ('funcionarios','funcionario_atividades','fazenda_atividades')
                          and coalesce(qual,'') || coalesce(with_check,'') like '%auth.role()%') then 'ERRO' else 'OK' end
union all
select 6, 'extensoes dblink e postgres_fdw',
       coalesce((select string_agg(extname, ', ') from pg_extension where extname in ('dblink','postgres_fdw')), 'apagadas'),
       case when exists (select 1 from pg_extension where extname in ('dblink','postgres_fdw'))
            then 'ATENCAO: o Supabase nao deixou apagar; o resto vale' else 'OK' end
union all
select 7, 'pessoas com celular cadastrado (so elas passam a precisar do codigo)',
       (select count(distinct user_id) from auth.mfa_factors where status = 'verified')::text, 'OK'
order by 1;

-- DESFAZER (so se precisar; rode as linhas abaixo sem os dois tracos):
-- do $$ declare t record; begin for t in select tablename from pg_policies where schemaname='public' and policyname='exige_segundo_fator' loop execute format('drop policy exige_segundo_fator on public.%I', t.tablename); end loop; end $$;
-- create or replace function public.ve_todo_o_financeiro() returns boolean language sql stable as $f$ select current_user in ('postgres','supabase_admin','service_role') or coalesce(public.tem_permissao('matriz_resultados','visualizar'),false) or coalesce(public.tem_permissao('matriz_financeiro','visualizar'),false) $f$;
-- create or replace function public.ve_financeiro_da_pecuaria() returns boolean language sql stable as $f$ select coalesce(public.tem_permissao('pec_financeiro','visualizar'),false) or coalesce(public.tem_permissao('pec_resultados','visualizar'),false) or coalesce(public.tem_permissao('vendas','visualizar'),false) or coalesce(public.tem_permissao('confinamento','visualizar'),false) or coalesce(public.tem_permissao('pasto','visualizar'),false) or coalesce(public.tem_permissao('cria','visualizar'),false) or coalesce(public.tem_permissao('lotesGeral','visualizar'),false) $f$;
-- drop function if exists public.segundo_fator_ok();
-- do $$ declare t text; begin foreach t in array array['funcionarios','funcionario_atividades','fazenda_atividades'] loop execute format('drop policy if exists ler_logado on public.%I', t); execute format('drop policy if exists inserir_com_permissao on public.%I', t); execute format('drop policy if exists atualizar_com_permissao on public.%I', t); execute format('drop policy if exists excluir_com_permissao on public.%I', t); execute format('create policy "leitura/escrita autenticado" on public.%I for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t); end loop; end $$;
-- (dblink e postgres_fdw: se precisar de novo, Database > Extensions no painel do Supabase)
