-- ============================================================
-- CONFERENCIA (SO LEITURA): repetidos que a rateio_14 nao olhou, desde janeiro/2026
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- E a mesma regra da rateio_14_pares_por_data.sql (mesmo fornecedor, mesmo valor,
-- pagamento a ate 7 dias do vencimento, mesmo documento do ERP quando a linha tem um),
-- so que olhando desde 01/01/2026. A rateio_14 comecava em 15/04/2026, que e onde
-- comecam as linhas do acerto de 21/10; antes disso so existe a lancada a mao (migrada
-- da Pecuaria) e a importacao do ERP. A limpeza de agosto so tirou a importacao de
-- atividade Cana ou Pecuaria; a importacao 'geral' (com partes) ficou, e pode estar
-- repetida com a lancada a mao de janeiro a abril.
-- As repeticoes de 15/04 em diante ja foram apagadas pela rateio_15.
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
     and coalesce(l.data, l.vencimento) >= date '2026-01-01'
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
