-- ============================================================
-- Pecuaria - lanca a pesagem retroativa do lote "Vacas de Descarte
-- 2026", feita em 20/08/2026 (o lote ja foi vendido/abatido depois --
-- Eduardo tinha a caderneta em papel e nao tinha lancado ainda). 47
-- animais, numero + peso (kg) cada, tirados da foto da caderneta e
-- conferidos com o Eduardo antes de gravar.
--
-- So grava pesagens + pesagens_animais (o mesmo que o app grava ao
-- salvar uma pesagem pela tela). NAO mexe na tabela animais -- esses
-- 47 numeros ja deviam estar cadastrados nesse lote (e ja foram
-- vendidos), entao rodar o upsert de animal aqui so arriscaria mudar o
-- lote_id de algum animal errado se o numero colidir com outro lote
-- (o mesmo numero pode existir em sexos/lotes diferentes nesta
-- fazenda -- ver PR #184). Se algum desses 47 numeros ainda nao tiver
-- cadastro individual, o Eduardo confere depois pela tela do animal.
--
-- Repetivel: se ja existir uma pesagem desse lote nessa data, nao
-- grava de novo (evita duplicar caso rode duas vezes).
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
  v_lote_id    bigint;
  v_pesagem_id bigint;
  v_data       date := '2026-08-20';
  v_media      numeric;
  v_qtd        int;
begin
  select id into v_lote_id from lotes where trim(nome) ilike 'Vacas de Descarte 2026';
  if v_lote_id is null then
    raise exception 'lote "Vacas de Descarte 2026" nao encontrado - confira o nome cadastrado';
  end if;

  if exists (select 1 from pesagens where lote_id = v_lote_id and data = v_data) then
    raise notice 'ja existe uma pesagem do lote "Vacas de Descarte 2026" em % - nada feito (confira antes de rodar de novo)', v_data;
    return;
  end if;

  select avg(peso), count(*) into v_media, v_qtd from (values
    ('020',424),('093',423),('725',510),('563',417),('703',542),('682',518),('731',534),('734',544),
    ('864',534),('107',482),('692',458),('701',461),('737',423),('067',530),('633',412),('708',628),
    ('733',530),('705',448),('099',520),('699',451),('723',470),('121',429),('047',450),('669',441),
    ('670',399),('036',456),('039',560),('677',473),('058',366),('672',469),('754',459),('719',459),
    ('184',510),('727',381),('736',580),('683',485),('065',441),('700',407),('742',459),('005',477),
    ('064',477),('706',409),('724',466),('711',407),('696',433),('664',476),('872',389)
  ) as t(numero, peso);

  if v_qtd <> 47 then
    raise exception 'esperava 47 animais, contei % - confira a lista antes de rodar', v_qtd;
  end if;

  insert into pesagens (data, lote_id, peso_medio_kg, observacao)
  values (v_data, v_lote_id, round(v_media,2), 'Vendida - Boi Brasil')
  returning id into v_pesagem_id;

  insert into pesagens_animais (pesagem_id, numero_animal, peso_kg)
  select v_pesagem_id, t.numero, t.peso from (values
    ('020',424),('093',423),('725',510),('563',417),('703',542),('682',518),('731',534),('734',544),
    ('864',534),('107',482),('692',458),('701',461),('737',423),('067',530),('633',412),('708',628),
    ('733',530),('705',448),('099',520),('699',451),('723',470),('121',429),('047',450),('669',441),
    ('670',399),('036',456),('039',560),('677',473),('058',366),('672',469),('754',459),('719',459),
    ('184',510),('727',381),('736',580),('683',485),('065',441),('700',407),('742',459),('005',477),
    ('064',477),('706',409),('724',466),('711',407),('696',433),('664',476),('872',389)
  ) as t(numero, peso);

  raise notice 'pesagem id % criada no lote "Vacas de Descarte 2026" (id %) em %, % animais, media % kg',
    v_pesagem_id, v_lote_id, v_data, v_qtd, round(v_media,2);
end $$;

-- ============================================================
-- CONFERENCIA - a pesagem tem que aparecer com 47 animais e a media
-- batendo com round(22017/47, 2) = 468,45 kg
-- ============================================================
select 1::numeric as ordem, item, valor, situacao from (
  select 'pesagem do lote "Vacas de Descarte 2026" em 20/08/2026' as item,
         'peso medio ' || p.peso_medio_kg || ' kg' as valor,
         case when p.peso_medio_kg = 468.45 then 'OK, bate com 468,45' else 'DIFERENTE do esperado (468,45) - confira' end as situacao
    from pesagens p
    join lotes l on l.id = p.lote_id
   where trim(l.nome) ilike 'Vacas de Descarte 2026' and p.data = '2026-08-20'
) x
union all
select 2::numeric, item, valor, situacao from (
  select 'quantidade de animais gravados nessa pesagem' as item,
         count(pa.id)::text as valor,
         case when count(pa.id) = 47 then 'OK, bate com 47' else 'DIFERENTE do esperado (47) - confira' end as situacao
    from pesagens p
    join lotes l on l.id = p.lote_id
    join pesagens_animais pa on pa.pesagem_id = p.id
   where trim(l.nome) ilike 'Vacas de Descarte 2026' and p.data = '2026-08-20'
) x
order by 1;
