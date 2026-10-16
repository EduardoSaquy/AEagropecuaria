-- ============================================================
-- Contas a Pagar/Receber - DIAGNOSTICO antes de baixar os vencidos
-- (so leitura, nao altera nada)
--
-- Pedido do Eduardo em 13/10/2026: baixar todos os titulos vencidos
-- (pagar e receber), considerando pagos na data do vencimento.
--
-- Cuidado: cada baixa gera lancamento em lancamentos_financeiros pelo
-- gatilho trg_baixa_gera_lancamento (contas_01_estrutura.sql). Se a
-- mesma despesa/receita ja foi lancada direto no Financeiro, a baixa
-- DUPLICA o valor - mesma classe do erro do ERP. Este diagnostico
-- mede isso antes de qualquer baixa.
--
-- Vencido = vencimento antes de hoje (horario de Brasilia), situacao
-- aberto ou parcial, nao cancelado.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

with hoje as (select (now() at time zone 'America/Sao_Paulo')::date as d),
venc as (
  select t.*, (t.valor - t.valor_baixado) as saldo,
         exists (select 1 from titulo_rateios r where r.titulo_id = t.id) as tem_rateio
    from titulos t, hoje
   where t.vencimento < hoje.d
     and t.situacao in ('aberto','parcial')
     and not t.cancelado
),
suspeito as (
  -- lancamento direto no Financeiro (nao veio de baixa), mesmo tipo,
  -- mesmo valor do titulo e mesmo mes do vencimento: provavel o mesmo
  -- pagamento ja lancado a mao
  select v.id, v.tipo, v.saldo
    from venc v
   where exists (
     select 1 from lancamentos_financeiros l
      where l.titulo_baixa_id is null
        and l.tipo = case when v.tipo = 'pagar' then 'despesa' else 'receita' end
        and l.valor in (v.valor, v.saldo)
        and l.mes = to_char(v.vencimento, 'YYYY-MM')
   )
)
select 1 as ordem, 'vencidos a PAGAR (qtd / saldo R$)' as item,
       count(*) || ' / ' || to_char(coalesce(sum(saldo),0), 'FM999G999G990D00') as valor,
       'informativo' as situacao
  from venc where tipo = 'pagar'
union all
select 2, 'vencidos a RECEBER (qtd / saldo R$)',
       count(*) || ' / ' || to_char(coalesce(sum(saldo),0), 'FM999G999G990D00'),
       'informativo'
  from venc where tipo = 'receber'
union all
select 3, 'vencimento mais antigo / mais recente',
       coalesce(to_char(min(vencimento),'DD/MM/YYYY') || ' a ' || to_char(max(vencimento),'DD/MM/YYYY'), '-'),
       'informativo'
  from venc
union all
select 4, 'desses, sao PREVISAO (sem boleto firme)',
       count(*) || ' / ' || to_char(coalesce(sum(saldo),0), 'FM999G999G990D00'),
       case when count(*) = 0 then 'OK' else 'decidir: baixar previsao tambem ou deixar de fora?' end
  from venc where previsao
union all
select 5, 'desses, ja com baixa parcial (vai baixar so o saldo)',
       count(*)::text,
       'informativo'
  from venc where situacao = 'parcial'
union all
select 6, 'SEM rateio (o banco recusa a baixa)',
       count(*) || coalesce(': ids ' || string_agg(id::text, ', ' order by id), ''),
       case when count(*) = 0 then 'OK' else 'ficam de fora - precisam de rateio antes' end
  from venc where not tem_rateio
union all
select 7, 'POSSIVEL DUPLICIDADE: ja tem lancamento direto no Financeiro com mesmo valor e mes',
       count(*) || ' / ' || to_char(coalesce(sum(saldo),0), 'FM999G999G990D00'),
       case when count(*) = 0 then 'OK, sem sinal de duplicidade'
            else 'CONFERIR antes de baixar - a baixa geraria o lancamento de novo' end
  from suspeito
order by 1;
