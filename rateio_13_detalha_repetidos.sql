-- ============================================================
-- CONFERENCIA (SO LEITURA): os dois lados de cada lancamento repetido ERP x outro
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela, uma linha por lancamento.
--
-- Continua o rateio_12_confere_repetidos.sql. Pega os grupos "ERP x lancado a mao"
-- (mesmo fornecedor, mesmo valor, mesmo mes; um com erp_id e outro sem) e mostra cada
-- lado por inteiro: quem criou, tipo, atividade, centro, datas, codigo do documento do
-- ERP e como ele conta nas atividades hoje (as partes do rateio, se tiver). Com isso da
-- para decidir qual dos dois fica.
--
-- A coluna "classe" separa:
--   A) MESMO DOCUMENTO: os dois lados citam o mesmo codigo de documento do ERP. E a
--      pista mais forte de duplicidade (a mesma conta entrou duas vezes).
--   B) MANUAL x ERP: um lado e lancamento antigo do app (sem codigo) e o outro e o ERP.
--   C) OUTRO: nenhum dos dois acima (codigos diferentes: pode ser conta parecida e legitima).
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
         l.observacao,
         substring(l.observacao from '^ERP [0-9]+') as documento,
         coalesce(cc.nome, '(sem centro de custo)') as centro,
         coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '(sem nome)') as fornecedor,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.valor > 0 and l.mes >= '2026-05' and l.tipo in ('despesa', 'investimento')
),
grupos as (
  select tipo, forn_norm, mes, valor,
         count(*) as n,
         bool_or(erp_id is not null) and bool_or(erp_id is null) as erp_x_outro,
         count(documento) as com_doc,
         count(distinct documento) as docs_distintos
    from base
   group by tipo, forn_norm, mes, valor
  having count(*) > 1
),
classificado as (
  select g.tipo, g.forn_norm, g.mes, g.valor, g.n,
         case when g.com_doc >= 2 and g.docs_distintos = 1 then 'A) mesmo documento'
              when g.docs_distintos = 0 or g.com_doc < g.n then 'B) manual x ERP'
              else 'C) outro' end as classe
    from grupos g
   where g.erp_x_outro
),
rateio as (
  select r.lancamento_id,
         string_agg(r.atividade || ' R$ ' || round(r.valor, 2)::text, ' / ' order by r.atividade) as partes
    from lancamento_rateios r
   group by r.lancamento_id
)
select c.classe,
       b.fornecedor || ' | ' || b.mes || ' | R$ ' || round(b.valor, 2)::text as conta,
       b.id,
       case when b.erp_id is not null then 'importacao do ERP' else 'lancado/acerto' end as origem,
       coalesce(b.criado_por, '-') as criado_por,
       b.tipo, b.atividade as atividade_do_lancamento, b.centro as centro_de_custo,
       coalesce(b.data::text, '-') as data, coalesce(b.vencimento::text, '-') as vencimento,
       coalesce(b.documento, '-') as documento,
       coalesce(r.partes, 'inteiro em ' || b.atividade) as como_conta_nas_atividades
  from classificado c
  join base b on b.tipo = c.tipo and b.forn_norm = c.forn_norm and b.mes = c.mes and b.valor = c.valor
  left join rateio r on r.lancamento_id = b.id
 order by c.classe, c.valor * (c.n - 1) desc, b.fornecedor, b.mes, b.id;
