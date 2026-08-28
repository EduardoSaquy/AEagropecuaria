-- ============================================================
-- ALARGA A VIEW lancamentos_rateados COM ano_safra
--
-- SO COLE ISTO DEPOIS de ter rodado o
-- lancamentos_ano_safra_01_adicionar_coluna.sql (cria a coluna
-- lancamentos_financeiros.ano_safra).
--
-- POR QUE: os Resultados (AE Matriz) leem lancamentos_rateados, nao
-- lancamentos_financeiros direto (um lancamento "geral" pode estar
-- rateado, ver CLAUDE.md). Sem alargar a view aqui, o campo Safra que o
-- Eduardo preenche no lancamento nunca aparece pros Resultados - fica
-- gravado na tabela, mas invisivel pra quem le da view.
--
-- Mesma tecnica de sempre: create or replace view preservando a ordem e
-- o nome das colunas que ja existem, so acrescentando ano_safra no fim.
-- Nada e apagado, seguro rodar em cima do que ja existe.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='lancamentos_financeiros'
                   and column_name='ano_safra') then
    raise exception 'ano_safra nao existe ainda - rode o lancamentos_ano_safra_01_adicionar_coluna.sql primeiro';
  end if;
end $$;

create or replace view lancamentos_rateados as
select l.id as lancamento_id, r.id as rateio_id, l.tipo,
       r.atividade, r.fazenda_id, r.cultura_id, r.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, true as rateado,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento,
       l.ano_safra
  from lancamentos_financeiros l
  join lancamento_rateios r on r.lancamento_id = l.id
union all
select l.id, null, l.tipo,
       l.atividade, l.fazenda_id, l.cultura_id, l.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, false,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento,
       l.ano_safra
  from lancamentos_financeiros l
 where not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);

comment on view lancamentos_rateados is
  'O financeiro ja rateado. Onde ha rateio, entrega as partes; onde nao ha, '
  'entrega o lancamento inteiro. E daqui que os Resultados devem ler.';

select 'View lancamentos_rateados com ano_safra. Feche e abra o app de novo (service worker cacheia) e confira a aba Safra do Resultados.' as proximo_passo;
