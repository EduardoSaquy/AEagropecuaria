-- ============================================================
-- DIAGNOSTICO (SO LEITURA): por que o rateio nao fecha o valor do lancamento
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela (item / valor / situacao).
--
-- CONTEXTO
-- A view lancamentos_rateados entrega, para um lancamento com rateio, so as
-- PARTES (lancamento_rateios). Se as partes somam menos que o lancamento, a
-- diferenca some de Relatorios, Geral e Operacional (em 14/10/2026: de maio
-- de 2026 em diante faltavam R$ 38 mil a R$ 170 mil por mes, R$ 645 mil no
-- ano). O script de importacao do ERP sempre fecha o rateio em 100%; entao
-- algo mudou DEPOIS. Esta consulta separa as causas possiveis:
--   A) o valor do lancamento foi editado no app e o rateio ficou com o valor
--      antigo (olha log_alteracoes);
--   B) a atividade do lancamento mudou e o rateio velho continua mandando;
--   C) partes foram apagadas ou nunca entraram inteiras (percentual < 100%).
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

with partes as (
  select lancamento_id,
         sum(valor)           as soma,
         sum(percentual)      as pct,
         count(*)             as n,
         min(origem)          as origem,
         min(created_at)::date as criado_em
    from lancamento_rateios
   group by lancamento_id
),
dif as (
  select l.id, l.mes, l.tipo, l.atividade, l.valor, l.criado_por,
         (l.erp_id is not null) as do_erp,
         p.soma, p.pct, p.n, p.origem, p.criado_em,
         l.valor - p.soma as falta
    from lancamentos_financeiros l
    join partes p on p.lancamento_id = l.id
   where abs(l.valor - p.soma) > 0.05
),
edit_valor as (
  select distinct g.registro_id
    from log_alteracoes g
   where g.tabela = 'lancamentos_financeiros' and g.operacao = 'UPDATE'
     and (g.antes ->> 'valor') is distinct from (g.depois ->> 'valor')
),
edit_ativ as (
  select distinct g.registro_id
    from log_alteracoes g
   where g.tabela = 'lancamentos_financeiros' and g.operacao = 'UPDATE'
     and (g.antes ->> 'atividade') is distinct from (g.depois ->> 'atividade')
),
saida as (
  select 10 as ord, 'Lancamentos com rateio (todos)' as item,
         (select count(*) from partes)::text as valor,
         '' as situacao
  union all
  select 20, 'Lancamentos cujas partes NAO somam o valor',
         count(*)::text,
         case when count(*) = 0 then 'OK' else 'PROBLEMA' end
    from dif
  union all
  select 30, 'R$ que faltam na visao rateada (partes menores que o lancamento)',
         coalesce(round(sum(falta) filter (where falta > 0), 2), 0)::text,
         'tem que ser 0'
    from dif
  union all
  select 31, 'R$ que sobram na visao rateada (partes maiores que o lancamento)',
         coalesce(round(-sum(falta) filter (where falta < 0), 2), 0)::text,
         'tem que ser 0'
    from dif
  union all
  select 40, 'Percentual medio ja rateado, entre os que nao fecham',
         coalesce(round(avg(pct) * 100, 1), 0)::text || '%',
         'minimo ' || coalesce(round(min(pct) * 100, 1), 0)::text
           || '% / maximo ' || coalesce(round(max(pct) * 100, 1), 0)::text || '%'
    from dif
  union all
  select 50, 'Causa A: valor editado depois do rateio (log_alteracoes)',
         count(*) filter (where d.id::text in (select registro_id from edit_valor))::text,
         'de ' || count(*)::text || ' que nao fecham'
    from dif d
  union all
  select 51, 'Causa B: atividade trocada depois do rateio (log_alteracoes)',
         count(*) filter (where d.id::text in (select registro_id from edit_ativ))::text,
         'de ' || count(*)::text || ' que nao fecham'
    from dif d
  union all
  select 52, 'Causa B2: lancamento com atividade diferente de geral e com rateio',
         count(*) filter (where d.atividade <> 'geral')::text,
         'rateio so deveria existir para atividade geral'
    from dif d
  union all
  select 53, 'Causa C: sem edicao no log e atividade geral (partes faltando)',
         count(*) filter (where d.id::text not in (select registro_id from edit_valor)
                            and d.id::text not in (select registro_id from edit_ativ)
                            and d.atividade = 'geral')::text,
         'de ' || count(*)::text || ' que nao fecham'
    from dif d
  union all
  select 60, 'Faltando por mes: ' || coalesce(d.mes, 'sem mes'),
         round(sum(d.falta), 2)::text,
         count(*)::text || ' lancamentos'
    from dif d
   group by d.mes
  union all
  select 70, 'Faltando por tipo: ' || d.tipo,
         round(sum(d.falta), 2)::text,
         count(*)::text || ' lancamentos'
    from dif d
   group by d.tipo
  union all
  select 71, 'Faltando por origem do rateio: ' || coalesce(d.origem, 'sem origem'),
         round(sum(d.falta), 2)::text,
         count(*)::text || ' lancamentos'
    from dif d
   group by d.origem
  union all
  select 72, 'Faltando por atividade do lancamento: ' || coalesce(d.atividade, 'sem'),
         round(sum(d.falta), 2)::text,
         count(*)::text || ' lancamentos'
    from dif d
   group by d.atividade
  union all
  select 73, 'Faltando por quem criou: ' || coalesce(d.criado_por, 'sem'),
         round(sum(d.falta), 2)::text,
         count(*)::text || ' lancamentos'
    from dif d
   group by d.criado_por
  union all
  select 74, 'Rateio gravado em: ' || d.criado_em::text,
         round(sum(d.falta), 2)::text,
         count(*)::text || ' lancamentos'
    from dif d
   group by d.criado_em
  union all
  select 80 + row_number() over (order by d.falta desc),
         'Maior #' || row_number() over (order by d.falta desc)::text
           || ' - lancamento ' || d.id::text || ' (' || coalesce(d.mes, 'sem mes') || ', '
           || d.atividade || ', ' || d.n::text || ' partes)',
         round(d.falta, 2)::text,
         'valor ' || round(d.valor, 2)::text || ' / partes somam ' || round(d.soma, 2)::text
    from (select * from dif order by falta desc limit 10) d
)
select item, valor, situacao
  from saida
 order by ord, item;
