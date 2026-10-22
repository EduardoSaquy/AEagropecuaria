-- ============================================================
-- Pecuaria - quem lanca saida de racao precisa VER as dietas
--
-- A leitura de dietas so era liberada para quem tem a permissao Dietas.
-- Operador de Confinamento/Pasto/Cria sem ela nao via nenhuma dieta e o
-- app dizia "nao ha lote de Cria ativo" (caso do Joilson, 22/10/2026).
-- Agora le quem tem Dietas OU Confinamento/Pasto/Cria. So leitura: criar e
-- mudar dieta continua exigindo Dietas: Editar. Repetivel.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

drop policy if exists "select dietas" on dietas;
create policy "select dietas" on dietas for select using (
  tem_permissao('dietas','visualizar')
  or tem_permissao('confinamento','visualizar')
  or tem_permissao('pasto','visualizar')
  or tem_permissao('cria','visualizar')
);

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, 'regra de leitura das dietas' as item,
       coalesce(max(qual), '-') as valor,
       case when count(*) = 1 and max(qual) like '%cria%' then 'OK' else 'ERRO - confira' end as situacao
  from pg_policies where schemaname = 'public' and tablename = 'dietas' and policyname = 'select dietas'
union all
select 2, 'Joilson passa a ver as dietas',
       coalesce(string_agg(nome, ', '), 'nao achei'),
       case when bool_or(papel = 'admin' or coalesce(permissoes->>'dietas','') in ('visualizar','editar')
                         or coalesce(permissoes->>'cria','') in ('visualizar','editar')
                         or coalesce(permissoes->>'confinamento','') in ('visualizar','editar')
                         or coalesce(permissoes->>'pasto','') in ('visualizar','editar'))
            then 'OK' else 'NAO - falta permissao de Cria em Usuarios' end
  from profiles where nome ilike '%joilson%' or usuario ilike '%joilson%'
order by 1;
