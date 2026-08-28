-- ============================================================
-- QUAL LANCAMENTO ENTROU
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada.
--
-- A conferencia acusou 2760 lancamentos (era 2759) e um total maior em
-- 221.784,28. O script de estrutura nao escreve em lancamentos - so em
-- entidades - entao isto veio de uso normal do app.
--
-- Esta consulta mostra os 10 lancamentos mais recentes para voce
-- reconhecer o novo. Uma consulta so.
-- ============================================================

select
  l.id,
  to_char(l.created_at, 'DD/MM/YYYY HH24:MI')       as criado_em,
  coalesce(l.criado_por, '-')                       as criado_por,
  l.tipo,
  l.atividade,
  coalesce(f.nome, 'Geral')                         as fazenda,
  coalesce(c.nome, '-')                             as centro_de_custo,
  l.descricao,
  l.valor,
  coalesce(to_char(l.data, 'DD/MM/YYYY'), '-')      as data,
  coalesce(l.mes, '-')                              as competencia,
  coalesce(l.fornecedor, '-')                       as fornecedor,
  case when l.valor = 221784.28 then '<<< ESTE E O QUE ENTROU' else '' end as marca
from lancamentos_financeiros l
left join fazendas      f on f.id = l.fazenda_id
left join centros_custo c on c.id = l.centro_custo_id
order by l.created_at desc nulls last, l.id desc
limit 10;
