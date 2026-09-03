-- ============================================================
-- SO LEITURA -- os 23 numeros do lote 31 (macho) na pesagem recente
-- ja estao cadastrados como macho hoje, sem colisao visivel -- mas
-- Eduardo acha provavel que alguns ja tenham sido femea antes (o bug
-- do numero unico sobrescrevia sexo/lote sem deixar rastro em
-- "animais"). Como reproducao_custos/diagnosticos_gestacionais/partos
-- guardam o numero da vaca/mae em texto (nao por id do animal), um
-- numero que aparece la e' evidencia forte de que era femea antes --
-- macho nunca tem inseminacao/diagnostico/parto no nome dele. Nao
-- muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

with numeros_lote31(numero) as (
  select unnest(array[
    '119','160','173','180','189','193','210','227','229','247','249',
    '2727','2966','2978','306','313','317','795','016','037','058','015','171'
  ])
)
select 1::numeric as ordem, n.numero as item,
       coalesce(
         nullif(concat_ws(' | ',
           case when rc.qtd>0 then rc.qtd || 'x em reproducao_custos (inseminacao/protocolo)' end,
           case when dg.qtd>0 then dg.qtd || 'x em diagnosticos_gestacionais' end,
           case when pt.qtd>0 then pt.qtd || 'x em partos (como mae)' end
         ), ''),
         '0'
       ) as valor,
       case
         when coalesce(rc.qtd,0)+coalesce(dg.qtd,0)+coalesce(pt.qtd,0) > 0
           then 'EVIDENCIA de femea antes (tem registro de reproducao no nome dele)'
         else 'sem registro de reproducao -- sem evidencia (nao prova nada sozinho)'
       end as situacao
  from numeros_lote31 n
  left join (select lower(trim(numero_vaca)) num, count(*) qtd from reproducao_custos group by 1) rc
    on rc.num = lower(trim(n.numero))
  left join (select lower(trim(numero_vaca)) num, count(*) qtd from diagnosticos_gestacionais group by 1) dg
    on dg.num = lower(trim(n.numero))
  left join (select lower(trim(numero_mae)) num, count(*) qtd from partos group by 1) pt
    on pt.num = lower(trim(n.numero))
 order by (case when coalesce(rc.qtd,0)+coalesce(dg.qtd,0)+coalesce(pt.qtd,0) > 0 then 0 else 1 end), n.numero;
