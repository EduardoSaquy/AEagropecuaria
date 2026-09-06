-- ============================================================
-- SO LEITURA - o Eduardo confirmou que lembra de ter cadastrado um
-- financiamento, mas a conferencia anterior mostrou a tabela
-- financiamentos vazia. Este arquivo procura o rastro dele no
-- log_alteracoes (gatilho que registra INSERT/UPDATE/DELETE em
-- financiamentos) pra descobrir se ele foi gravado e depois sumiu
-- (haveria um DELETE) ou se nunca chegou a ser gravado (nao apareceria
-- nem o INSERT). Nao muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, item, valor, situacao from (
  select 'gatilho de log em financiamentos esta ligado' as item,
         case when exists (
           select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
            where c.relname = 'financiamentos' and t.tgname = 'trg_registrar_alteracao' and t.tgenabled = 'O'
         ) then 'sim' else 'NAO - esse e o motivo do sumico, nada fica registrado' end as valor,
         'esperado: sim' as situacao
) x

union all
select 2::numeric, item, valor, situacao from (
  select 'toda alteracao registrada em financiamentos' as item,
         quando::text || ' - ' || operacao || ' (registro ' || registro_id || ') por ' || coalesce(quem_nome,'?') as valor,
         coalesce(depois->>'banco', antes->>'banco', '?') as situacao
    from log_alteracoes
   where tabela = 'financiamentos'
   order by quando
) x

union all
select 3::numeric, item, valor, situacao from (
  select 'resumo geral do log_alteracoes (todas as tabelas)' as item,
         count(*)::text || ' linha(s) no total' as valor,
         'do mais antigo (' || min(quando)::text || ') ao mais recente (' || max(quando)::text || ')' as situacao
    from log_alteracoes
) x

order by 1;
