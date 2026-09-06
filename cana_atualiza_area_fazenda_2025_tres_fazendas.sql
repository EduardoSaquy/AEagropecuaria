-- ============================================================
-- Cana - grava a area de cana cadastrada NA FAZENDA (fazenda_atividades,
-- atividade='cana'), separado dos talhoes -- pedido do Eduardo apos o
-- cadastro dos talhoes reais (PR #191): a area TOTAL vai na fazenda, nao
-- nos talhoes. Esse e o numero que o app usa em hectaresPorOperacao()
-- pra calcular despesa/receita por hectare em Resultados.
--
-- Valores = soma dos talhoes reais de cada fazenda (Palhadao 166,31 =
-- 30,80+22,80+21,40+19,10+21,60+38,00+12,61; Palmito 150,93; Mata Verde
-- 104,56), passados pelo Eduardo.
--
-- Se a fazenda ja tinha uma area de cana cadastrada, atualiza (UPDATE);
-- se nao tinha nenhuma, cria a linha (INSERT). Repetivel: rodar de novo
-- so reafirma o mesmo valor, nao duplica.
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
      ('Faz. Palhad%', 166.31),
      ('Faz. Palmito%', 150.93),
      ('Faz. Mata Verde%', 104.56)
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
-- CONFERENCIA - area de cana atual de cada uma das 3 fazendas
-- ============================================================
select f.nome as fazenda, fa.atividade, fa.area_ha
  from fazenda_atividades fa
  join fazendas f on f.id = fa.fazenda_id
 where f.nome ilike 'Faz. Palhad%' or f.nome ilike 'Faz. Palmito%' or f.nome ilike 'Faz. Mata Verde%'
 order by f.nome;
