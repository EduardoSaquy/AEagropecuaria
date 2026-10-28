-- ============================================================
-- Pecuaria - conferencia (so le, nao muda nada): a vaca com parto
-- lancado esta cadastrada no lote do parto? (27/10/2026)
--
-- Pedido do Eduardo: a vaca do parto tem que estar no lote em que o
-- parto foi lancado (ex.: parto da 063 em Vacas 09/10 -> a 063 tem que
-- estar em Vacas 09/10); o numero de animais do lote nao bate com o de
-- partos. Vale o parto mais recente de cada vaca.
--
-- 1) por lote: cabecas (numero_animais), vacas numeradas, partos e
--    quantas vacas do parto estao em outro lote ou sem cadastro
-- 2) cada vaca fora do lote do parto e o que fazer:
--    MOVER, ou NAO MOVER (morta, ou com lancamento no lote atual depois
--    do parto), ou CONFERIR (manejo de troca de lote depois do parto)
-- 3) cada vaca do parto sem cadastro (e se ha cadastro com o mesmo
--    numero mudando so zero a esquerda, ex.: 063 x 63)
-- ============================================================
with ultimo_parto as (
  select distinct on (lower(trim(p.numero_mae)))
         lower(trim(p.numero_mae)) as num, trim(p.numero_mae) as numero,
         p.id as parto_id, p.data, p.lote_id
    from partos p
   where coalesce(trim(p.numero_mae), '') <> ''
   order by lower(trim(p.numero_mae)), p.data desc, p.id desc
),
maes as (
  select u.*, a.id as animal_id, a.lote_id as lote_atual, a.status,
         (select string_agg(a2.numero, ', ') from animais a2
           where a2.sexo = 'femea'
             and ltrim(lower(trim(a2.numero)), '0') = ltrim(u.num, '0')
             and lower(trim(a2.numero)) <> u.num) as parecido
    from ultimo_parto u
    left join animais a on a.sexo = 'femea' and lower(trim(a.numero)) = u.num
),
eventos as (
  select lower(trim(numero_vaca)) as num, lote_id, data from diagnosticos_gestacionais
  union all select lower(trim(numero_vaca)), lote_id, data from reproducao_custos
  union all select lower(trim(numero_animal)), lote_id, data from protocolos_inseminacao
  union all select lower(trim(pa.numero_animal)), pe.lote_id, pe.data
              from pesagens_animais pa join pesagens pe on pe.id = pa.pesagem_id
),
fora as (
  select m.*,
         (select max(e.data) from eventos e
           where e.num = m.num and e.lote_id = m.lote_atual and e.data > m.data) as evento_depois,
         (select max(mj.data) from manejos mj
           where mj.lote_destino_id = m.lote_atual and mj.data > m.data) as manejo_depois
    from maes m
   where m.animal_id is not null and m.lote_atual is distinct from m.lote_id
),
resumo as (
  select l.id, l.nome, coalesce(l.numero_animais, 0) as cabecas, l.data_fim,
         (select count(*) from animais a where a.lote_id = l.id and a.sexo = 'femea' and a.status = 'ativo') as vacas_numeradas,
         (select count(*) from partos p where p.lote_id = l.id) as partos,
         (select count(distinct lower(trim(p.numero_mae))) from partos p where p.lote_id = l.id) as vacas_paridas,
         (select count(*) from fora f where f.lote_id = l.id) as vacas_fora,
         (select count(*) from maes m where m.lote_id = l.id and m.animal_id is null) as sem_cadastro
    from lotes l
   where exists (select 1 from partos p where p.lote_id = l.id)
)
select 1 as ordem, r.nome as item,
       'cabecas: ' || r.cabecas || ' | vacas numeradas: ' || r.vacas_numeradas
       || ' | partos: ' || r.partos || ' (' || r.vacas_paridas || ' vacas)'
       || ' | vacas do parto em outro lote: ' || r.vacas_fora
       || ' | sem cadastro: ' || r.sem_cadastro
       || case when r.data_fim is not null then ' | lote encerrado' else '' end as valor,
       case when r.vacas_fora = 0 and r.sem_cadastro = 0 and r.vacas_paridas <= r.cabecas then 'OK'
            when r.vacas_paridas > r.cabecas then 'CONFERIR: mais vacas paridas que cabecas no lote'
            else 'CONFERIR: vacas fora do lote ou sem cadastro (ver abaixo)' end as situacao
  from resumo r
union all
select 2, 'vaca ' || f.numero,
       'esta em ' || coalesce(la.nome, 'sem lote') || ', parto em ' || coalesce(lp.nome, '?')
       || ' (' || to_char(f.data, 'DD/MM/YYYY') || ')',
       case when f.status = 'morto' then 'NAO MOVER: morta'
            when f.evento_depois is not null then 'NAO MOVER: tem lancamento em ' || coalesce(la.nome, '?')
                 || ' em ' || to_char(f.evento_depois, 'DD/MM/YYYY') || ', depois do parto'
            when f.manejo_depois is not null then 'CONFERIR: manejo levou animais para ' || coalesce(la.nome, '?')
                 || ' em ' || to_char(f.manejo_depois, 'DD/MM/YYYY') || ', depois do parto'
            else 'MOVER para ' || coalesce(lp.nome, '?') end
  from fora f
  left join lotes la on la.id = f.lote_atual
  left join lotes lp on lp.id = f.lote_id
union all
select 3, 'vaca ' || m.numero,
       'sem cadastro; parto em ' || coalesce(lp.nome, '?') || ' (' || to_char(m.data, 'DD/MM/YYYY') || ')',
       case when m.parecido is not null then 'CONFERIR: existe cadastro ' || m.parecido || ' (zero a esquerda diferente)'
            else 'CADASTRAR no lote do parto' end
  from maes m
  left join lotes lp on lp.id = m.lote_id
 where m.animal_id is null
union all
select 4, 'total',
       (select count(*) from maes)::text || ' vacas com parto | no lote certo: '
       || (select count(*) from maes where animal_id is not null and lote_atual is not distinct from lote_id)
       || ' | em outro lote: ' || (select count(*) from fora)
       || ' | sem cadastro: ' || (select count(*) from maes where animal_id is null),
       case when not exists (select 1 from fora) and not exists (select 1 from maes where animal_id is null)
            then 'OK' else 'ver linhas acima' end
order by 1, 2;
