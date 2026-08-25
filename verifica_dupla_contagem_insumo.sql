-- ============================================================
-- QUANTO O RESULTADO ESTA CONTANDO DUAS VEZES
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada.
--
-- ------------------------------------------------------------
-- O QUE ISTO INVESTIGA
--
-- Voce confirmou: adubo comprado entra como DESPESA, e o lancamento no
-- talhao serve so para saber quanto foi gasto naquele talhao.
--
-- Mas a tela de Resultados soma as DUAS coisas:
--
--   despesa do mes = custo do insumo aplicado + despesa lancada
--
-- Se a compra do insumo ja e uma despesa lancada, o mesmo dinheiro esta
-- entrando duas vezes, e o Resultado da cana e dos cereais aparece com
-- custo MAIOR do que o real - e lucro menor.
--
-- Esta consulta mede o tamanho disso, mes a mes.
--
-- COMO LER
--
--   custo_insumo_aplicado  o que a tela soma HOJE alem da despesa lancada
--   despesa_lancada        o que veio de lancamentos_financeiros
--   mostrado_hoje          a soma dos dois, que e o que voce ve na tela
--   correto                so a despesa lancada
--   diferenca              quanto o custo vai CAIR quando eu corrigir
-- ============================================================

with preco_medio as (
  -- preco medio ponderado de cada insumo, pelas entradas que tem preco
  select 'cana' as frente, e.insumo_id,
         sum(e.quantidade * e.preco_pago) / nullif(sum(e.quantidade), 0) as preco
  from entradas_insumo_cana e
  where e.preco_pago is not null and e.quantidade > 0
  group by e.insumo_id
  union all
  select 'graos', e.insumo_id,
         sum(e.quantidade * e.preco_pago) / nullif(sum(e.quantidade), 0)
  from entradas_insumo_graos e
  where e.preco_pago is not null and e.quantidade > 0
  group by e.insumo_id
),
insumo_por_mes as (
  select 'cana' as atividade, to_char(a.data, 'YYYY-MM') as mes,
         sum(a.quantidade * coalesce(p.preco, 0)) as custo
  from aplicacoes_cana a
  left join preco_medio p on p.frente = 'cana' and p.insumo_id = a.insumo_id
  where a.data is not null
  group by 2
  union all
  select 'graos', to_char(a.data, 'YYYY-MM'),
         sum(a.quantidade * coalesce(p.preco, 0))
  from aplicacoes_graos a
  left join preco_medio p on p.frente = 'graos' and p.insumo_id = a.insumo_id
  where a.data is not null
  group by 2
),
despesa_por_mes as (
  select atividade, mes, sum(valor) as valor
  from lancamentos_financeiros
  where tipo = 'despesa' and atividade in ('cana','graos') and mes is not null
  group by 1, 2
)
select
  coalesce(i.atividade, d.atividade)                  as atividade,
  coalesce(i.mes, d.mes)                              as mes,
  round(coalesce(i.custo, 0), 2)                      as custo_insumo_aplicado,
  round(coalesce(d.valor, 0), 2)                      as despesa_lancada,
  round(coalesce(i.custo,0) + coalesce(d.valor,0), 2) as mostrado_hoje,
  round(coalesce(d.valor, 0), 2)                      as correto,
  round(coalesce(i.custo, 0), 2)                      as diferenca
from insumo_por_mes i
full join despesa_por_mes d on d.atividade = i.atividade and d.mes = i.mes
where coalesce(i.custo, 0) > 0
order by 1, 2 desc;


-- ============================================================
-- O TOTAL, PARA DIMENSIONAR
--
-- insumo_contado_em_dobro e quanto sai do custo quando eu corrigir.
-- ============================================================
with preco_medio as (
  select 'cana' as frente, e.insumo_id,
         sum(e.quantidade * e.preco_pago) / nullif(sum(e.quantidade), 0) as preco
  from entradas_insumo_cana e
  where e.preco_pago is not null and e.quantidade > 0 group by e.insumo_id
  union all
  select 'graos', e.insumo_id,
         sum(e.quantidade * e.preco_pago) / nullif(sum(e.quantidade), 0)
  from entradas_insumo_graos e
  where e.preco_pago is not null and e.quantidade > 0 group by e.insumo_id
)
select
  'cana' as atividade,
  round((select coalesce(sum(a.quantidade * coalesce(p.preco, 0)), 0)
         from aplicacoes_cana a
         left join preco_medio p on p.frente = 'cana' and p.insumo_id = a.insumo_id), 2)
    as insumo_contado_em_dobro,
  round((select coalesce(sum(valor), 0) from lancamentos_financeiros
         where tipo = 'despesa' and atividade = 'cana'), 2) as despesa_lancada_total
union all
select
  'graos',
  round((select coalesce(sum(a.quantidade * coalesce(p.preco, 0)), 0)
         from aplicacoes_graos a
         left join preco_medio p on p.frente = 'graos' and p.insumo_id = a.insumo_id), 2),
  round((select coalesce(sum(valor), 0) from lancamentos_financeiros
         where tipo = 'despesa' and atividade = 'graos'), 2);
