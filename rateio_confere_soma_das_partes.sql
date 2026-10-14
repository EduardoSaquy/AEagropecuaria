-- ============================================================
-- CONFERENCIA (SO LEITURA): rateio que nao soma o valor do lancamento
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Nao altera nada.
--
-- POR QUE EXISTE
-- A view lancamentos_rateados entrega, para um lancamento rateado, so as
-- PARTES (lancamento_rateios). Se as partes somam menos que o lancamento, a
-- diferenca some de Relatorios, Geral e Operacional -- o lancamento continua
-- inteiro em lancamentos_financeiros, mas ninguem enxerga o resto.
--
-- Achado em 14/10/2026 pela aba Resultados > Empresa: de 2023 a abril/2026 a
-- despesa do Financeiro e da view batem centavo por centavo; de maio/2026 em
-- diante a view tem de R$ 38 mil a R$ 170 mil A MENOS por mes (R$ 645 mil no
-- ano de 2026, R$ 1,33 milhao de custos gerais dos quais so metade chegou as
-- atividades). Esta conferencia mostra quais lancamentos estao assim.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

-- 1) POR MES: quanto falta rateado
select l.mes,
       count(*)                       as lancamentos,
       sum(l.valor)                   as valor_do_lancamento,
       sum(r.soma_partes)             as valor_rateado,
       sum(l.valor - r.soma_partes)   as faltando,
       round(avg(r.soma_percentual), 2) as percentual_medio_rateado
  from lancamentos_financeiros l
  join (select lancamento_id,
               sum(valor)      as soma_partes,
               sum(percentual) as soma_percentual,
               count(*)        as partes
          from lancamento_rateios
         group by lancamento_id) r on r.lancamento_id = l.id
 where abs(l.valor - r.soma_partes) > 0.05
 group by l.mes
 order by l.mes;

-- 2) OS 30 MAIORES: o que esta faltando, lancamento por lancamento
select l.id, l.mes, l.atividade, l.descricao, c.nome as centro_de_custo,
       l.valor, r.soma_partes, l.valor - r.soma_partes as faltando,
       r.soma_percentual, r.partes
  from lancamentos_financeiros l
  join (select lancamento_id,
               sum(valor)      as soma_partes,
               sum(percentual) as soma_percentual,
               count(*)        as partes
          from lancamento_rateios
         group by lancamento_id) r on r.lancamento_id = l.id
  left join centros_custo c on c.id = l.centro_custo_id
 where abs(l.valor - r.soma_partes) > 0.05
 order by (l.valor - r.soma_partes) desc
 limit 30;

-- 3) AS PARTES de um dos maiores (troque o numero pelo id do lancamento acima)
-- select r.* from lancamento_rateios r where r.lancamento_id = 0 order by r.id;

-- 4) TOTAL: despesa do Financeiro x despesa da view, por ano
select left(f.mes, 4) as ano,
       sum(f.valor)   as financeiro,
       (select sum(v.valor) from lancamentos_rateados v
         where v.tipo = 'despesa' and left(v.mes, 4) = left(f.mes, 4)) as visao_rateada
  from lancamentos_financeiros f
 where f.tipo = 'despesa' and f.mes is not null
 group by left(f.mes, 4)
 order by 1;
