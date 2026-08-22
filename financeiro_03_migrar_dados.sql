-- ============================================================
-- MIGRAR O FINANCEIRO PARA O MODELO UNICO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- RODE ESTE SCRIPT E SUBA OS HTMLs NA MESMA JANELA DE TEMPO. Entre um e
-- outro, o Matriz e a Pecuaria ficam olhando tabelas diferentes.
--
-- ------------------------------------------------------------
-- O QUE ELE FAZ
--
-- Copia para lancamentos_financeiros tudo que hoje esta espalhado em
-- custos_fixos, receitas, investimentos, despesas_cana e despesas_graos.
--
-- NAO APAGA NADA das tabelas antigas. Elas ficam intactas como conferencia
-- e como caminho de volta. Ficam sem uso depois que os apps subirem.
--
-- ------------------------------------------------------------
-- DECISOES DA MIGRACAO, PARA VOCE CONFERIR DEPOIS
--
-- 1. Centro de custo: hoje a pecuaria guarda isso como texto livre. Cada
--    texto distinto vira um centro de custo global (sem fazenda). O que
--    estiver em branco cai num centro chamado "Nao classificado", para
--    ficar visivel que precisa de atencao em vez de sumir.
--
-- 2. Fazenda: custos_fixos nao tem esse campo. Os lancamentos da pecuaria
--    entram como "Geral" (fazenda nula). Nao da para adivinhar a fazenda, e
--    inventar seria pior. Depois de migrado da para corrigir na tela, e o
--    relatorio mostra quanto ainda esta como Geral.
--
-- 3. Receita nao tem centro de custo na origem. Entra num centro chamado
--    "Vendas". Na tela o campo aparece como "Centro de custo / origem".
--
-- 4. Despesas de cana e graos tem categoria de lista fixa ALEM do centro de
--    custo. Quando o centro existe, ele e usado e a categoria vai para a
--    observacao, para nao se perder. Quando nao existe, a propria categoria
--    vira o centro.
-- ============================================================

do $migrarfin$
declare
  id_nao_classificado bigint;
  id_vendas           bigint;
  n_cf int; n_rec int; n_inv int; n_cana int; n_graos int;
begin
  -- ---------- TRAVAS ----------
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'lancamentos_financeiros') then
    raise exception 'A tabela lancamentos_financeiros nao existe. Rode antes o financeiro_01_modelo_unico.sql.';
  end if;

  if (select count(*) from lancamentos_financeiros) > 0 then
    raise exception 'Ja existe lancamento migrado (% linhas). Rodar de novo duplicaria tudo.',
      (select count(*) from lancamentos_financeiros);
  end if;

  -- ---------- CENTROS DE CUSTO QUE FALTAM ----------
  -- Cada texto livre distinto da pecuaria vira um centro global.
  insert into centros_custo (fazenda_id, nome, frente, ativo)
  select distinct null::bigint, trim(cf.categoria), 'pecuaria', true
  from custos_fixos cf
  where coalesce(trim(cf.categoria), '') <> ''
    and not exists (
      select 1 from centros_custo c
      where c.fazenda_id is null and lower(c.nome) = lower(trim(cf.categoria))
    );

  insert into centros_custo (fazenda_id, nome, frente, ativo)
  select distinct null::bigint, trim(i.categoria), 'pecuaria', true
  from investimentos i
  where coalesce(trim(i.categoria), '') <> ''
    and not exists (
      select 1 from centros_custo c
      where c.fazenda_id is null and lower(c.nome) = lower(trim(i.categoria))
    );

  -- Dois centros de apoio, criados so se ainda nao existirem.
  insert into centros_custo (fazenda_id, nome, frente, ativo)
  select null, 'Nao classificado', 'geral', true
  where not exists (select 1 from centros_custo where fazenda_id is null and nome = 'Nao classificado');

  insert into centros_custo (fazenda_id, nome, frente, ativo)
  select null, 'Vendas', 'geral', true
  where not exists (select 1 from centros_custo where fazenda_id is null and nome = 'Vendas');

  select id into id_nao_classificado from centros_custo where fazenda_id is null and nome = 'Nao classificado';
  select id into id_vendas           from centros_custo where fazenda_id is null and nome = 'Vendas';

  -- ---------- DESPESAS DA PECUARIA ----------
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     fornecedor, observacao, areas)
  select
    'despesa', 'pecuaria', null,
    coalesce(
      (select c.id from centros_custo c
        where c.fazenda_id is null and lower(c.nome) = lower(trim(cf.categoria)) limit 1),
      id_nao_classificado
    ),
    -- o nome da despesa e o que identifica a linha; a descricao detalhada
    -- entra junto quando existe, para nao virar duas colunas com o mesmo papel
    case when coalesce(trim(cf.descricao), '') = '' then cf.nome
         else cf.nome || ' — ' || trim(cf.descricao) end,
    cf.valor_mensal,
    cf.data,
    case when cf.data is not null then to_char(cf.data, 'YYYY-MM') else null end,
    nullif(trim(coalesce(cf.fornecedor, '')), ''),
    nullif(trim(coalesce(cf.observacao, '')), ''),
    coalesce(cf.areas, '{}')
  from custos_fixos cf
  where coalesce(cf.valor_mensal, 0) > 0;
  get diagnostics n_cf = row_count;

  -- ---------- RECEITAS DA PECUARIA ----------
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     observacao, lote_id, arrobas)
  select
    'receita', 'pecuaria', null, id_vendas,
    r.descricao, r.valor, r.data, to_char(r.data, 'YYYY-MM'),
    nullif(trim(coalesce(r.observacao, '')), ''),
    r.lote_id, r.arrobas
  from receitas r
  where coalesce(r.valor, 0) > 0 and r.data is not null;
  get diagnostics n_rec = row_count;

  -- ---------- INVESTIMENTOS DA PECUARIA ----------
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes, fornecedor)
  select
    'investimento', 'pecuaria', null,
    coalesce(
      (select c.id from centros_custo c
        where c.fazenda_id is null and lower(c.nome) = lower(trim(i.categoria)) limit 1),
      id_nao_classificado
    ),
    i.nome, i.valor, i.data, to_char(i.data, 'YYYY-MM'),
    nullif(trim(coalesce(i.fornecedor, '')), '')
  from investimentos i
  where coalesce(i.valor, 0) > 0 and i.data is not null;
  get diagnostics n_inv = row_count;

  -- ---------- DESPESAS DE CANA ----------
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     observacao, talhao_id)
  select
    'despesa', 'cana', d.fazenda_id,
    coalesce(d.centro_custo_id, id_nao_classificado),
    d.descricao, d.valor, d.data, to_char(d.data, 'YYYY-MM'),
    -- a categoria de lista fixa nao existe no modelo novo; preservada aqui
    -- para nao se perder informacao na conversao
    trim(both ' ' from coalesce(d.observacao, '') || ' [categoria: ' || d.categoria || ']'),
    d.talhao_id
  from despesas_cana d
  where coalesce(d.valor, 0) > 0;
  get diagnostics n_cana = row_count;

  -- ---------- DESPESAS DE GRAOS ----------
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     observacao, talhao_id)
  select
    'despesa', 'graos', d.fazenda_id,
    coalesce(d.centro_custo_id, id_nao_classificado),
    d.descricao, d.valor, d.data, to_char(d.data, 'YYYY-MM'),
    trim(both ' ' from coalesce(d.observacao, '') || ' [categoria: ' || d.categoria || ']'),
    d.talhao_id
  from despesas_graos d
  where coalesce(d.valor, 0) > 0;
  get diagnostics n_graos = row_count;

  raise notice 'despesas pecuaria: % | receitas: % | investimentos: % | cana: % | graos: %',
    n_cf, n_rec, n_inv, n_cana, n_graos;
end
$migrarfin$;


-- ============================================================
-- CONFERENCIA
--
-- A coluna confere tem que dar OK em todas as linhas: significa que a
-- soma em reais bate entre a tabela antiga e a nova.
-- ============================================================
select 'despesas pecuaria' as origem,
       (select count(*) from custos_fixos where coalesce(valor_mensal,0) > 0) as linhas_origem,
       (select count(*) from lancamentos_financeiros where tipo='despesa' and atividade='pecuaria') as linhas_novo,
       (select coalesce(sum(valor_mensal),0) from custos_fixos where coalesce(valor_mensal,0) > 0) as total_origem,
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='pecuaria') as total_novo
union all
select 'receitas pecuaria',
       (select count(*) from receitas where coalesce(valor,0) > 0 and data is not null),
       (select count(*) from lancamentos_financeiros where tipo='receita' and atividade='pecuaria'),
       (select coalesce(sum(valor),0) from receitas where coalesce(valor,0) > 0 and data is not null),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='pecuaria')
union all
select 'investimentos',
       (select count(*) from investimentos where coalesce(valor,0) > 0 and data is not null),
       (select count(*) from lancamentos_financeiros where tipo='investimento'),
       (select coalesce(sum(valor),0) from investimentos where coalesce(valor,0) > 0 and data is not null),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='investimento')
union all
select 'despesas cana',
       (select count(*) from despesas_cana where coalesce(valor,0) > 0),
       (select count(*) from lancamentos_financeiros where tipo='despesa' and atividade='cana'),
       (select coalesce(sum(valor),0) from despesas_cana where coalesce(valor,0) > 0),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='cana')
union all
select 'despesas graos',
       (select count(*) from despesas_graos where coalesce(valor,0) > 0),
       (select count(*) from lancamentos_financeiros where tipo='despesa' and atividade='graos'),
       (select coalesce(sum(valor),0) from despesas_graos where coalesce(valor,0) > 0),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='despesa' and atividade='graos');
