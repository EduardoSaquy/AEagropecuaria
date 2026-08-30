-- ============================================================
-- SÓ LEITURA — confere as policies de DELETE de lancamentos_
-- financeiros, partos e desmamas, antes de restringir exclusão
-- a admin/proprietário (hoje parece aceitar qualquer editar).
-- Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, tablename || ' - ' || policyname as item,
       'DELETE' as valor, coalesce(qual,'(sem using)') as situacao
  from pg_policies
 where schemaname='public' and cmd='DELETE'
   and tablename in ('lancamentos_financeiros','partos','desmamas')
union all
select 2, 'is_dono() existe?', case when count(*)=1 then 'sim' else 'NAO - PARE E ME AVISE' end,
       'esperado: sim'
  from pg_proc where proname='is_dono'
order by 1;
