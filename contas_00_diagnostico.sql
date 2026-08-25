-- ============================================================
-- ANTES DE CRIAR CONTAS A PAGAR / A RECEBER
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada.
--
-- Preciso saber tres coisas para decidir a estrutura:
--   1. quantas despesas recorrentes existem hoje
--   2. como estao as permissoes de financeiro
--   3. se ja existe alguma tabela parecida no banco
-- ============================================================

-- guarda de projeto
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - esta consulta e do projeto unificado';
  end if;
end $$;


-- ------------------------------------------------------------
-- 1. RECORRENTES: o que a conta fixa mensal iria duplicar
-- ------------------------------------------------------------
select
  'recorrentes hoje' as item,
  count(*)           as quantidade,
  round(sum(valor), 2) as total_por_mes
from lancamentos_financeiros
where data is null and mes is null;

-- detalhe de cada um
select
  atividade,
  coalesce((select nome from fazendas f where f.id = l.fazenda_id), 'Geral') as fazenda,
  (select nome from centros_custo c where c.id = l.centro_custo_id) as centro,
  descricao,
  round(valor, 2) as valor_mensal
from lancamentos_financeiros l
where data is null and mes is null
order by valor desc;


-- ------------------------------------------------------------
-- 2. PERMISSOES: quem hoje enxerga o financeiro
-- ------------------------------------------------------------
select
  nome,
  usuario,
  papel,
  permissoes ->> 'matriz_financeiro' as financeiro_matriz,
  permissoes ->> 'pec_financeiro'    as financeiro_pecuaria,
  permissoes ->> 'cana_financeiro'   as financeiro_cana,
  permissoes ->> 'cereais_financeiro' as financeiro_cereais
from funcionarios
order by papel, nome;


-- ------------------------------------------------------------
-- 3. O banco ja tem alguma coisa de titulo / vencimento?
-- ------------------------------------------------------------
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (table_name  ilike '%conta%'
    or table_name  ilike '%titulo%'
    or table_name  ilike '%pagar%'
    or table_name  ilike '%receber%'
    or column_name ilike '%vencimento%'
    or column_name ilike '%parcela%')
order by table_name, ordinal_position;


-- ------------------------------------------------------------
-- 4. FORNECEDORES: quanto ja existe de nome digitado solto
-- ------------------------------------------------------------
select
  count(*) filter (where fornecedor is not null and btrim(fornecedor) <> '') as lancamentos_com_fornecedor,
  count(distinct lower(btrim(fornecedor))) filter (where fornecedor is not null and btrim(fornecedor) <> '') as nomes_diferentes
from lancamentos_financeiros;
