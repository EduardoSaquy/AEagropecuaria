-- ============================================================
-- CONFERENCIA (SO LEITURA): lancamentos repetidos pareados por DOCUMENTO, VALOR e DATA
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- POR QUE ESTA E MELHOR QUE O rateio_12/13: aqueles pareavam pelo MES. Mas a
-- importacao do ERP guarda o mes da competencia e o vencimento (data nula), e o
-- acerto de 21/10 guarda a data do PAGAMENTO. Salario pago em setembro tem
-- competencia de agosto: a mesma conta cai em meses diferentes e contas vizinhas
-- (mesmo documento recorrente, mesmo valor) caem no mesmo mes. Pareando pela data
-- (pagamento proximo do vencimento) a gente acha a mesma conta de verdade.
--
-- REGRA DO PAR: uma linha SEM erp_id (do acerto ou lancada a mao) e uma linha da
-- importacao do ERP (com erp_id) com o mesmo fornecedor, o mesmo valor, data de
-- pagamento a ate 7 dias do vencimento, e, quando a linha tem codigo de documento do
-- ERP (observacao "ERP 1234"), o mesmo codigo. Cada linha escolhe a importacao mais
-- proxima. Linha do acerto SEM par na importacao e adicao legitima (conta que a
-- importacao nao tinha) e vem so no RESUMO.
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
base as (
  select l.id, l.tipo, l.atividade, l.mes, l.data, l.vencimento, l.valor, l.erp_id, l.criado_por,
         substring(l.observacao from '^ERP [0-9]+') as documento,
         coalesce(l.data, l.vencimento) as quando,
         coalesce(cc.nome, '(sem centro de custo)') as centro,
         coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '(sem nome)') as fornecedor,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.valor > 0 and l.tipo in ('despesa', 'investimento')
     and coalesce(l.data, l.vencimento) >= date '2026-04-15'
),
imp as (select * from base where erp_id is not null),
outros as (select * from base where erp_id is null),
candidatos as (
  select o.id as o_id, i.id as i_id, abs(o.quando - i.quando) as dias,
         case when o.documento is not null and o.documento = i.documento
              then 'A) mesmo documento e data proxima'
              else 'B) sem documento (lancada a mao) e data proxima' end as classe,
         row_number() over (partition by o.id order by abs(o.quando - i.quando), i.id) as rk
    from outros o
    join imp i on i.forn_norm = o.forn_norm and i.valor = o.valor
              and abs(o.quando - i.quando) <= 7
              and (o.documento is null or o.documento = i.documento)
),
pares as (
  select * from candidatos where rk = 1
),
rateio as (
  select r.lancamento_id,
         string_agg(r.atividade || ' R$ ' || round(r.valor, 2)::text, ' / ' order by r.atividade) as partes
    from lancamento_rateios r
   group by r.lancamento_id
),
sem_par as (
  select o.* from outros o
   where o.criado_por like 'ERP (acerto%' and o.id not in (select o_id from pares)
),
saida as (
  select 0 as ord, 'RESUMO: ' || p.classe as classe, '' as conta, count(*)::text as id_outro,
         'R$ ' || round(sum(o.valor), 2)::text as criado_por, '' as atividade_outro, '' as data_outro,
         '' as id_importacao, '' as vencimento_importacao, '' as dias, '' as importacao_conta_assim
    from pares p join outros o on o.id = p.o_id
   group by p.classe
  union all
  select 0, 'RESUMO: linhas do acerto SEM par na importacao (adicao legitima)', '', count(*)::text,
         'R$ ' || coalesce(round(sum(valor), 2), 0)::text, '', '', '', '', '', ''
    from sem_par
  union all
  select 1, p.classe,
         o.fornecedor || ' | R$ ' || round(o.valor, 2)::text || ' | ' || o.centro,
         o.id::text, coalesce(o.criado_por, '-'), o.atividade || ' (' || o.tipo || ')',
         coalesce(o.quando::text, '-'),
         i.id::text, coalesce(i.vencimento::text, i.data::text, '-'), p.dias::text,
         coalesce(r.partes, 'inteiro em ' || i.atividade)
    from pares p
    join outros o on o.id = p.o_id
    join imp i on i.id = p.i_id
    left join rateio r on r.lancamento_id = i.id
)
select classe, conta, id_outro, criado_por, atividade_outro, data_outro,
       id_importacao, vencimento_importacao, dias, importacao_conta_assim
  from saida
 order by ord, classe, conta, id_outro;
