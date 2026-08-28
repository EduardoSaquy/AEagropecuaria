-- ============================================================
-- ALARGA A VIEW lancamentos_rateados
--
-- So precisa colar isto se voce ja rodou as partes 1 a 4 da importacao do
-- Conag (a view ja existe no banco, so com menos colunas).
--
-- POR QUE:
--
-- A tela de Resultados (AE Matriz) e o Financeiro so-leitura da Pecuaria
-- (AEpecuaria.html) nunca liam da view lancamentos_rateados - liam direto
-- de lancamentos_financeiros, filtrando por atividade. Isso significava
-- que um lancamento "geral" (os titulos do Conag sem atividade propria,
-- rateados entre fazenda/atividade) tinha sua fatia invisivel pra essas
-- telas: a despesa da Cana, por exemplo, aparecia menor do que deveria,
-- porque faltava a parte que o rateio mandou pra ela.
--
-- A correcao (no proprio codigo do app) e trocar essas leituras pra ler da
-- view em vez da tabela. Mas a view, do jeito que foi criada, so tinha as
-- colunas que a conferencia do Conag precisava (tipo, atividade, valor,
-- centro_custo_id, descricao, fornecedor, data, mes, conag_id, contrato) -
-- faltava abate_id (pra saber qual venda gerou aquela receita), areas,
-- observacao, talhao_id, lote_id, arrobas, criado_por, quantidade,
-- unidade, safra_id, cnpj_nota, vencimento. Sem essas colunas, trocar a
-- fonte de leitura ia fazer a Pecuaria perder o vinculo de receita->venda.
--
-- Este arquivo so re-cria a view com essas colunas a mais (nada e
-- apagado, nenhuma coluna muda de nome ou de posicao - so entram colunas
-- novas no fim). E seguro rodar em cima do que ja existe.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.views
                 where table_schema='public' and table_name='lancamentos_rateados') then
    raise exception 'lancamentos_rateados nao existe ainda - rode o conag_dashboard_2 primeiro';
  end if;
end $$;

create or replace view lancamentos_rateados as
select l.id as lancamento_id, r.id as rateio_id, l.tipo,
       r.atividade, r.fazenda_id, r.cultura_id, r.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, true as rateado,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento
  from lancamentos_financeiros l
  join lancamento_rateios r on r.lancamento_id = l.id
union all
select l.id, null, l.tipo,
       l.atividade, l.fazenda_id, l.cultura_id, l.valor,
       l.centro_custo_id, l.descricao, l.fornecedor, l.data, l.mes,
       l.conag_id, l.contrato, false,
       l.observacao, l.talhao_id, l.lote_id, l.areas, l.arrobas, l.abate_id,
       l.criado_por, l.quantidade, l.unidade, l.safra_id, l.cnpj_nota, l.vencimento
  from lancamentos_financeiros l
 where not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);

comment on view lancamentos_rateados is
  'O financeiro ja rateado. Onde ha rateio, entrega as partes; onde nao ha, '
  'entrega o lancamento inteiro. E daqui que os Resultados devem ler.';

select 'View lancamentos_rateados alargada. Agora atualize o app (AEMatriz.html e AEpecuaria.html ja saem daqui do repo com a correcao).' as proximo_passo;
