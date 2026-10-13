-- ============================================================
-- Contas a Pagar/Receber - BAIXA dos titulos vencidos
--
-- Pedido do Eduardo em 13/10/2026: todos os titulos vencidos (pagar e
-- receber) foram pagos no dia do vencimento - dar baixa de todos.
--
-- Diagnostico rodado antes (contas_09_baixa_vencidos_01_diagnostico.sql):
--   34 a pagar / R$ 200.568,13, 0 a receber, vencimentos de 14/09/2026
--   a 12/10/2026, 0 previsao, 0 parcial, 0 sem rateio, 0 com sinal de
--   duplicidade no Financeiro.
--
-- O que faz: uma baixa por titulo, data = vencimento, valor = saldo,
-- mesma conta bancaria do titulo. O gatilho trg_baixa_gera_lancamento
-- cria os lancamentos_financeiros (um por rateio, data = vencimento) e
-- marca o titulo como pago - nada disso e feito aqui a mao.
--
-- Trava: so roda se ainda forem exatamente os 34 titulos / 200568.13
-- do diagnostico. Se rodar outro dia (entra titulo que venceu depois)
-- ou alguem baixou algum pelo app no meio tempo, para sem gravar nada.
-- Repetivel: depois de baixados eles viram "pago" e nao entram de novo.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

do $$
declare
  v_hoje   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_qtd    int;
  v_saldo  numeric;
  v_feitas int;
begin
  select count(*), coalesce(sum(valor - valor_baixado), 0)
    into v_qtd, v_saldo
    from titulos
   where vencimento < v_hoje
     and situacao in ('aberto','parcial')
     and not cancelado;

  if v_qtd = 0 then
    raise notice 'nenhum titulo vencido em aberto - ja foi baixado, nada feito';
    return;
  end if;
  if v_qtd <> 34 or v_saldo <> 200568.13 then
    raise exception 'esperava 34 titulos / 200568.13 (diagnostico), achei % / % - nada feito, rode o diagnostico de novo', v_qtd, v_saldo;
  end if;

  insert into titulo_baixas (titulo_id, data, valor, conta_bancaria_id, observacao, criado_por)
  select id, vencimento, valor - valor_baixado, conta_bancaria_id,
         'Baixa em lote: pago no vencimento (pedido do Eduardo em 13/10/2026)',
         'Eduardo (baixa em lote via SQL, 13/10/2026)'
    from titulos
   where vencimento < v_hoje
     and situacao in ('aberto','parcial')
     and not cancelado
   order by vencimento, id;
  get diagnostics v_feitas = row_count;

  raise notice 'baixas criadas: % (R$ %)', v_feitas, v_saldo;
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
with baixas as (
  select b.* from titulo_baixas b
   where b.criado_por = 'Eduardo (baixa em lote via SQL, 13/10/2026)'
)
select 1 as ordem, 'baixas criadas (qtd / R$)' as item,
       count(*) || ' / ' || to_char(coalesce(sum(valor),0), 'FM999G999G990D00') as valor,
       case when count(*) = 34 and sum(valor) = 200568.13 then 'OK, bate com 34 / 200.568,13'
            else 'DIFERENTE do esperado - confira' end as situacao
  from baixas
union all
select 2, 'baixas com data diferente do vencimento',
       count(*)::text,
       case when count(*) = 0 then 'OK' else 'ERRO - confira' end
  from baixas b join titulos t on t.id = b.titulo_id
 where b.data <> t.vencimento
union all
select 3, 'lancamentos gerados no Financeiro (qtd / R$)',
       count(*) || ' / ' || to_char(coalesce(sum(l.valor),0), 'FM999G999G990D00'),
       case when coalesce(sum(l.valor),0) = 200568.13 then 'OK, soma bate com as baixas'
            else 'DIFERENTE de 200.568,13 - confira' end
  from lancamentos_financeiros l
 where l.titulo_baixa_id in (select id from baixas)
union all
select 4, 'titulos vencidos ainda em aberto',
       count(*)::text,
       case when count(*) = 0 then 'OK, nenhum' else 'sobrou titulo vencido - confira' end
  from titulos
 where vencimento < (now() at time zone 'America/Sao_Paulo')::date
   and situacao in ('aberto','parcial')
   and not cancelado
order by 1;
