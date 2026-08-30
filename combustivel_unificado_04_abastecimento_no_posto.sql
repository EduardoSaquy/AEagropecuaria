-- ===================================================================
-- AE Combustível — abastecimento pode ser feito num posto de gasolina
-- ===================================================================
-- Decisão do Eduardo em 30/08/2026: só existe um tanque por fazenda —
-- então em vez de escolher um tanque, a tela passa a pedir a fazenda
-- (resolve o tanque dela por trás) ou "Posto de gasolina", pra quando
-- o abastecimento é uma compra externa, fora do tanque da empresa.
--
-- Único ajuste de banco que isso pede: tanque_id em abastecimentos
-- vira opcional. Sem tanque = sem desconto de estoque e sem custo médio
-- ponderado pra esse abastecimento (o app já trata isso como "—" quando
-- não dá pra calcular) — o valor da compra no posto entra em
-- Lançamentos Financeiros à parte, não aqui. fazenda_id continua
-- obrigatório (a tela pede a fazenda diretamente quando é posto).
--
-- SÓ COLE DEPOIS de já ter rodado combustivel_unificado_01_schema.sql.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='abastecimentos') then
    raise exception 'abastecimentos nao existe - rode o combustivel_unificado_01_schema.sql primeiro.';
  end if;
end $$;

alter table abastecimentos alter column tanque_id drop not null;

select 1::numeric as ordem, 'tanque_id em abastecimentos aceita nulo' as item,
       case when is_nullable='YES' then 'sim' else 'não' end as valor,
       case when is_nullable='YES' then 'OK' else 'ERRO - ainda obrigatório' end as situacao
  from information_schema.columns
 where table_schema='public' and table_name='abastecimentos' and column_name='tanque_id';
