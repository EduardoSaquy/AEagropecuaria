-- ============================================================
-- CONFERE O FINANCEIRO E MEDE OS RECORRENTES
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
end $$;


-- ------------------------------------------------------------
-- 1. O FINANCEIRO NAO PODE TER MUDADO
--
-- Tem que continuar 2759 lancamentos e 10226028.01 de total, com
-- vindos_de_titulo = 0 (nenhuma baixa foi dada ainda).
-- Qualquer outra coisa e problema.
-- ------------------------------------------------------------
select
  count(*)                                                   as lancamentos,
  round(sum(valor), 2)                                       as total,
  count(*) filter (where titulo_baixa_id is not null)        as vindos_de_titulo,
  case when count(*) = 2759 and round(sum(valor),2) = 10226028.01
       then 'OK - intacto'
       else '*** MUDOU - ME AVISE ANTES DE CONTINUAR ***' end as conferencia
from lancamentos_financeiros;


-- ------------------------------------------------------------
-- 2. AS CINCO TABELAS NOVAS
-- ------------------------------------------------------------
select 'entidades' as tabela, count(*) as linhas from entidades
union all select 'contas_bancarias', count(*) from contas_bancarias
union all select 'titulos',          count(*) from titulos
union all select 'titulo_rateios',   count(*) from titulo_rateios
union all select 'titulo_baixas',    count(*) from titulo_baixas
order by 1;


-- ------------------------------------------------------------
-- 3. QUANTOS RECORRENTES EXISTEM
--
-- E o numero que decide como sera a migracao. Recorrente e o lancamento
-- sem data E sem mes: vale todo mes ate voce lancar um especifico.
-- ------------------------------------------------------------
select
  count(*)                              as recorrentes,
  round(coalesce(sum(valor),0), 2)      as total_por_mes,
  round(coalesce(sum(valor),0) * 12, 2) as total_no_ano
from lancamentos_financeiros
where data is null and mes is null;


-- ------------------------------------------------------------
-- 4. QUAIS SAO
--
-- Cada uma destas viraria um titulo com vencimento mensal.
-- ------------------------------------------------------------
select
  l.atividade,
  coalesce(f.nome, 'Geral')   as fazenda,
  c.nome                      as centro_de_custo,
  l.descricao,
  round(l.valor, 2)           as valor_mensal,
  coalesce(l.fornecedor, '-') as fornecedor
from lancamentos_financeiros l
left join fazendas      f on f.id = l.fazenda_id
left join centros_custo c on c.id = l.centro_custo_id
where l.data is null and l.mes is null
order by l.valor desc;
