-- ============================================================
-- Cana - corrige os talhoes de Palmito e Mata Verde com os mapas de GPS
-- (poligonos KMZ/KML, Google Earth Pro) que o Eduardo mandou em
-- 09/09/2026. Os talhoes cadastrados antes (PR #191) vieram de uma
-- planilha escrita a mao e tinham numeros diferentes -- os mapas sao a
-- fonte correta agora. So mexe nos talhoes de CANA (Palmito tem tambem
-- Reserva Legal e Glebas de abacate no mapa, que ficam de fora, a
-- pedido do Eduardo).
--
-- Palhadao NAO muda -- o mapa dela bate exato com o que ja estava
-- cadastrado (166,31 ha, mesmos 7 talhoes).
--
-- Mata Verde: a estrutura mudou de 6 para 5 talhoes (a planilha tinha
-- dividido errado). Se algum dos 6 talhoes antigos ja tiver colheita/
-- aplicacao/plantio lancado, NAO apaga -- so desativa (ativo=false) e
-- avisa no resultado, pra o Eduardo decidir o que fazer com esse
-- lancamento antes de mexer mais.
--
-- Palmito: continuam 5 talhoes, so as areas mudam um pouco -- atualiza
-- em cima do cadastro que ja existe (mesmo id, sem risco de perder
-- referencia nenhuma).
--
-- Repetivel: rodar de novo so reafirma os mesmos valores.
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
  v_cana_id  bigint;
  v_qtd_cana int;
  v_faz_id   bigint;
  v_qtd_ref  int;
begin
  select count(*) into v_qtd_cana from culturas where frente = 'cana';
  if v_qtd_cana <> 1 then
    raise exception 'esperava 1 cultura com frente=cana, achei %. Confira antes de rodar.', v_qtd_cana;
  end if;
  select id into v_cana_id from culturas where frente = 'cana';

  -- Faz. Palmito -- so atualiza area_ha dos 5 talhoes que ja existem,
  -- mesmo id, sem apagar nada.
  select id into v_faz_id from fazendas where trim(nome) ilike 'Faz. Palmito%';
  if v_faz_id is null then raise exception 'fazenda Palmito nao encontrada - confira o nome cadastrado'; end if;
  update talhoes_areas t set area_ha = v.area_nova
    from (values ('Talhão 1', 11.54), ('Talhão 2', 43.28), ('Talhão 3', 31.41),
                  ('Talhão 4', 38.40), ('Talhão 5', 27.78)) as v(nome, area_nova)
   where t.fazenda_id = v_faz_id and t.nome = v.nome;

  -- Faz. Mata Verde -- estrutura mudou (6 -> 5 talhoes). Confere
  -- referencia antes de decidir apagar ou so desativar os 6 antigos.
  select id into v_faz_id from fazendas where trim(nome) ilike 'Faz. Mata Verde%';
  if v_faz_id is null then raise exception 'fazenda Mata Verde nao encontrada - confira o nome cadastrado'; end if;

  select count(*) into v_qtd_ref
    from talhoes_areas t
   where t.fazenda_id = v_faz_id and t.nome like 'Talhão %' and t.cultura_id = v_cana_id
     and (
       exists (select 1 from colheitas_cana c where c.talhao_id = t.id)
       or exists (select 1 from aplicacoes_cana a where a.talhao_id = t.id)
       or exists (select 1 from plantios_cana p where p.talhao_id = t.id)
     );

  if v_qtd_ref = 0 then
    delete from talhoes_areas t
     where t.fazenda_id = v_faz_id and t.nome like 'Talhão %' and t.cultura_id = v_cana_id;
    raise notice 'Mata Verde: os talhoes antigos (sem nenhum lancamento) foram apagados';
  else
    update talhoes_areas t set ativo = false
     where t.fazenda_id = v_faz_id and t.nome like 'Talhão %' and t.cultura_id = v_cana_id;
    raise notice 'Mata Verde: % talhao(oes) antigo(s) tinha(m) lancamento -- so desativado(s) (ativo=false), NAO apagado(s). Confira o resultado abaixo.', v_qtd_ref;
  end if;

  insert into talhoes_areas (fazenda_id, nome, tipo, area_ha, cultura_id, ativo)
  select v_faz_id, t.nome, 'talhao', t.area_ha, v_cana_id, true
    from (values
      ('Talhão 1', 47.92), ('Talhão 2', 4.25), ('Talhão 3', 16.91),
      ('Talhão 4', 15.26), ('Talhão 5', 19.67)
    ) as t(nome, area_ha)
   where not exists (
     select 1 from talhoes_areas x
      where x.fazenda_id = v_faz_id and x.nome = t.nome and x.area_ha = t.area_ha and x.ativo = true
   );
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1::numeric as ordem, item, valor, situacao from (
  select 'Faz. Palhadão (nao deveria ter mudado)' as item,
         string_agg(t.nome||': '||t.area_ha||'ha', ', ' order by t.nome) as valor,
         case when sum(t.area_ha) = 166.31 then 'OK, total 166,31' else 'DIVERGE - confira' end as situacao
    from talhoes_areas t join fazendas f on f.id=t.fazenda_id
   where f.nome ilike 'Faz. Palhad%' and t.nome like 'Talhão %' and t.ativo
) x
union all
select 2::numeric, item, valor, situacao from (
  select 'Faz. Palmito (areas atualizadas)' as item,
         string_agg(t.nome||': '||t.area_ha||'ha', ', ' order by t.nome) as valor,
         case when sum(t.area_ha) = 152.41 then 'OK, total 152,41' else 'DIVERGE - confira' end as situacao
    from talhoes_areas t join fazendas f on f.id=t.fazenda_id
   where f.nome ilike 'Faz. Palmito%' and t.nome like 'Talhão %' and t.ativo
) x
union all
select 3::numeric, item, valor, situacao from (
  select 'Faz. Mata Verde (5 talhoes novos, ativos)' as item,
         string_agg(t.nome||': '||t.area_ha||'ha', ', ' order by t.nome) as valor,
         case when count(*)=5 and sum(t.area_ha) = 104.01 then 'OK, 5 talhoes, total 104,01' else 'DIVERGE - confira' end as situacao
    from talhoes_areas t join fazendas f on f.id=t.fazenda_id
   where f.nome ilike 'Faz. Mata Verde%' and t.nome like 'Talhão %' and t.ativo and t.area_ha in (47.92,4.25,16.91,15.26,19.67)
) x
union all
select 4::numeric, item, valor, situacao from (
  select 'Faz. Mata Verde - talhoes antigos ainda visiveis (ativos ou nao)' as item,
         t.nome||': '||t.area_ha||'ha' as valor,
         case when t.ativo then 'AINDA ATIVO - confira se e esperado' else 'desativado, OK (tinha lancamento)' end as situacao
    from talhoes_areas t join fazendas f on f.id=t.fazenda_id
   where f.nome ilike 'Faz. Mata Verde%' and t.nome like 'Talhão %'
     and t.area_ha in (26.43,22.32,4.34,19.61,16.86,15.00)
) x
order by 1;
