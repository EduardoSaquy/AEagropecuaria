-- ============================================================
-- SÓ LEITURA — confere a(s) venda(s) recente(s) do lote "vacas de
-- descarte" (ou nome parecido) e se a receita correspondente existe em
-- lancamentos_financeiros, ligada pelo abate_id. Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem,
       'venda: ' || l.nome || ' em ' || to_char(a.data,'DD/MM/YYYY') as item,
       a.tipo_venda || ', ' || coalesce(a.quantidade::text,'?') || ' animais, R$ ' ||
         coalesce(
           case a.tipo_venda
             when 'cabeca' then (a.quantidade * a.valor_por_animal)::text
             when 'kg' then (a.quantidade * a.peso_medio_kg * a.valor_kg)::text
             else ((a.peso_medio_kg/15.0) * a.quantidade * a.valor_arroba)::text
           end, '?') as valor,
       case when a.tipo_venda='arroba' then round((a.peso_medio_kg/15.0)*a.quantidade,2)::text || ' @ registradas'
            else 'SEM ARROBA — venda lançada por ' || a.tipo_venda || ', não por arroba/carcaça' end as situacao
  from abates a
  join lotes l on l.id = a.lote_id
 where l.nome ilike '%descarte%'
union all
select 2, 'receita ligada ao abate #' || lf.abate_id,
       'R$ ' || lf.valor::text,
       'atividade=' || lf.atividade || ', mes=' || coalesce(lf.mes,'NULO — PROBLEMA') ||
         ', arrobas=' || coalesce(lf.arrobas::text,'null')
  from lancamentos_financeiros lf
 where lf.abate_id in (select a.id from abates a join lotes l on l.id=a.lote_id where l.nome ilike '%descarte%')
union all
select 3, 'abates sem receita correspondente (deveria ser 0)',
       count(*)::text,
       'esperado: 0'
  from abates a
  join lotes l on l.id = a.lote_id
 where l.nome ilike '%descarte%'
   and not exists (select 1 from lancamentos_financeiros lf where lf.abate_id = a.id)
order by 1;
