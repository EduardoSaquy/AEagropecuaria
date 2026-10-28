-- ============================================================
-- Pecuaria - vacas do parto sem cadastro e a 19 ES (27/10/2026).
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Decisoes do Eduardo (27/10/2026), depois da conferencia do lote do parto:
--   1) a 19 (que ate hoje era "19 ES") NAO e a 019 do parto de 21/08:
--      a 19 ES vira 19099 (o nome ES fica) junto com o parto dela
--   2) os partos da 368 e da 370 (26/07/2026, nasceu morto), que estavam
--      sem lote, sao do lote Vacas vazia Santa Alice; 368 e 370 ganham
--      cadastro la se nao tiverem
--   3) vacas com parto em Vacas 07/08 e sem cadastro (019, 057, 076, 080,
--      083, 147) ganham cadastro de femea nesse lote, raca em branco
-- Para sem mudar nada se nao achar exatamente um lote Vacas 07/08 e um
-- Vacas vazia Santa Alice. Repetivel. Termina com a conferencia.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

create temp table if not exists conserto_partos (ordem int, item text, valor text, situacao text);
truncate conserto_partos;

do $$
declare
  v_0708  bigint;
  v_vazia bigint;
  v_qtd   int;
  v_19    bigint;
  n       int;
  num     text;
  autor   text := 'Conferencia de partos (27/10/2026)';
begin
  select count(*), min(id) into v_qtd, v_0708 from lotes where lower(trim(nome)) = 'vacas 07/08';
  if v_qtd <> 1 then
    raise exception 'esperava 1 lote Vacas 07/08, achei % - nada feito', v_qtd;
  end if;
  select count(*), min(id) into v_qtd, v_vazia from lotes where lower(trim(nome)) like '%vazia%santa alice%';
  if v_qtd <> 1 then
    raise exception 'esperava 1 lote Vacas vazia Santa Alice, achei % - nada feito', v_qtd;
  end if;

  -- ---------- 1) 19 (era 19 ES) -> 19099 ----------
  select count(*), min(id) into v_qtd, v_19
    from animais where sexo = 'femea' and lower(trim(numero)) = '19' and coalesce(nome, '') ilike '%ES%';
  if v_qtd = 0 then
    if exists (select 1 from animais where numero = '19099') then
      insert into conserto_partos values (1, 'vaca 19 ES', 'ja era 19099', 'OK');
    else
      insert into conserto_partos values (3, 'PENDENTE vaca 19 ES', 'nao achei femea 19 com nome ES', 'conferir; nada foi mudado');
    end if;
  elsif v_qtd > 1 then
    insert into conserto_partos values (3, 'PENDENTE vaca 19 ES', 'achei ' || v_qtd || ' femeas 19 com nome ES', 'conferir; nada foi mudado');
  elsif exists (select 1 from animais where id <> v_19 and lower(trim(numero)) = '19099') then
    insert into conserto_partos values (3, 'PENDENTE vaca 19 ES', 'o 19099 ja e de outro animal', 'escolher outro numero; nada foi mudado');
  else
    -- a limpeza passou exatamente 1 parto de "19 ES" para 19: so troca se for esse um
    select count(*) into n from partos where lower(trim(numero_mae)) = '19';
    if n > 1 then
      insert into conserto_partos values (3, 'PENDENTE vaca 19 ES', 'ha ' || n || ' partos com mae 19, nao sei qual e dela', 'conferir; nada foi mudado');
    else
      update animais set numero = '19099' where id = v_19;
      update partos set numero_mae = '19099' where lower(trim(numero_mae)) = '19';
      insert into conserto_partos values (1, 'vaca 19 ES', 'agora 19099 (nome ES), ' || n || ' parto junto', 'OK');
    end if;
  end if;

  -- ---------- 2) partos da 368 e 370 sem lote -> Vacas vazia Santa Alice ----------
  update partos set lote_id = v_vazia
   where lower(trim(numero_mae)) in ('368', '370') and lote_id is null;
  get diagnostics n = row_count;
  if n > 0 then
    insert into conserto_partos values (1, 'partos da 368 e 370', n || ' passaram para Vacas vazia Santa Alice', 'OK');
  end if;
  foreach num in array array['368', '370'] loop
    if not exists (select 1 from animais where sexo = 'femea' and lower(trim(numero)) = num) then
      insert into animais (numero, lote_id, sexo, criado_por) values (num, v_vazia, 'femea', autor);
      insert into conserto_partos values (1, 'vaca ' || num, 'cadastrada em Vacas vazia Santa Alice', 'OK');
    elsif not exists (select 1 from animais where sexo = 'femea' and lower(trim(numero)) = num and lote_id = v_vazia) then
      insert into conserto_partos values (3, 'vaca ' || num, 'ja tem cadastro em outro lote',
        'nao foi movida (o parto e de julho; ela pode ter mudado depois)');
    end if;
  end loop;

  -- ---------- 3) vacas do parto sem cadastro em Vacas 07/08 ----------
  foreach num in array array['019', '057', '076', '080', '083', '147'] loop
    if exists (select 1 from animais where sexo = 'femea' and lower(trim(numero)) = num) then
      continue;
    end if;
    if not exists (select 1 from partos where lote_id = v_0708 and lower(trim(numero_mae)) = num) then
      insert into conserto_partos values (3, 'PENDENTE vaca ' || num, 'nao achei parto dela em Vacas 07/08', 'conferir; nada foi mudado');
      continue;
    end if;
    insert into animais (numero, lote_id, sexo, criado_por) values (num, v_0708, 'femea', autor);
    insert into conserto_partos values (1, 'vaca ' || num, 'cadastrada em Vacas 07/08 (raca em branco)', 'OK');
  end loop;
end $$;

-- ============================================================
-- conferencia
-- ============================================================
with sem_cadastro as (
  select distinct trim(p.numero_mae) as numero
    from partos p
   where coalesce(trim(p.numero_mae), '') <> ''
     and not exists (select 1 from animais a where a.sexo = 'femea'
                      and lower(trim(a.numero)) = lower(trim(p.numero_mae)))
)
select ordem, item, valor, situacao from conserto_partos
union all
select 4, 'vacas com parto e sem cadastro',
       (select count(*) from sem_cadastro)::text
       || coalesce(' -> ' || (select string_agg(numero, ', ' order by numero) from sem_cadastro), ''),
       case when not exists (select 1 from sem_cadastro) then 'OK' else 'CONFERIR' end
union all
select 5, 'partos sem lote',
       (select count(*) from partos where lote_id is null)::text,
       case when (select count(*) from partos where lote_id is null) = 0 then 'OK' else 'CONFERIR' end
order by 1, 2;
