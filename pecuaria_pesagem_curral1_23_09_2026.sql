-- ============================================================
-- Pecuaria - lanca a pesagem do lote "Curral 1", feita em 23/09/2026
-- (Eduardo tinha a caderneta Criabem em papel, duas folhas, e pediu
-- pra lancar). 108 animais, numero + peso (kg) cada, tirados da foto
-- da caderneta.
--
-- So grava pesagens + pesagens_animais (o mesmo que o app grava ao
-- salvar uma pesagem pela tela). NAO mexe na tabela animais -- esses
-- 108 numeros ja deviam estar cadastrados nesse lote, entao rodar o
-- upsert de animal aqui so arriscaria mudar o lote_id de algum animal
-- errado se o numero colidir com outro lote (mesmo numero pode
-- existir em sexos/lotes diferentes nesta fazenda). Se algum desses
-- numeros ainda nao tiver cadastro individual, o Eduardo confere
-- depois pela tela do animal.
--
-- Pontos pra conferir com o Eduardo antes de considerar fechado
-- (ficam registrados na observacao da pesagem tambem):
--   - numero 301 aparece duas vezes na caderneta, com pesos diferentes
--     (487 kg e 467 kg) -- pode ser reaproveitamento de brinco ou erro
--     de leitura da foto. Gravado como veio, duas linhas.
--   - 16 animais tem marca (rasura/"x") do proprio Eduardo na
--     caderneta ao lado do peso -- nao sei o que a marca significa,
--     gravado o peso como escrito.
--   - numero "019" (bloco 2 da primeira foto) esta com caligrafia
--     ambigua, pode ser "079" (que ja aparece separado na segunda
--     foto) -- gravado como "019".
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
  v_data       date := '2026-09-23';
  v_media      numeric;
  v_qtd        int;
begin
  select id into v_lote_id from lotes where trim(nome) ilike 'Curral 1';
  if v_lote_id is null then
    raise exception 'lote "Curral 1" nao encontrado - confira o nome cadastrado no app';
  end if;

  if exists (select 1 from pesagens where lote_id = v_lote_id and data = v_data) then
    raise notice 'ja existe uma pesagem do lote "Curral 1" em % - nada feito (confira antes de rodar de novo)', v_data;
    return;
  end if;

  select avg(peso), count(*) into v_media, v_qtd from (values
    ('016',471), ('010',572), ('316',560), ('183',528), ('2962',449), ('225',524), ('236',510), ('057',534),
    ('313',540), ('229',552), ('195',510), ('304',520), ('2970',496), ('234',526), ('182',596), ('053',572),
    ('239',550), ('328',600), ('2969',477), ('210',514), ('512',544), ('2396',487), ('310',578), ('249',548),
    ('3028',477), ('143',532), ('2978',518), ('076',554), ('019',496), ('303',506), ('196',554), ('308',458),
    ('306',620), ('205',552), ('2714',493), ('126',522), ('3029',502), ('193',634), ('180',550), ('644',466),
    ('2972',467), ('103',514), ('245',485), ('2959',484), ('332',473), ('322',590), ('166',526), ('207',480),
    ('321',560), ('119',590), ('079',540), ('2952',538), ('301',487), ('139',514), ('2965',484), ('033',479),
    ('215',566), ('179',508), ('311',544), ('111',572), ('247',550), ('227',594), ('318',510), ('160',540),
    ('330',572), ('2956',520), ('176',531), ('413',516), ('642',522), ('141',478), ('075',504), ('223',532),
    ('149',512), ('2996',518), ('173',526), ('2990',514), ('063',491), ('646',514), ('3016',544), ('083',550),
    ('300',552), ('162',500), ('058',553), ('2963',534), ('333',480), ('212',492), ('3009',496), ('163',606),
    ('250',434), ('214',510), ('080',556), ('008',488), ('121',460), ('2741',544), ('329',548), ('128',570),
    ('147',508), ('003',514), ('191',504), ('301',467), ('419',526), ('005',466), ('2727',491), ('021',483),
    ('218',497), ('159',544), ('151',540), ('002',534)
  ) as t(numero, peso);

  if v_qtd <> 108 then
    raise exception 'esperava 108 animais, contei % - confira a lista antes de rodar', v_qtd;
  end if;

  insert into pesagens (data, lote_id, peso_medio_kg, observacao)
  values (
    v_data, v_lote_id, round(v_media,2),
    'Lancado a partir da caderneta Criabem (foto). Conferir: numero 301 duplicado (487 e 467 kg), 16 animais com marca do Eduardo na caderneta, numero "019" com caligrafia ambigua (pode ser 079).'
  )
  returning id into v_pesagem_id;

  insert into pesagens_animais (pesagem_id, numero_animal, peso_kg)
  select v_pesagem_id, t.numero, t.peso from (values
    ('016',471), ('010',572), ('316',560), ('183',528), ('2962',449), ('225',524), ('236',510), ('057',534),
    ('313',540), ('229',552), ('195',510), ('304',520), ('2970',496), ('234',526), ('182',596), ('053',572),
    ('239',550), ('328',600), ('2969',477), ('210',514), ('512',544), ('2396',487), ('310',578), ('249',548),
    ('3028',477), ('143',532), ('2978',518), ('076',554), ('019',496), ('303',506), ('196',554), ('308',458),
    ('306',620), ('205',552), ('2714',493), ('126',522), ('3029',502), ('193',634), ('180',550), ('644',466),
    ('2972',467), ('103',514), ('245',485), ('2959',484), ('332',473), ('322',590), ('166',526), ('207',480),
    ('321',560), ('119',590), ('079',540), ('2952',538), ('301',487), ('139',514), ('2965',484), ('033',479),
    ('215',566), ('179',508), ('311',544), ('111',572), ('247',550), ('227',594), ('318',510), ('160',540),
    ('330',572), ('2956',520), ('176',531), ('413',516), ('642',522), ('141',478), ('075',504), ('223',532),
    ('149',512), ('2996',518), ('173',526), ('2990',514), ('063',491), ('646',514), ('3016',544), ('083',550),
    ('300',552), ('162',500), ('058',553), ('2963',534), ('333',480), ('212',492), ('3009',496), ('163',606),
    ('250',434), ('214',510), ('080',556), ('008',488), ('121',460), ('2741',544), ('329',548), ('128',570),
    ('147',508), ('003',514), ('191',504), ('301',467), ('419',526), ('005',466), ('2727',491), ('021',483),
    ('218',497), ('159',544), ('151',540), ('002',534)
  ) as t(numero, peso);

  raise notice 'pesagem id % criada no lote "Curral 1" (id %) em %, % animais, media % kg',
    v_pesagem_id, v_lote_id, v_data, v_qtd, round(v_media,2);
end $$;

-- ============================================================
-- CONFERENCIA - a pesagem tem que aparecer com 108 animais e a media
-- batendo com round(56528/108, 2) = 523,41 kg
-- ============================================================
select 1::numeric as ordem, item, valor, situacao from (
  select 'pesagem do lote "Curral 1" em 23/09/2026' as item,
         'peso medio ' || p.peso_medio_kg || ' kg' as valor,
         case when p.peso_medio_kg = 523.41 then 'OK, bate com 523,41' else 'DIFERENTE do esperado (523,41) - confira' end as situacao
    from pesagens p
    join lotes l on l.id = p.lote_id
   where trim(l.nome) ilike 'Curral 1' and p.data = '2026-09-23'
) x
union all
select 2::numeric, item, valor, situacao from (
  select 'quantidade de animais gravados nessa pesagem' as item,
         count(pa.id)::text as valor,
         case when count(pa.id) = 108 then 'OK, bate com 108' else 'DIFERENTE do esperado (108) - confira' end as situacao
    from pesagens p
    join lotes l on l.id = p.lote_id
    join pesagens_animais pa on pa.pesagem_id = p.id
   where trim(l.nome) ilike 'Curral 1' and p.data = '2026-09-23'
) x
order by 1;
