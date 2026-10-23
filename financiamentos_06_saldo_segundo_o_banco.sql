-- ============================================================
-- Financiamentos - saldo devedor segundo o banco (pedido do Eduardo em 23/10/2026:
-- "o saldo devedor que vc colocou e um e no contrato e outro").
--
-- O extrato do banco mostra o saldo devedor com o juros, a correcao e os seguros
-- financiados que o banco ja somou e ainda nao cobrou; o app conta so o principal
-- que falta pagar (o juros vira despesa quando a parcela e paga). Estas duas colunas
-- guardam o numero do extrato e a data dele, so para mostrar ao lado do contrato.
-- NAO entram em conta nenhuma: divida da aba Empresa, fluxo de caixa e juros
-- continuam pelo principal.
--
-- RODAR ANTES do AEMatriz.html novo para usar o campo (o app novo salva contrato
-- sem elas, mas so grava o saldo do banco depois deste script).
-- Opcionais (nulas = como era). Repetivel.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table financiamentos add column if not exists saldo_banco numeric(14,2);
alter table financiamentos add column if not exists saldo_banco_em date;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, 'coluna saldo_banco' as item,
       coalesce(max(data_type), '-') as valor,
       case when count(*) = 1 then 'OK' else 'ERRO - nao criada' end as situacao
  from information_schema.columns
 where table_schema = 'public' and table_name = 'financiamentos' and column_name = 'saldo_banco'
union all
select 2, 'coluna saldo_banco_em',
       coalesce(max(data_type), '-'),
       case when count(*) = 1 then 'OK' else 'ERRO - nao criada' end
  from information_schema.columns
 where table_schema = 'public' and table_name = 'financiamentos' and column_name = 'saldo_banco_em'
union all
select 3, 'contratos (total / com saldo do banco informado)',
       count(*) || ' / ' || count(*) filter (where saldo_banco is not null),
       'OK'
  from financiamentos
order by 1;
