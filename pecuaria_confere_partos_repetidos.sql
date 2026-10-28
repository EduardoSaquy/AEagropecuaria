-- ============================================================
-- Pecuaria - conferencia (so le, nao muda nada): vaca com mais de um
-- parto no mesmo lote (27/10/2026).
--
-- Achado da conferencia do lote do parto: Vacas 09/10 tem 82 partos de
-- 72 vacas e Vacas 07/08 tem 87 partos de 84 vacas. Uma vaca so pare
-- uma vez por estacao: dois partos dela no mesmo lote sao lancamento em
-- dobro ou gemeos. Lista cada caso com os partos (id, data, o que
-- aconteceu, sexo, quem lancou, se tem desmama) e uma sugestao.
-- ============================================================
with repetidos as (
  select p.lote_id, lower(trim(p.numero_mae)) as num
    from partos p
   where coalesce(trim(p.numero_mae), '') <> ''
   group by 1, 2
  having count(*) > 1
),
detalhe as (
  select r.lote_id, r.num, p.id, p.data, p.tipo, p.sexo_bezerro, p.criado_por, p.data_obito, p.causa_obito,
         exists (select 1 from desmamas d where d.parto_id = p.id) as desmamado
    from repetidos r
    join partos p on p.lote_id = r.lote_id and lower(trim(p.numero_mae)) = r.num
),
por_vaca as (
  select lote_id, num,
         count(*) as qtd,
         max(data) - min(data) as dias,
         string_agg('id ' || id || ' em ' || to_char(data, 'DD/MM/YYYY') || ' ('
                    || case when tipo = 'aborto' then 'aborto'
                            when data_obito is not null and data_obito = data then 'nasceu morto'
                            else coalesce(sexo_bezerro, 'sem sexo') end
                    || ', ' || coalesce(criado_por, '?')
                    || case when desmamado then ', DESMAMADO' else '' end || ')',
                    ' | ' order by data, id) as partos
    from detalhe
   group by lote_id, num
)
select 1 as ordem, 'vaca ' || v.num || ' em ' || coalesce(trim(l.nome), '?') as item,
       v.qtd || ' partos: ' || v.partos as valor,
       case when v.dias = 0 then 'MESMA DATA: gemeos ou lancado 2 vezes'
            when v.dias < 240 then 'PROVAVEL DUPLICADO (' || v.dias || ' dias entre os partos): apagar o que nao tem desmama'
            else 'OK: estacoes diferentes (' || v.dias || ' dias)' end as situacao
  from por_vaca v
  left join lotes l on l.id = v.lote_id
union all
select 2, 'total',
       (select count(*) from por_vaca)::text || ' vacas com parto repetido no mesmo lote, '
       || coalesce((select sum(qtd - 1) from por_vaca), 0) || ' partos a mais',
       case when not exists (select 1 from por_vaca) then 'OK' else 'ver linhas acima' end
order by 1, 2;
