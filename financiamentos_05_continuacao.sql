-- ============================================================
-- Financiamentos - contrato que ja existia, lancado so pelo saldo
-- (pedido do Eduardo em 22/10/2026).
--
-- Com a divida a vencer do ERP apagada, os contratos vigentes sao lancados
-- de novo a mao so pelo saldo devedor, com data = dia da ultima parcela
-- paga (as pagas continuam no historico do ERP). Marcado assim, o contrato
-- nao entra como emprestimo recebido no fluxo de caixa (o dinheiro entrou
-- anos antes) e o saldo medio da divida emenda no historico do ERP.
--
-- RODAR ANTES do AEMatriz.html novo: o app novo grava esta coluna.
-- Contrato que ja existe fica com false (como era). Repetivel.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table financiamentos add column if not exists continuacao boolean not null default false;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, 'coluna continuacao' as item,
       coalesce(max(data_type), '-') as valor,
       case when count(*) = 1 then 'OK' else 'ERRO - nao criada' end as situacao
  from information_schema.columns
 where table_schema = 'public' and table_name = 'financiamentos' and column_name = 'continuacao'
union all
select 2, 'contratos (total / marcados como ja existentes)',
       count(*) || ' / ' || count(*) filter (where continuacao),
       'OK'
  from financiamentos
order by 1;
