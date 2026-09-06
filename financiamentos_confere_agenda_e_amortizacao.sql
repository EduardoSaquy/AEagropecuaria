-- ============================================================
-- SO LEITURA - Eduardo pediu (03/09/2026) pra checar os financiamentos
-- lancados no app: quais tem parcela agendada pra frente (parcelas
-- futuras, ainda nao pagas), e se as amortizacoes/juros de cada um
-- estao gravados certos. Nao muda nada.
--
-- CADA BLOCO:
--   1. financiamentos por status (contagem, so pra situar)
--   2. um financiamento por linha: dados do contrato, contagem de
--      parcelas (pagas / pendentes futuras / ATRASADAS / canceladas) e
--      se a soma das amortizacoes bate com o valor principal
--   3. toda parcela PENDENTE com vencimento no futuro (a agenda daqui
--      pra frente que o Eduardo pediu pra ver)
--   4. toda parcela PENDENTE com vencimento no passado (atrasada -- nao
--      deveria ter nenhuma, ou se tiver, precisa saber)
--   5. a ultima parcela nao cancelada de cada financiamento deveria
--      fechar com saldo devedor R$ 0,00 -- lista as que nao fecham
--   6. financiamento com TODAS as parcelas pagas mas status ainda
--      diferente de "quitado" (deveria ter virado quitado sozinho ao
--      pagar a ultima parcela)
--   7. parcela paga sem nenhum lancamento de juros vinculado (o juros
--      nunca foi lancado no Financeiro apesar da parcela estar paga)
--   8. parcela paga cujo lancamento de juros vinculado nao existe mais
--      em lancamentos_financeiros (foi apagado depois) -- juros pago
--      mas sumiu do Resultado
--   9. parcela paga cuja soma dos lancamentos vinculados diverge do
--      valor_juros da propria parcela (mais que 1 centavo) -- indica
--      edicao manual desalinhada
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, item, valor, situacao from (
  select 'financiamentos por status' as item,
         status as valor,
         count(*)::text || ' financiamento(s), principal total R$ ' || round(sum(valor_principal),2)::text as situacao
    from financiamentos
   group by status
) x

union all
select 2::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' - ' || f.banco || ' (' || f.finalidade
           || coalesce(', ' || f.atividade, ', rateado 1/3 Pec-Cana-Graos') || ', status ' || f.status || ')' as item,
         'principal R$ ' || f.valor_principal || ' | contratado em ' || f.data_contratacao
           || ' | ' || f.sistema_amortizacao || ' ' || f.numero_parcelas || 'x, carencia ' || f.carencia_meses || 'm'
           || ' | taxa ' || f.taxa_juros_aa || '% aa' as valor,
         (count(p.id) filter (where p.status<>'cancelada'))::text || ' parcela(s) validas: '
           || (count(p.id) filter (where p.status='paga'))::text || ' pagas, '
           || (count(p.id) filter (where p.status='pendente' and p.data_vencimento >= current_date))::text || ' pendentes no futuro, '
           || (count(p.id) filter (where p.status='pendente' and p.data_vencimento < current_date))::text || ' ATRASADAS'
           || ' | soma amortizacao R$ ' || round(coalesce(sum(p.valor_amortizacao) filter (where p.status<>'cancelada'),0),2)::text
           || case when abs(coalesce(sum(p.valor_amortizacao) filter (where p.status<>'cancelada'),0) - f.valor_principal) > 0.01
                   then ' -- DIVERGE DO PRINCIPAL R$ ' || f.valor_principal
                   else ' -- bate com o principal' end
           || case when f.data_contratacao > current_date then ' | CONTRATACAO DATADA NO FUTURO, confira' else '' end
    as situacao
    from financiamentos f
    left join parcelas_financiamento p on p.financiamento_id = f.id
   group by f.id, f.banco, f.finalidade, f.atividade, f.status, f.valor_principal,
            f.data_contratacao, f.sistema_amortizacao, f.numero_parcelas, f.carencia_meses, f.taxa_juros_aa
) x

union all
select 3::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco || ' - parcela ' || p.numero || '/' || f.numero_parcelas as item,
         'vence ' || p.data_vencimento || ' | parcela R$ ' || p.valor_parcela
           || ' | amortizacao R$ ' || p.valor_amortizacao || ' | juros R$ ' || p.valor_juros as valor,
         'saldo devedor apos R$ ' || p.saldo_devedor_apos || ' | pendente, ainda nao venceu' as situacao
    from parcelas_financiamento p
    join financiamentos f on f.id = p.financiamento_id
   where p.status = 'pendente' and p.data_vencimento >= current_date
) x

union all
select 4::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco || ' - parcela ' || p.numero || '/' || f.numero_parcelas as item,
         'venceu ' || p.data_vencimento || ' (ha ' || (current_date - p.data_vencimento) || ' dia(s)) | parcela R$ ' || p.valor_parcela as valor,
         'ATRASADA - ainda marcada pendente no banco' as situacao
    from parcelas_financiamento p
    join financiamentos f on f.id = p.financiamento_id
   where p.status = 'pendente' and p.data_vencimento < current_date
) x

union all
select 5::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco || ' - ultima parcela (' || ultima.numero || ')' as item,
         'status ' || ultima.status || ' | saldo devedor apos R$ ' || ultima.saldo_devedor_apos as valor,
         case when ultima.saldo_devedor_apos <> 0 then 'NAO FECHA EM ZERO, confira o cronograma' else 'OK' end as situacao
    from financiamentos f
    join lateral (
      select * from parcelas_financiamento p
       where p.financiamento_id = f.id and p.status <> 'cancelada'
       order by p.numero desc limit 1
    ) ultima on true
   where ultima.saldo_devedor_apos <> 0
) x

union all
select 6::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco as item,
         'status atual: ' || f.status as valor,
         'TODAS as parcelas estao pagas mas o financiamento nao esta quitado' as situacao
    from financiamentos f
   where f.status = 'ativo'
     and exists (select 1 from parcelas_financiamento p where p.financiamento_id = f.id and p.status <> 'cancelada')
     and not exists (
       select 1 from parcelas_financiamento p
        where p.financiamento_id = f.id and p.status not in ('paga','cancelada')
     )
) x

union all
select 7::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco || ' - parcela ' || p.numero as item,
         'paga em ' || p.data_pagamento || ' | juros da parcela R$ ' || p.valor_juros as valor,
         'PAGA SEM NENHUM LANCAMENTO DE JUROS VINCULADO' as situacao
    from parcelas_financiamento p
    join financiamentos f on f.id = p.financiamento_id
   where p.status = 'paga' and coalesce(array_length(p.lancamentos_financeiro_ids,1),0) = 0
) x

union all
select 8::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco || ' - parcela ' || p.numero as item,
         'lancamento_id ' || lid || ' vinculado na parcela' as valor,
         'ESSE LANCAMENTO NAO EXISTE MAIS em lancamentos_financeiros (foi apagado)' as situacao
    from parcelas_financiamento p
    join financiamentos f on f.id = p.financiamento_id
    cross join lateral unnest(p.lancamentos_financeiro_ids) as lid
   where p.status = 'paga'
     and not exists (select 1 from lancamentos_financeiros l where l.id = lid)
) x

union all
select 9::numeric, item, valor, situacao from (
  select 'Fin #' || f.id || ' ' || f.banco || ' - parcela ' || p.numero as item,
         'juros da parcela R$ ' || p.valor_juros || ' | soma dos lancamentos vinculados R$ '
           || round(coalesce((select sum(l.valor) from lancamentos_financeiros l
                               where l.id = any(p.lancamentos_financeiro_ids)),0),2)::text as valor,
         'DIVERGE - confira se a parcela ou o lancamento foi editado a mao' as situacao
    from parcelas_financiamento p
    join financiamentos f on f.id = p.financiamento_id
   where p.status = 'paga'
     and abs(p.valor_juros - coalesce((select sum(l.valor) from lancamentos_financeiros l
                                         where l.id = any(p.lancamentos_financeiro_ids)),0)) > 0.01
) x

order by 1;
