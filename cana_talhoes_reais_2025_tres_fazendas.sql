-- ============================================================
-- Cana - cadastra os talhoes REAIS (numero + area) das 3 fazendas que o
-- Eduardo passou (Palhadao, Palmito, Mata Verde), safra 2025. Passam a
-- ser os talhoes de cadastro usados daqui pra frente pra lancar colheita/
-- aplicacao de verdade em AECana.html.
--
-- NAO mexe no talhao "Historico 2025" (nem nos anteriores 2023/2024)
-- criado antes so pra guardar a tonelada agregada da safra inteira, sem
-- quebra por talhao -- decisao do Eduardo, fica como esta.
--
-- Variedade de cada talhao (NAO gravada agora -- Plantio exige data de
-- plantio, que nao temos; decisao do Eduardo foi so cadastrar o talhao e
-- deixar a variedade/Plantio pra quando tiver a data certa). Registro
-- aqui pra nao perder:
--   Palhadao:    1 CTC 4 | 2 (sem variedade informada) | 3 DIVERSAS |
--                4 CTC4/2994 | 5 2994/3280/4 | 6 3280 | 7 CTC 4
--   Palmito:     1 3280/5902 | 2 5094 | 3 5094 | 4 5094 | 5 3280/5902
--   Mata Verde:  1 CTC2 | 2 CTC2 | 3 579 | 4 CTC2/579 | 5 CTC2/579 | 6 3280
--
-- Repetivel: nao duplica se rodar de novo (confere fazenda_id+nome antes
-- de inserir).
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
begin
  select count(*) into v_qtd_cana from culturas where frente = 'cana';
  if v_qtd_cana <> 1 then
    raise exception 'esperava 1 cultura com frente=cana, achei %. Confira antes de rodar.', v_qtd_cana;
  end if;
  select id into v_cana_id from culturas where frente = 'cana';

  -- Faz. Palhadao -----------------------------------------------------
  select id into v_faz_id from fazendas where trim(nome) ilike 'Faz. Palhad%';
  if v_faz_id is null then raise exception 'fazenda Palhadao nao encontrada - confira o nome cadastrado'; end if;
  insert into talhoes_areas (fazenda_id, nome, tipo, area_ha, cultura_id, ativo)
  select v_faz_id, t.nome, 'talhao', t.area_ha, v_cana_id, true
    from (values
      ('Talhão 1', 30.80), ('Talhão 2', 22.80), ('Talhão 3', 21.40), ('Talhão 4', 19.10),
      ('Talhão 5', 21.60), ('Talhão 6', 38.00), ('Talhão 7', 12.61)
    ) as t(nome, area_ha)
   where not exists (select 1 from talhoes_areas x where x.fazenda_id = v_faz_id and x.nome = t.nome);

  -- Faz. Palmito --------------------------------------------------------
  select id into v_faz_id from fazendas where trim(nome) ilike 'Faz. Palmito%';
  if v_faz_id is null then raise exception 'fazenda Palmito nao encontrada - confira o nome cadastrado'; end if;
  insert into talhoes_areas (fazenda_id, nome, tipo, area_ha, cultura_id, ativo)
  select v_faz_id, t.nome, 'talhao', t.area_ha, v_cana_id, true
    from (values
      ('Talhão 1', 10.57), ('Talhão 2', 42.95), ('Talhão 3', 31.49), ('Talhão 4', 37.94),
      ('Talhão 5', 27.98)
    ) as t(nome, area_ha)
   where not exists (select 1 from talhoes_areas x where x.fazenda_id = v_faz_id and x.nome = t.nome);

  -- Faz. Mata Verde ------------------------------------------------------
  select id into v_faz_id from fazendas where trim(nome) ilike 'Faz. Mata Verde%';
  if v_faz_id is null then raise exception 'fazenda Mata Verde nao encontrada - confira o nome cadastrado'; end if;
  insert into talhoes_areas (fazenda_id, nome, tipo, area_ha, cultura_id, ativo)
  select v_faz_id, t.nome, 'talhao', t.area_ha, v_cana_id, true
    from (values
      ('Talhão 1', 26.43), ('Talhão 2', 22.32), ('Talhão 3', 4.34), ('Talhão 4', 19.61),
      ('Talhão 5', 16.86), ('Talhão 6', 15.00)
    ) as t(nome, area_ha)
   where not exists (select 1 from talhoes_areas x where x.fazenda_id = v_faz_id and x.nome = t.nome);
end $$;

-- ============================================================
-- CONFERENCIA - os 18 talhoes novos (7+5+6), com a fazenda ao lado
-- ============================================================
select f.nome as fazenda, t.nome as talhao, t.area_ha, t.ativo
  from talhoes_areas t
  join fazendas f on f.id = t.fazenda_id
 where f.nome ilike 'Faz. Palhad%' or f.nome ilike 'Faz. Palmito%' or f.nome ilike 'Faz. Mata Verde%'
 order by f.nome, t.nome;
