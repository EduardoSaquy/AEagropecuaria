-- ============================================================
-- CONFERE AS RECEITAS LINHA A LINHA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Nao altera nada. So compara.
--
-- ------------------------------------------------------------
-- POR QUE
--
-- A conferencia anterior acusou:
--   receitas pecuaria  1953191.39999999999  x  1953191.40
--
-- A diferenca esta na 11a casa decimal. Isso nao e dado errado: e o tipo da
-- coluna. Em receitas o valor e provavelmente double precision (numero de
-- ponto flutuante, que nao representa centavos de forma exata), e em
-- lancamentos_financeiros ele e numeric(12,2), que representa. Somar 15
-- valores em float acumula esse residuo.
--
-- Este script prova isso de duas formas: mostra o tipo das duas colunas e
-- compara receita por receita. Se for so o tipo, a segunda consulta volta
-- VAZIA.
-- ============================================================

-- ------------------------------------------------------------
-- 0) TRAVA DE PROJETO
-- ------------------------------------------------------------
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

-- ------------------------------------------------------------
-- 1) TIPO DAS COLUNAS
--    Se receitas.valor for double precision e lancamentos_financeiros.valor
--    for numeric, a diferenca esta explicada.
-- ------------------------------------------------------------
select table_name, column_name, data_type, numeric_precision, numeric_scale
from information_schema.columns
where table_schema = 'public'
  and column_name = 'valor'
  and table_name in ('receitas', 'lancamentos_financeiros')
order by table_name;


-- ------------------------------------------------------------
-- 2) COMPARACAO RECEITA POR RECEITA
--    Volta vazio = nenhuma receita mudou de valor. Qualquer linha aqui e
--    diferenca de verdade, e nao arredondamento.
-- ------------------------------------------------------------
select
  r.id            as id_receita,
  r.data,
  r.descricao,
  r.valor         as valor_origem,
  l.valor         as valor_novo,
  round(l.valor - r.valor::numeric, 2) as diferenca
from receitas r
join lancamentos_financeiros l
  on l.tipo = 'receita' and l.atividade = 'pecuaria'
 and l.descricao is not distinct from r.descricao
 and l.data      is not distinct from r.data
 and l.abate_id  is not distinct from r.abate_id
where coalesce(r.valor, 0) > 0 and r.data is not null
  and round(l.valor - r.valor::numeric, 2) <> 0
order by r.data;


-- ------------------------------------------------------------
-- 3) TOTAL DAS RECEITAS COM OS DOIS LADOS EM NUMERIC
--    Somando os dois como numeric, tem que dar OK.
-- ------------------------------------------------------------
select
  (select count(*) from receitas where coalesce(valor,0) > 0 and data is not null) as linhas_antes,
  (select count(*) from lancamentos_financeiros where tipo='receita' and atividade='pecuaria') as linhas_agora,
  (select coalesce(sum(round(valor::numeric, 2)), 0) from receitas
     where coalesce(valor,0) > 0 and data is not null) as total_antes,
  (select coalesce(sum(valor), 0) from lancamentos_financeiros
     where tipo='receita' and atividade='pecuaria') as total_agora,
  case when (select coalesce(sum(round(valor::numeric, 2)), 0) from receitas
               where coalesce(valor,0) > 0 and data is not null)
          = (select coalesce(sum(valor), 0) from lancamentos_financeiros
               where tipo='receita' and atividade='pecuaria')
       then 'OK' else '*** DIFERENTE ***' end as confere;
