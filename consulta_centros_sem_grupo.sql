-- ============================================================
-- OS CENTROS DE CUSTO QUE FALTAM CLASSIFICAR
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- So leitura.
--
-- O plano de contas do Conag e hierarquico e essa hierarquia esta gravada
-- em centros_custo.tipo (entrada/saida) e .subcategoria ('GRUPO |
-- Subcategoria'). 52 dos 71 centros ja estao classificados; 19 nao.
--
-- Os 19 quase certamente vieram da migracao da Pecuaria: o custos_fixos
-- guardava o centro de custo como texto livre, sem grupo nenhum, entao a
-- migracao criou o centro so com o nome.
--
-- Esta consulta mostra quais sao, quanto dinheiro passa por cada um e em
-- que atividade - o suficiente para voce decidir o grupo de cada. Depois e
-- so editar na tela de Centros de Custo do Matriz, escolhendo o grupo numa
-- lista dos que ja existem (nao da para digitar e criar grupo repetido).
-- ============================================================
select
  c.nome as centro_de_custo,
  count(l.id)                                  as lancamentos,
  coalesce(sum(l.valor), 0)                    as total,
  coalesce(string_agg(distinct l.atividade, ', ' order by l.atividade), '-') as atividades,
  coalesce(string_agg(distinct l.tipo, ', ' order by l.tipo), '-')           as tipos_de_lancamento
from centros_custo c
left join lancamentos_financeiros l on l.centro_custo_id = c.id
where coalesce(trim(c.subcategoria), '') = ''
group by c.id, c.nome
order by coalesce(sum(l.valor), 0) desc, c.nome;
