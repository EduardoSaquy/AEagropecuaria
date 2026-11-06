-- ============================================================
-- CONFERENCIA (SO LEITURA): a lista do que esta SEM atividade (depois da rateio_18)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- A rateio_18 mostrou que quase tudo que esta fora das tres atividades e movimento de
-- caixa que nao e custo nem receita de atividade (ajuste de saldo bancario, resgate de
-- aplicacao, estorno, aporte). Esta lista tira esses e os centavos de arredondamento e
-- mostra, linha a linha, o que SOBROU e precisa de uma atividade: despesa, receita de
-- producao e servico, venda de maquina, outros recebimentos.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

with
v as (
  select r.lancamento_id, r.tipo, r.valor, r.erp_id, r.criado_por,
         coalesce(r.data, r.vencimento) as quando, r.mes,
         coalesce(nullif(btrim(r.fornecedor), ''), r.descricao, '(sem nome)') as quem,
         coalesce(cc.nome, '(sem centro de custo)') as centro,
         btrim(regexp_replace(translate(upper(coalesce(cc.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as centro_norm,
         case when r.erp_id is not null then 'importacao do ERP'
              when r.criado_por like 'ERP (acerto%' then 'acerto de 21/10'
              else 'lancada a mao' end as origem
    from lancamentos_rateados r
    left join centros_custo cc on cc.id = r.centro_custo_id
   where r.tipo in ('despesa', 'receita', 'investimento') and r.valor <> 0
     and r.atividade not in ('pecuaria', 'cana', 'graos')
),
classe as (
  select v.*,
         case when abs(v.valor) < 1 then 'centavos'
              when v.tipo = 'receita' and (v.centro_norm like 'AJUSTE DE SALDO%'
                                        or v.centro_norm like 'RESGATE DE APLICACOES%'
                                        or v.centro_norm like 'ESTORNO%'
                                        or v.centro_norm like 'OUTRAS MOVIMENTACOES DE CAIXA%'
                                        or v.centro_norm like 'APORTE DE CAPITAL%'
                                        or v.centro_norm like 'RENDIMENTOS DE APLICACOES%')
                then 'movimento de caixa'
              else 'precisa de atividade' end as classe
    from v
),
saida as (
  select 0 as ord, 0::numeric as sub, 'RESUMO: ' || tipo || ' | ' || classe as item,
         count(*)::text || ' lancamentos' as valor, 'R$ ' || round(sum(valor), 2)::text as situacao
    from classe group by tipo, classe
  union all
  select 1, -valor, tipo || ' | ' || centro || ' | R$ ' || round(valor, 2)::text || ' | #' || lancamento_id,
         coalesce(quando::text, mes, '-'), origem || ' | ' || quem
    from classe where classe = 'precisa de atividade'
)
select item, valor, situacao from saida order by ord, sub, item;
