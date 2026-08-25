-- ============================================================
-- CONFERENCIA EM UMA CONSULTA SO
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada.
--
-- O editor do Supabase mostra o resultado de UMA consulta por vez. Por
-- isso aqui e tudo uma consulta unica: um resultado, todas as respostas.
-- ============================================================

with financeiro as (
  select count(*) as n, round(coalesce(sum(valor),0),2) as total,
         count(*) filter (where titulo_baixa_id is not null) as de_titulo
  from lancamentos_financeiros
)
select 1 as ordem,
       'Lancamentos no financeiro' as item,
       n::text                     as valor,
       case when n = 2759 then 'OK' else '*** MUDOU - era 2759 ***' end as situacao
from financeiro
union all
select 2, 'Total do financeiro',
       total::text,
       case when total = 10226028.01 then 'OK' else '*** MUDOU - era 10226028.01 ***' end
from financeiro
union all
select 3, 'Lancamentos vindos de titulo', de_titulo::text,
       case when de_titulo = 0 then 'OK - nenhuma baixa ainda' else 'ja existem baixas' end
from financeiro
union all
select 4, 'Despesas recorrentes', count(*)::text,
       case when count(*) = 0 then 'OK - nenhuma, como esperado'
            else 'existem recorrentes - me avise' end
from lancamentos_financeiros where data is null and mes is null
union all
select 5, 'Entidades (fornecedores)', count(*)::text, 'semeadas dos lancamentos' from entidades
union all
select 6, 'Contas bancarias', count(*)::text, 'a cadastrar' from contas_bancarias
union all
select 7, 'Titulos', count(*)::text,
       case when count(*) = 0 then 'vazio, como esperado' else 'ja tem lancado' end from titulos
union all
select 8, 'Rateios', count(*)::text,
       case when count(*) = 0 then 'vazio, como esperado' else 'ja tem lancado' end from titulo_rateios
union all
select 9, 'Baixas', count(*)::text,
       case when count(*) = 0 then 'vazio, como esperado' else 'ja tem lancado' end from titulo_baixas
union all
select 10, 'Tabelas novas com RLS ligada',
       count(*)::text,
       case when count(*) = 5 then 'OK - as cinco'
            else '*** FALTA RLS EM ALGUMA ***' end
from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
where ns.nspname='public' and c.relrowsecurity
  and c.relname in ('entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas')
union all
select 11, 'Exclusao restrita a admin/proprietario',
       count(*)::text,
       case when count(*) = 5 then 'OK - nas cinco'
            else '*** EXCLUSAO ABERTA EM ALGUMA ***' end
from pg_policies
where schemaname='public' and cmd='DELETE' and qual like '%pode_excluir%'
  and tablename in ('entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas')
union all
select 12, 'is_dono() existe', count(*)::text,
       case when count(*) = 1 then 'OK - proprietario reconhecido'
            else '*** FALTOU criar is_dono ***' end
from pg_proc where proname = 'is_dono'
order by ordem;
