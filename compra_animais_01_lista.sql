-- ============================================================
-- COMPRA DE ANIMAIS: lista para separar MATRIZ (rebanho de cria) de ANIMAL DE GIRO
--
-- SOMENTE LEITURA. Nao altera nada. RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- Cole inteiro, rode e mande o resultado.
--
-- PARA QUE SERVE: o resultado da Pecuaria hoje ignora tudo que e 'investimento'. Para
-- contar a compra de animais do jeito certo, cada compra precisa ser de um de dois tipos:
--   . giro   (recria, engorda, abate): o custo do lote, entra no resultado quando o lote e vendido;
--   . matriz (rebanho de cria): ativo; vale o valor em carne e so vira ganho ou perda no descarte.
-- A coluna "sugestao" abaixo vem do centro de custo (COMPRA DE MATRIZES = matriz; COMPRA DE
-- ANIMAIS = giro). O Eduardo confere e diz o que esta trocado.
--
-- LE: lancamentos_financeiros, centros_custo, lotes. Mostra uma linha por fornecedor e dia.
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
c as (
  select id, nome, tipo,
         translate(upper(nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') as nome_norm
    from centros_custo
),
l as (
  select f.id, f.tipo, f.atividade, f.valor, f.quantidade, f.unidade, f.lote_id,
         coalesce(f.data, f.vencimento) as quando,
         coalesce(nullif(btrim(f.fornecedor), ''), f.descricao, '') as quem,
         coalesce(c.nome, '(sem centro)') as centro,
         coalesce(c.nome_norm, '') as nome_norm,
         coalesce(f.descricao, '') as descricao,
         case when f.erp_id is not null then 'importacao'
              when f.criado_por like 'ERP (acerto%' then 'acerto'
              else 'a mao' end as origem
    from lancamentos_financeiros f
    left join c on c.id = f.centro_custo_id
),
compras as (
  select l.*,
         case when nome_norm like 'COMPRA DE MATRIZES%' then 'matriz'
              when nome_norm like 'COMPRA DE ANIMAIS%'  then 'giro'
              when descricao ~* 'matriz'                then 'matriz'
              else '?' end as sugestao
    from l
   where nome_norm like 'COMPRA DE MATRIZES%'
      or nome_norm like 'COMPRA DE ANIMAIS%'
      or (tipo = 'investimento' and atividade = 'pecuaria')
),
resumo as (
  select centro, tipo, sugestao, extract(year from quando)::int as ano, count(*) as n, sum(valor) as soma
    from compras group by centro, tipo, sugestao, extract(year from quando)::int
),
total_sug as (
  select sugestao, count(*) as n, sum(valor) as soma from compras group by sugestao
),
dias as (
  select quando, quem, centro, tipo, sugestao,
         count(*) as n, sum(valor) as soma,
         array_agg(id order by id) as ids,
         string_agg(distinct origem, ' + ' order by origem) as origens,
         count(lote_id) as com_lote,
         string_agg(distinct (select nome from lotes lo where lo.id = compras.lote_id), ', ') as lotes,
         sum(case when quantidade > 0 then quantidade end) as cabecas
    from compras group by quando, quem, centro, tipo, sugestao
),
saida as (
  select 0 as o1, ''::text as o2, 0::numeric as o3,
         'T) total sugerido como ' || sugestao as item,
         n::text || ' lancamentos' as valor,
         'R$ ' || round(soma, 2)::text as situacao
    from total_sug
  union all
  select 1, centro || tipo || coalesce(ano::text, ''), 0,
         'R) ' || centro || ' | ' || tipo || ' | ' || coalesce(ano::text, 'sem data'),
         n::text || ' lancamentos',
         'R$ ' || round(soma, 2)::text || ' | sugestao: ' || sugestao
    from resumo
  union all
  select 2, to_char(coalesce(quando, date '1900-01-01'), 'YYYY-MM-DD') || quem, 0,
         '   #' || array_to_string(ids[1:4], ',') || case when n > 4 then '...' else '' end || ' '
           || coalesce(to_char(quando, 'DD/MM/YYYY'), 'sem data') || ' ' || left(quem, 34),
         'R$ ' || round(soma, 2)::text || case when n > 1 then ' (' || n::text || ' lanc.)' else '' end,
         sugestao || ' | ' || tipo || ' | ' || left(centro, 38) || ' | ' || origens
           || ' | ' || case when com_lote = 0 then 'sem lote' else 'lote: ' || coalesce(lotes, '?') end
           || case when cabecas is not null then ' | ' || cabecas::text || ' cab.' else '' end
    from dias
)
select item, valor, situacao from saida order by o1, o2, o3, item;
