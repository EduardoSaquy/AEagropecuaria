-- ============================================================
-- SO LEITURA - antes de integrar o Combustivel no projeto unificado,
-- confere as policies de SELECT nas tabelas que vamos reaproveitar
-- (fazendas, talhoes_areas, centros_custo, culturas, safras,
-- funcionarios, funcionario_atividades, fazenda_atividades) - preciso
-- saber que modulo de permissao cada uma exige, pra saber se um
-- usuario so-de-combustivel (sem permissao de Matriz) consegue ler.
-- Nao muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, tablename || ' - ' || policyname as item,
       'comando=' || cmd as valor,
       coalesce('using: ' || qual, '(sem using)') as situacao
  from pg_policies
 where schemaname='public'
   and tablename in ('fazendas','talhoes_areas','centros_custo','culturas','safras',
                      'funcionarios','funcionario_atividades','fazenda_atividades')
   and cmd = 'SELECT'
 order by tablename;
