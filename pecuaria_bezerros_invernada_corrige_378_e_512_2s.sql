-- ============================================================
-- Pecuaria - bezerros da Invernada, pesagem de 10/10/2026:
-- corrige dois numeros que colidiam com machos adultos do Curral 2
-- (fichas do Curral 2 certas, confirmado pelo Eduardo).
--
-- A) o bezerro de 344 kg (folha DOM, escrito 368 na caderneta) foi
-- gravado como 308, mas 308 e um macho adulto do Curral 2 (ficha
-- certa, confirmado pelo Eduardo). Eduardo definiu o numero 378.
--
-- 1) troca 308 -> 378 na linha de 344 kg da pesagem de 10/10/2026
--    do lote de bezerros da Invernada (so essa linha);
-- 2) cria a ficha 378 macho/nelore nesse lote.
-- Nao mexe no 308 do Curral 2.
--
-- Para (nada gravado) se ja existir macho 378 em qualquer lote.
--
-- B) o bezerro de 253 kg (folha SEG, marca 2S) foi gravado como 512,
-- mas 512 e um macho adulto do Curral 2. Eduardo confirmou que e o
-- 512 da marca 2S - vira "512 2S" (a marca entra no numero so neste
-- caso, pra diferenciar do 512 do Curral 2).
--
-- Repetivel: cada bloco so age se ainda nao foi feito.
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
  v_linhas      int;
begin
  select count(*), min(id) into v_lotes, v_lote_id
    from lotes where trim(nome) ilike '%bezerr%invernada%';
  if v_lotes <> 1 then
    raise exception 'esperava 1 lote de bezerros da Invernada, achei % - nada feito', v_lotes;
  end if;

  select id into v_pesagem_id from pesagens where lote_id = v_lote_id and data = '2026-10-10';
  if v_pesagem_id is null then
    raise exception 'pesagem de 10/10/2026 do lote nao encontrada - nada feito';
  end if;

  if exists (select 1 from pesagens_animais
              where pesagem_id = v_pesagem_id and trim(numero_animal) = '378') then
    raise notice 'a pesagem ja tem o 378 - bloco A nada feito';
    return;
  end if;

  if exists (select 1 from animais where lower(trim(numero)) = '378' and sexo = 'macho') then
    raise exception 'ja existe macho 378 cadastrado em algum lote - nada feito, escolha outro numero';
  end if;

  update pesagens_animais
     set numero_animal = '378'
   where pesagem_id = v_pesagem_id and trim(numero_animal) = '308' and peso_kg = 344;
  get diagnostics v_linhas = row_count;
  if v_linhas <> 1 then
    raise exception 'esperava 1 linha 308 com 344 kg nessa pesagem, achei % - nada feito', v_linhas;
  end if;

  insert into animais (numero, lote_id, sexo, raca, criado_por)
  values ('378', v_lote_id, 'macho', 'nelore',
          'Eduardo (cadastro via SQL a partir da pesagem de 10/10/2026)');

  raise notice 'pesagem corrigida (308 -> 378, 344 kg) e ficha 378 macho/nelore criada no lote id %', v_lote_id;
end $$;

do $$
declare
  v_lote_id     bigint;
  v_lotes       int;
  v_pesagem_id  bigint;
  v_linhas      int;
begin
  select count(*), min(id) into v_lotes, v_lote_id
    from lotes where trim(nome) ilike '%bezerr%invernada%';
  if v_lotes <> 1 then
    raise exception 'esperava 1 lote de bezerros da Invernada, achei % - nada feito', v_lotes;
  end if;

  select id into v_pesagem_id from pesagens where lote_id = v_lote_id and data = '2026-10-10';
  if v_pesagem_id is null then
    raise exception 'pesagem de 10/10/2026 do lote nao encontrada - nada feito';
  end if;

  if exists (select 1 from pesagens_animais
              where pesagem_id = v_pesagem_id and lower(trim(numero_animal)) = '512 2s') then
    raise notice 'a pesagem ja tem o 512 2S - bloco B nada feito';
    return;
  end if;

  if exists (select 1 from animais where lower(trim(numero)) = '512 2s' and sexo = 'macho') then
    raise exception 'ja existe macho 512 2S cadastrado em algum lote - nada feito';
  end if;

  update pesagens_animais
     set numero_animal = '512 2S'
   where pesagem_id = v_pesagem_id and trim(numero_animal) = '512' and peso_kg = 253;
  get diagnostics v_linhas = row_count;
  if v_linhas <> 1 then
    raise exception 'esperava 1 linha 512 com 253 kg nessa pesagem, achei % - nada feito', v_linhas;
  end if;

  insert into animais (numero, lote_id, sexo, raca, criado_por)
  values ('512 2S', v_lote_id, 'macho', 'nelore',
          'Eduardo (cadastro via SQL a partir da pesagem de 10/10/2026)');

  raise notice 'pesagem corrigida (512 -> 512 2S, 253 kg) e ficha 512 2S macho/nelore criada no lote id %', v_lote_id;
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, '378 na pesagem de 10/10/2026 (deve ter 344 kg)' as item,
       coalesce(string_agg(pa.peso_kg::text || ' kg', ', '), 'nao encontrado') as valor,
       case when count(*) = 1 and max(pa.peso_kg) = 344 then 'OK' else 'confira' end as situacao
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and trim(pa.numero_animal) = '378'
union all
select 2, '308 que sobrou na pesagem de 10/10/2026',
       count(*)::text,
       case when count(*) = 0 then 'OK, nenhum' else 'ainda tem 308 na pesagem - confira' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and trim(pa.numero_animal) = '308'
union all
select 3, 'ficha 378 macho',
       coalesce(string_agg(l.nome || ' / ' || coalesce(a.raca, '-'), ', '), 'nao encontrada'),
       case when count(*) = 1 and bool_and(l.nome ilike '%bezerr%invernada%') then 'OK' else 'confira' end
  from animais a join lotes l on l.id = a.lote_id
 where lower(trim(a.numero)) = '378' and a.sexo = 'macho'
union all
select 4, 'ficha 308 macho (Curral 2, nao pode ter mudado)',
       coalesce(string_agg(l.nome, ', '), 'nao encontrada'),
       case when count(*) = 1 and bool_and(l.nome ilike 'Curral 2') then 'OK, intocado' else 'confira' end
  from animais a join lotes l on l.id = a.lote_id
 where lower(trim(a.numero)) = '308' and a.sexo = 'macho'
union all
select 5, '512 2S na pesagem de 10/10/2026 (deve ter 253 kg)',
       coalesce(string_agg(pa.peso_kg::text || ' kg', ', '), 'nao encontrado'),
       case when count(*) = 1 and max(pa.peso_kg) = 253 then 'OK' else 'confira' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and lower(trim(pa.numero_animal)) = '512 2s'
union all
select 6, 'ficha 512 2S macho',
       coalesce(string_agg(l.nome, ', '), 'nao encontrada'),
       case when count(*) = 1 and bool_and(l.nome ilike '%bezerr%invernada%') then 'OK' else 'confira' end
  from animais a join lotes l on l.id = a.lote_id
 where lower(trim(a.numero)) = '512 2s' and a.sexo = 'macho'
union all
select 7, 'ficha 512 macho (Curral 2, nao pode ter mudado)',
       coalesce(string_agg(l.nome, ', '), 'nao encontrada'),
       case when count(*) = 1 and bool_and(l.nome ilike 'Curral 2') then 'OK, intocado' else 'confira' end
  from animais a join lotes l on l.id = a.lote_id
 where lower(trim(a.numero)) = '512' and a.sexo = 'macho'
order by 1;
