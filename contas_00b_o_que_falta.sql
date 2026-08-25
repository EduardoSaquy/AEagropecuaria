-- ============================================================
-- O QUE AINDA FALTA SABER
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada. Pode rodar antes ou depois do
-- contas_01_estrutura - o resultado e o mesmo.
--
-- Sao duas perguntas:
--   1. quantas despesas recorrentes existem (e o que a "conta fixa
--      mensal" do Contas a Pagar iria duplicar)
--   2. quem hoje enxerga o financeiro (para eu saber a quem a chave
--      nova 'contas' precisa ser dada)
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - esta consulta e do projeto unificado';
  end if;
end $$;


-- ------------------------------------------------------------
-- 1a. O TAMANHO DO PROBLEMA
--
-- Recorrente e o lancamento sem data E sem mes: vale todo mes ate voce
-- lancar um especifico daquele grupo.
-- ------------------------------------------------------------
select
  count(*)                                          as recorrentes,
  round(coalesce(sum(valor),0), 2)                  as total_por_mes,
  round(coalesce(sum(valor),0) * 12, 2)             as total_no_ano
from lancamentos_financeiros
where data is null and mes is null;


-- ------------------------------------------------------------
-- 1b. QUAIS SAO
--
-- Cada linha destas viraria um titulo com vencimento mensal.
-- ------------------------------------------------------------
select
  l.atividade,
  coalesce(f.nome, 'Geral')                as fazenda,
  c.nome                                   as centro_de_custo,
  l.descricao,
  round(l.valor, 2)                        as valor_mensal,
  coalesce(l.fornecedor, '-')              as fornecedor
from lancamentos_financeiros l
left join fazendas      f on f.id = l.fazenda_id
left join centros_custo c on c.id = l.centro_custo_id
where l.data is null and l.mes is null
order by l.valor desc;


-- ------------------------------------------------------------
-- 2. QUEM ENXERGA O FINANCEIRO HOJE
--
-- As permissoes ficam em profiles (nao em funcionarios - foi o erro da
-- primeira versao desta consulta).
-- ------------------------------------------------------------
select
  nome,
  usuario,
  papel,
  coalesce(permissoes ->> 'matriz_financeiro', 'nenhum')  as financeiro_matriz,
  coalesce(permissoes ->> 'pec_financeiro',    'nenhum')  as financeiro_pecuaria,
  coalesce(permissoes ->> 'cana_financeiro',   'nenhum')  as financeiro_cana,
  coalesce(permissoes ->> 'cereais_financeiro','nenhum')  as financeiro_cereais,
  coalesce(permissoes ->> 'contas',            'nenhum')  as contas_a_pagar,
  ativo
from profiles
order by
  case papel when 'admin' then 1 when 'proprietario' then 2 else 3 end,
  nome;
