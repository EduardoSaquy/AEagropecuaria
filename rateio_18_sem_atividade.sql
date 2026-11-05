-- ============================================================
-- CONFERENCIA (SO LEITURA): quanto dinheiro esta FORA das tres atividades
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- PERGUNTA: o que o Eduardo teme e lancamento sem atividade, que faz a soma de
-- Pecuaria + Cana + Graos ficar menor do que a empresa. Esta consulta mede.
--
-- COMO O APP LE (para entender o resultado):
--   aba Empresa ................. soma o Financeiro inteiro, com ou sem atividade;
--   Pecuaria / Cana / Graos ..... leem a visao lancamentos_rateados e so somam o que
--                                 tem a atividade deles. Lancamento 'geral' SEM partes
--                                 de rateio nao cai em nenhuma das tres;
--   aviso "rateio incompleto" ... NAO pega esse caso (a visao devolve o 'geral' inteiro,
--                                 entao a soma bate com o Financeiro).
--
-- O QUE DEVOLVE
--   1. por safra (maio a abril) e tipo: o total da empresa e quanto foi para cada
--      atividade, e quanto ficou SEM ATIVIDADE (lancamento 'geral' sem partes);
--   2. de onde vem o que ficou sem atividade: por safra, tipo, centro de custo e origem.
-- Lancamento sem data e sem mes (recorrente, vale todo mes) aparece separado: contar o
-- valor uma vez nao e o numero real dele.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

with
v as (
  select r.lancamento_id, r.tipo, r.atividade, r.valor, r.erp_id, r.criado_por,
         coalesce(cc.nome, '(sem centro de custo)') as centro,
         coalesce(r.mes, to_char(coalesce(r.data, r.vencimento), 'YYYY-MM')) as mes_ref
    from lancamentos_rateados r
    left join centros_custo cc on cc.id = r.centro_custo_id
   where r.tipo in ('despesa', 'receita', 'investimento') and r.valor <> 0
),
s as (
  select v.*,
         case when v.mes_ref is null then 'sem mes (recorrente)'
              when substring(v.mes_ref, 6, 2)::int >= 5
                then substring(v.mes_ref, 1, 4) || '/' || (substring(v.mes_ref, 1, 4)::int + 1)::text
              else (substring(v.mes_ref, 1, 4)::int - 1)::text || '/' || substring(v.mes_ref, 1, 4)
         end as safra,
         case when v.erp_id is not null then 'importacao do ERP'
              when v.criado_por like 'ERP (acerto%' then 'acerto de 21/10'
              else 'lancada a mao' end as origem
    from v
),
resumo as (
  select 0 as ord, 0::numeric as sub, safra || ' | ' || tipo as item,
         'Empresa R$ ' || round(sum(valor), 2)::text as valor,
         'Pecuaria R$ ' || round(coalesce(sum(valor) filter (where atividade = 'pecuaria'), 0), 2)::text
           || ' | Cana R$ ' || round(coalesce(sum(valor) filter (where atividade = 'cana'), 0), 2)::text
           || ' | Graos R$ ' || round(coalesce(sum(valor) filter (where atividade = 'graos'), 0), 2)::text
           || ' | SEM ATIVIDADE R$ ' || round(coalesce(sum(valor) filter (where atividade not in ('pecuaria', 'cana', 'graos')), 0), 2)::text
           || ' (' || count(distinct lancamento_id) filter (where atividade not in ('pecuaria', 'cana', 'graos')) || ' lancamentos)' as situacao
    from s
   group by safra, tipo
),
total as (
  select 0, 1::numeric, 'TODAS AS SAFRAS | ' || tipo,
         'Empresa R$ ' || round(sum(valor), 2)::text,
         'SEM ATIVIDADE R$ ' || round(coalesce(sum(valor) filter (where atividade not in ('pecuaria', 'cana', 'graos')), 0), 2)::text
           || ' (' || count(distinct lancamento_id) filter (where atividade not in ('pecuaria', 'cana', 'graos')) || ' lancamentos) = '
           || round(100 * coalesce(sum(valor) filter (where atividade not in ('pecuaria', 'cana', 'graos')), 0)
                    / nullif(sum(valor), 0), 1)::text || '% do total'
    from s
   where safra <> 'sem mes (recorrente)'
   group by tipo
),
origem as (
  select 1, -sum(valor), safra || ' | ' || tipo || ' | ' || centro || ' | ' || origem,
         count(distinct lancamento_id)::text || ' lancamentos',
         'R$ ' || round(sum(valor), 2)::text
    from s
   where atividade not in ('pecuaria', 'cana', 'graos')
   group by safra, tipo, centro, origem
)
select item, valor, situacao
  from (select * from resumo union all select * from total union all select * from origem) z
 order by ord, sub, item;
