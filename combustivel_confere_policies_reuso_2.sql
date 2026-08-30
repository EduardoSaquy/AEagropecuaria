-- ============================================================
-- SO LEITURA - parte 2: por que funcionarios/funcionario_atividades/
-- fazenda_atividades nao apareceram no resultado da parte 1?
-- Confere se o RLS esta ligado e lista TODAS as policies (nao so
-- SELECT) dessas 3 tabelas. Nao muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'RLS: ' || c.relname as item,
       case when c.relrowsecurity then 'LIGADO' else 'DESLIGADO - PARE E ME AVISE' end as valor,
       'esperado: LIGADO' as situacao
  from pg_class c
 where c.relname in ('funcionarios','funcionario_atividades','fazenda_atividades')
   and c.relnamespace = 'public'::regnamespace
union all
select 2, tablename || ' - ' || policyname, 'comando=' || cmd,
       coalesce('using: ' || qual, '(sem using)')
  from pg_policies
 where schemaname='public'
   and tablename in ('funcionarios','funcionario_atividades','fazenda_atividades')
 order by ordem;
