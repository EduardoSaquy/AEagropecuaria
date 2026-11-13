-- ============================================================
-- DESEMPENHO 01 - REGRAS DE ACESSO AVALIADAS UMA VEZ POR CONSULTA (13/11/2026)
--
-- As regras de acesso (RLS) chamavam tem_permissao(...), acesso_total(),
-- is_admin(), auth.uid() etc. LINHA A LINHA: ler os 9.838 movimentos da
-- Pecuaria levava ~2 s por pagina de 1000. Embrulhar cada chamada em
-- (select ...) faz o banco calcular uma vez por consulta (e a recomendacao
-- do Supabase). Nao muda quem ve ou grava o que: as funcoes so dependem de
-- quem esta logado, igual em todas as linhas da mesma consulta.
--
-- So reescreve as regras do schema public que tem essas chamadas soltas;
-- pode rodar de novo (o que ja esta embrulhado fica como esta).
-- Guarda o texto antigo em zz_backup_regras_2026_11_13 (fechada).
-- Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
end $guarda$;

create or replace function pg_temp.embrulha(e text) returns text language sql immutable as $f$
  select case when e is null then null else
    regexp_replace(
      regexp_replace(e,
        '(?<!SELECT )\m(public\.)?(tem_permissao|is_admin|is_dono|acesso_total|pode_excluir|segundo_fator_ok|eh_consultor|ve_todo_o_financeiro|ve_financeiro_da_pecuaria)\(([^()]*)\)',
        '(SELECT \1\2(\3))', 'g'),
      '(?<!SELECT )\mauth\.uid\(\)', '(SELECT auth.uid())', 'g') end
$f$;

create table if not exists public.zz_backup_regras_2026_11_13 (
  tabela text, nome text, qual text, with_check text, primary key (tabela, nome)
);
alter table public.zz_backup_regras_2026_11_13 enable row level security;
revoke all on public.zz_backup_regras_2026_11_13 from anon, authenticated, public;

insert into public.zz_backup_regras_2026_11_13 (tabela, nome, qual, with_check)
select tablename, policyname, qual, with_check from pg_policies
 where schemaname = 'public'
   and (coalesce(pg_temp.embrulha(qual), '') <> coalesce(qual, '') or coalesce(pg_temp.embrulha(with_check), '') <> coalesce(with_check, ''))
on conflict (tabela, nome) do nothing;

do $regras$
declare r record; v_sql text;
begin
  for r in select tablename, policyname, qual, with_check from pg_policies where schemaname = 'public' loop
    if coalesce(pg_temp.embrulha(r.qual), '') = coalesce(r.qual, '')
       and coalesce(pg_temp.embrulha(r.with_check), '') = coalesce(r.with_check, '') then
      continue;
    end if;
    v_sql := format('alter policy %I on public.%I', r.policyname, r.tablename);
    if r.qual is not null then v_sql := v_sql || format(' using (%s)', pg_temp.embrulha(r.qual)); end if;
    if r.with_check is not null then v_sql := v_sql || format(' with check (%s)', pg_temp.embrulha(r.with_check)); end if;
    execute v_sql;
  end loop;
end $regras$;

drop policy if exists exige_segundo_fator on public.zz_backup_regras_2026_11_13;
create policy exige_segundo_fator on public.zz_backup_regras_2026_11_13 as restrictive for all to authenticated
  using ((select public.segundo_fator_ok())) with check ((select public.segundo_fator_ok()));

-- Conferencia
select item, valor, situacao from (
  select 1 o, 'regras com chamada solta (linha a linha)' item, count(*)::text valor,
         case when count(*) = 0 then 'OK' else 'SOBROU' end situacao
    from pg_policies where schemaname = 'public'
     and (coalesce(pg_temp.embrulha(qual), '') <> coalesce(qual, '') or coalesce(pg_temp.embrulha(with_check), '') <> coalesce(with_check, ''))
  union all
  select 2, 'regras guardadas na copia', count(*)::text, 'OK' from public.zz_backup_regras_2026_11_13
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar):
-- do $d$ declare r record; v text; begin
--   for r in select b.*, p.cmd from public.zz_backup_regras_2026_11_13 b
--            join pg_policies p on p.schemaname = 'public' and p.tablename = b.tabela and p.policyname = b.nome loop
--     v := format('alter policy %I on public.%I', r.nome, r.tabela);
--     if r.qual is not null then v := v || format(' using (%s)', r.qual); end if;
--     if r.with_check is not null then v := v || format(' with check (%s)', r.with_check); end if;
--     execute v;
--   end loop; end $d$;
-- ============================================================
