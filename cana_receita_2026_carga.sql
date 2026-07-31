-- ============================================================
-- AE Cana — carga de receita a partir do relatório "ERP Conag -
-- Painel de Resultado - DRE / Contas a Receber - Ano 2026".
--
-- 5 lançamentos, todos da USINA SANTO ANTONIO (cliente único no
-- relatório), venda física de cana. Total: R$ 2.587.195,27 (bate
-- exato com o total do relatório original).
--
-- A data usada é a Data de Pagamento (único campo de data que o
-- relatório traz). O relatório não informa toneladas nem talhão/safra
-- específicos, então esses campos ficam em branco — o texto original
-- de cada lançamento (cliente, conta, nota entre parênteses, nº do
-- documento) fica preservado na observação.
--
-- IMPORTANTE — confira antes de rodar: o subquery de fazenda_id
-- aponta pra Faz. Palhadão (mesma usada nas despesas). Ajuste o nome
-- abaixo se não for essa a fazenda certa.
-- ============================================================

with fz as (
  select id from fazendas where nome = 'Faz. Palhadão' limit 1
)
insert into receitas_cana (fazenda_id, talhao_id, safra_id, data, toneladas, valor_total, observacao)
select fz.id, null, null, v.data::date, null, v.valor, v.observacao
from fz, (values
  ('2026-02-10', 38291.23, 'USINA SANTO ANTONIO — RECEITA COM PRODUÇÃO AGROPECUÁRIA - VENDA FÍSICA (ACERTO RESÍDUO) (doc 169)'),
  ('2026-03-10', 89613.93, 'USINA SANTO ANTONIO — RECEITA COM PRODUÇÃO AGROPECUÁRIA - VENDA FÍSICA (ACERTO DO RESÍDUO) (doc 168)'),
  ('2026-04-30', 16307.35, 'USINA SANTO ANTONIO — RECEITA COM PRODUÇÃO AGROPECUÁRIA - VENDA FÍSICA (ACERTO CANA SAFRA 25/26) (doc 175)'),
  ('2026-05-11', 638266.80, 'USINA SANTO ANTONIO — RECEITA COM PRODUÇÃO AGROPECUÁRIA - VENDA FÍSICA (VENDA DE CANA) (doc 188)'),
  ('2026-07-03', 1804715.96, 'USINA SANTO ANTONIO — RECEITA COM PRODUÇÃO AGROPECUÁRIA - VENDA FÍSICA (doc 209)')
) as v(data, valor, observacao);
