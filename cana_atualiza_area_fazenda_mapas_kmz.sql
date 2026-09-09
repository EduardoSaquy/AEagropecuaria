-- ============================================================
-- Cana - reajusta a area de cana da FAZENDA (fazenda_atividades,
-- atividade='cana') de Palmito e Mata Verde pros totais reais dos mapas
-- de GPS (cana_corrige_talhoes_mapas_kmz.sql), no lugar dos totais da
-- planilha escrita a mao usados em cana_atualiza_area_fazenda_01_
-- tres_fazendas.sql.
--
-- Palhadao NAO muda -- o mapa bateu exato com o que ja estava (166,31 ha),
-- entao a area da fazenda ja esta certa e essa migracao nem toca nela.
--
-- Palmito: 150,93 -> 152,41 ha
-- Mata Verde: 104,56 -> 104,01 ha
--
-- Repetivel: rodar de novo so reafirma o mesmo valor, nao duplica.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

do $$
declare
  v_faz_id  bigint;
  v_antiga  numeric;
  v_padrao  text;
  v_area    numeric;
  v_row     record;
begin
  for v_row in
    select * from (values
      ('Faz. Palmito%', 152.41),
      ('Faz. Mata Verde%', 104.01)
    ) as t(padrao, area)
  loop
    v_padrao := v_row.padrao;
    v_area   := v_row.area;

    select id into v_faz_id from fazendas where trim(nome) ilike v_padrao;
    if v_faz_id is null then
      raise exception 'fazenda "%" nao encontrada - confira o nome cadastrado', v_padrao;
    end if;

    select area_ha into v_antiga from fazenda_atividades where fazenda_id = v_faz_id and atividade = 'cana';

    if v_antiga is null then
      insert into fazenda_atividades (fazenda_id, atividade, area_ha) values (v_faz_id, 'cana', v_area);
      raise notice 'fazenda "%" (id %): area de cana CRIADA em % ha (nao tinha cadastro antes)', v_padrao, v_faz_id, v_area;
    else
      update fazenda_atividades set area_ha = v_area where fazenda_id = v_faz_id and atividade = 'cana';
      raise notice 'fazenda "%" (id %): area de cana atualizada de % ha pra % ha', v_padrao, v_faz_id, v_antiga, v_area;
    end if;
  end loop;
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1::numeric as ordem, item, valor, situacao from (
  select 'Faz. Palhadão (nao deveria ter mudado)' as item,
         fa.area_ha::text as valor,
         case when fa.area_ha = 166.31 then 'OK, 166,31' else 'DIVERGE - confira' end as situacao
    from fazenda_atividades fa join fazendas f on f.id=fa.fazenda_id
   where f.nome ilike 'Faz. Palhad%' and fa.atividade = 'cana'
) x
union all
select 2::numeric, item, valor, situacao from (
  select 'Faz. Palmito (area atualizada)' as item,
         fa.area_ha::text as valor,
         case when fa.area_ha = 152.41 then 'OK, 152,41' else 'DIVERGE - confira' end as situacao
    from fazenda_atividades fa join fazendas f on f.id=fa.fazenda_id
   where f.nome ilike 'Faz. Palmito%' and fa.atividade = 'cana'
) x
union all
select 3::numeric, item, valor, situacao from (
  select 'Faz. Mata Verde (area atualizada)' as item,
         fa.area_ha::text as valor,
         case when fa.area_ha = 104.01 then 'OK, 104,01' else 'DIVERGE - confira' end as situacao
    from fazenda_atividades fa join fazendas f on f.id=fa.fazenda_id
   where f.nome ilike 'Faz. Mata Verde%' and fa.atividade = 'cana'
) x
order by 1;
