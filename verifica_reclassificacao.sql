-- ============================================================
-- A RECLASSIFICACAO CHEGOU A APLICAR?
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ. So leitura.
--
-- O centros_01 quebrou na ULTIMA consulta. O editor do Supabase manda o
-- arquivo inteiro numa requisicao so, e o Postgres trata isso como uma
-- transacao unica: se qualquer comando falha, TUDO volta atras.
--
-- Entao o mais provavel e que nada tenha sido aplicado. Mas "provavel" nao
-- serve - esta consulta responde com certeza.
--
-- COMO LER:
--   classificados = 0  ->  nao aplicou. Rode o centros_01 corrigido.
--   classificados = 12 ->  aplicou. Nao rode de novo (nao faria mal, mas
--                          nao ha o que fazer).
--   entre 1 e 11       ->  aplicou pela metade. Me mande o resultado.
-- ============================================================
select
  count(*) filter (
    where coalesce(trim(subcategoria),'') <> ''
      and lower(btrim(nome)) in (
        'vendas','insumos agrícolas','mão de obra operacional','combustíveis',
        'energia elétrica','terceirização de serviços agropecuários',
        'manutenção de infraestrutura','manutenção de máquinas e frota',
        'casa-sede','instalações - administração','veículos - administração',
        'serviços profissionais (segurança/cartório/contabilidade)')
  ) as classificados,
  count(*) filter (where coalesce(trim(subcategoria),'') = '') as ainda_sem_grupo,
  count(*) filter (where lower(btrim(nome)) = 'nao classificado') as centro_nao_classificado_ainda_existe,
  count(*) as total_de_centros
from centros_custo;
