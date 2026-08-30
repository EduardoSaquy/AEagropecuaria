-- ============================================================
-- SÓ LEITURA — antes de trocar "Operadores" (cadastro próprio do
-- Combustível) por "Funcionários" (reaproveitado do Matriz), preciso
-- saber duas coisas: (1) se funcionarios já é legível por quem só tem
-- permissão de combustível — o `combustivel_confere_policies_reuso.sql`
-- rodado antes de integrar o Combustível mostrou funcionarios SEM
-- nenhuma policy de SELECT, ao contrário de fazendas/talhoes_areas/
-- centros_custo/culturas/safras (por isso elas entraram no
-- combustivel_unificado_02 e funcionarios ficou de fora) — esta consulta
-- confirma se isso ainda é verdade; (2) se já existe abastecimento ou
-- operador cadastrado que a migração da FK precisa levar em conta (se
-- tiver, a migração NÃO pode simplesmente trocar a referência da coluna
-- sem religar os dados). Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'RLS ligado em funcionarios' as item,
       case when c.relrowsecurity then 'sim' else 'não' end as valor,
       'informativo' as situacao
  from pg_class c
 where c.relname = 'funcionarios' and c.relnamespace = 'public'::regnamespace
union all
select 2, 'policies de SELECT em funcionarios (esperado pelo diagnóstico anterior: 0)',
       coalesce(string_agg(policyname || ' [' || qual || ']', ' | '), '(nenhuma)'),
       'informativo'
  from pg_policies where schemaname='public' and tablename='funcionarios' and cmd='SELECT'
union all
select 3, 'operadores cadastrados hoje', count(*)::text,
       case when count(*)=0 then 'OK - nada pra religar' else 'ATENÇÃO - precisa decidir o que fazer com esses registros' end
  from operadores
union all
select 4, 'abastecimentos já lançados hoje', count(*)::text,
       case when count(*)=0 then 'OK - troca de FK é segura' else 'PARE - existe abastecimento(s) com operador_id apontando pra operadores; a migração não pode trocar a FK sem religar essas linhas primeiro' end
  from abastecimentos
order by 1;
