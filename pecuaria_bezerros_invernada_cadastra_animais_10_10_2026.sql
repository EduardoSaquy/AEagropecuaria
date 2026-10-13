-- ============================================================
-- Pecuaria - cadastra os animais do lote de bezerros da Invernada
-- que vieram da pesagem de 10/10/2026
-- (ver pecuaria_pesagem_bezerros_invernada_10_10_2026.sql).
-- Todos macho/nelore (confirmado pelo Eduardo). Inclui Alice 1 a 4.
--
-- Conferencia rodada pelo Eduardo: dos 230 numeros da pesagem,
--   - 188 nao tinham ficha nenhuma;
--   -  39 tinham ficha so como FEMEA, em lote de cria
--        (Vacas 07/08: 32, Vacas 09: 7) - sao as vacas, outro animal.
--        O bezerro macho com o mesmo numero pode ter ficha propria:
--        o indice animais_numero_sexo_unique e por numero+sexo;
--   -   3 tinham ficha como MACHO no Curral 2 (confinamento):
--        300, 308, 512 - adultos (~450-550 kg na pesagem do
--        Curral 1 de 23/09), outro animal. O indice impede outro
--        macho com o mesmo numero, entao esses 3 bezerros ficam SEM
--        ficha ate o Eduardo decidir como numerar. NAO mexe no
--        Curral 2.
-- Total criado: 188 + 39 = 227.
--
-- Criterio: cria ficha macho/nelore para todo numero da pesagem que
-- ainda nao tem ficha de MACHO em lote nenhum. Os numeros vem da
-- propria pesagem gravada, nao de lista copiada.
--
-- Repetivel: se ja tiver cadastrado, nao cria de novo.
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
  v_lote_id     bigint;
  v_lotes       int;
  v_pesagem_id  bigint;
  v_candidatos  int;
  v_criados     int;
begin
  select count(*), min(id) into v_lotes, v_lote_id
    from lotes where trim(nome) ilike '%bezerr%invernada%';
  if v_lotes <> 1 then
    raise exception 'esperava 1 lote de bezerros da Invernada, achei % - nada feito', v_lotes;
  end if;

  select id into v_pesagem_id from pesagens where lote_id = v_lote_id and data = '2026-10-10';
  if v_pesagem_id is null then
    raise exception 'pesagem de 10/10/2026 do lote nao encontrada - rode antes o script da pesagem';
  end if;

  select count(*) into v_candidatos
    from pesagens_animais pa
   where pa.pesagem_id = v_pesagem_id
     and not exists (select 1 from animais a where lower(trim(a.numero)) = lower(trim(pa.numero_animal)) and a.sexo = 'macho');

  if v_candidatos = 0 then
    raise notice 'nenhum numero sem ficha de macho - ja foi cadastrado antes, nada feito';
    return;
  elsif v_candidatos <> 227 then
    raise exception 'esperava 227 numeros sem ficha de macho, achei % - algo mudou desde a conferencia, nada feito', v_candidatos;
  end if;

  -- raca em minusculo: e o que o check animais_raca_check aceita
  insert into animais (numero, lote_id, sexo, raca, criado_por)
  select pa.numero_animal, v_lote_id, 'macho', 'nelore',
         'Eduardo (cadastro via SQL a partir da pesagem de 10/10/2026)'
    from pesagens_animais pa
   where pa.pesagem_id = v_pesagem_id
     and not exists (select 1 from animais a where lower(trim(a.numero)) = lower(trim(pa.numero_animal)) and a.sexo = 'macho');
  get diagnostics v_criados = row_count;

  raise notice 'cadastrados % animais (macho/nelore) no lote id %', v_criados, v_lote_id;
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, 'animais com ficha no lote Bezerros Invernada' as item,
       count(*)::text as valor,
       case when count(*) = 227 then 'OK, bate com 227 (188 novos + 39 com numero igual ao de vaca)'
            else 'DIFERENTE de 227 - confira' end as situacao
  from animais a join lotes l on l.id = a.lote_id
 where trim(l.nome) ilike '%bezerr%invernada%'
union all
select 2, 'desses, quantos estao como macho / nelore',
       count(*) filter (where a.sexo = 'macho' and a.raca = 'nelore') || ' de ' || count(*),
       case when count(*) filter (where a.sexo = 'macho' and a.raca = 'nelore') = count(*) then 'OK'
            else 'tem animal com sexo/raca diferente - confira' end
  from animais a join lotes l on l.id = a.lote_id
 where trim(l.nome) ilike '%bezerr%invernada%'
union all
select 3, 'numeros da pesagem sem ficha de macho no lote',
       count(*) || coalesce(': ' || string_agg(pa.numero_animal, ', ' order by pa.numero_animal), ''),
       case when count(*) = 3 and bool_and(pa.numero_animal in ('300','308','512')) then 'OK, so os 3 do Curral 2 (300, 308, 512) - aguardam decisao'
            else 'DIFERENTE do esperado (300, 308, 512) - confira' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and not exists (select 1 from animais a where a.lote_id = l.id and a.sexo = 'macho'
                     and lower(trim(a.numero)) = lower(trim(pa.numero_animal)))
union all
select 4, 'vacas (femea) com numero igual ao de bezerro - continuam no lote delas',
       count(*)::text,
       case when count(*) = 39 then 'OK, 39 intocadas' else 'DIFERENTE de 39 - confira' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
  join animais a on lower(trim(a.numero)) = lower(trim(pa.numero_animal)) and a.sexo = 'femea'
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and a.lote_id is distinct from l.id
order by 1;
