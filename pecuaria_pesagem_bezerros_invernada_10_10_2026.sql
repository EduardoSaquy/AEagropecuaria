-- ============================================================
-- Pecuaria - lanca a pesagem do lote de bezerros da Invernada,
-- feita em 10/10/2026 (caderneta Criabem em papel, 4 folhas, foto).
-- 230 animais, numero + peso (kg) cada.
--
-- So grava pesagens + pesagens_animais (o mesmo que o app grava ao
-- salvar uma pesagem pela tela). NAO mexe na tabela animais - mesmo
-- criterio da pesagem do Curral 1 (23/09/2026).
--
-- Numero gravado como escrito na caderneta (zero a esquerda mantido:
-- 025, 027, 077...). A marca 2S (56 animais) NAO entra no numero -
-- e marca de origem, nao brinco. Os 4 animais sem numero, escritos
-- so "Alice", viraram "Alice 1".."Alice 4" (pedido do Eduardo).
--
-- Correcoes de leitura confirmadas pelo Eduardo antes de gravar:
-- 271->211 (318 kg), 517->511 (209 kg), 77->11 (326 kg),
-- 444->494 (239 kg), 368->308 (344 kg), 243->293 (319 kg).
-- Nenhum numero repetido na lista.
--
-- Repetivel: se ja existir pesagem desse lote nessa data, nao grava
-- de novo.
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
  v_lotes      int;
  v_nomes      text;
  v_pesagem_id bigint;
  v_data       date := '2026-10-10';
  v_media      numeric;
  v_qtd        int;
  v_distintos  int;
begin
  select count(*), string_agg(nome, ' / '), min(id)
    into v_lotes, v_nomes, v_lote_id
    from lotes where trim(nome) ilike '%bezerr%invernada%';
  if v_lotes = 0 then
    raise exception 'nenhum lote com "bezerr" e "invernada" no nome - confira o nome cadastrado no app';
  elsif v_lotes > 1 then
    raise exception 'mais de um lote bate com o nome (%) - nada feito, diga qual e o certo', v_nomes;
  end if;

  if exists (select 1 from pesagens where lote_id = v_lote_id and data = v_data) then
    raise notice 'ja existe uma pesagem do lote % em % - nada feito', v_nomes, v_data;
    return;
  end if;

  create temp table tmp_pesagem_1010 (numero text, peso numeric) on commit drop;
  insert into tmp_pesagem_1010 (numero, peso) values
    ('486',261), ('435',264), ('Alice 1',258), ('203',259), ('410',252), ('497',248), ('386',284), ('287',298),
    ('288',289), ('025',318), ('341',297), ('492',211), ('259',285), ('275',305), ('428',254), ('489',227),
    ('221',349), ('513',260), ('490',255), ('514',316), ('246',310), ('414',156), ('Alice 2',267), ('452',312),
    ('358',330), ('454',273), ('367',303), ('211',318), ('381',294), ('312',317), ('509',228), ('433',282),
    ('308',344), ('251',294), ('491',223), ('391',300), ('427',216), ('Alice 3',318), ('267',310), ('254',330),
    ('07',300), ('255',327), ('269',280), ('401',327), ('263',328), ('437',215), ('436',211), ('390',279),
    ('208',326), ('042',310), ('525',293), ('Alice 4',342), ('222',320), ('522',255), ('444',234), ('175',281),
    ('415',279), ('537',247), ('406',297), ('508',312), ('339',309), ('501',249), ('424',238), ('291',289),
    ('515',235), ('439',257), ('500',209), ('274',309), ('354',323), ('271',332), ('045',340), ('375',224),
    ('494',239), ('511',209), ('393',280), ('369',244), ('370',308), ('226',303), ('520',221), ('451',266),
    ('364',286), ('493',228), ('278',298), ('357',302), ('408',255), ('027',322), ('077',281), ('536',218),
    ('407',294), ('62',292), ('292',272), ('379',285), ('517',229), ('340',290), ('18',289), ('438',242),
    ('441',288), ('529',275), ('362',312), ('527',216), ('425',253), ('377',282), ('383',327), ('533',208),
    ('534',277), ('524',225), ('535',270), ('398',279), ('396',271), ('394',206), ('290',282), ('487',239),
    ('485',237), ('153',301), ('264',301), ('343',262), ('512',253), ('93',306), ('540',254), ('496',225),
    ('256',314), ('429',295), ('366',287), ('484',247), ('397',335), ('41',308), ('495',247), ('426',273),
    ('447',253), ('519',281), ('346',286), ('371',263), ('521',222), ('108',284), ('389',312), ('506',294),
    ('60',321), ('432',252), ('382',262), ('403',299), ('440',244), ('192',331), ('443',321), ('505',265),
    ('431',259), ('040',327), ('253',290), ('293',319), ('146',257), ('510',214), ('286',253), ('539',244),
    ('272',296), ('483',234), ('281',294), ('518',211), ('31',306), ('244',284), ('032',301), ('526',234),
    ('498',241), ('273',316), ('516',192), ('276',277), ('284',254), ('504',284), ('530',318), ('392',240),
    ('448',240), ('385',257), ('266',331), ('405',305), ('11',326), ('144',298), ('449',182), ('434',268),
    ('23',328), ('374',281), ('387',296), ('376',278), ('345',323), ('20',316), ('6',313), ('70',312),
    ('360',288), ('507',245), ('499',211), ('257',323), ('280',297), ('283',300), ('268',323), ('350',292),
    ('156',272), ('528',196), ('260',298), ('24',308), ('450',245), ('356',297), ('300',305), ('115',310),
    ('363',311), ('039',342), ('446',221), ('388',319), ('82',252), ('22',324), ('732',327), ('503',215),
    ('14',324), ('277',287), ('136',468), ('282',264), ('532',324), ('418',307), ('299',318), ('30',327),
    ('523',277), ('502',226), ('538',264), ('347',292), ('359',277), ('289',271), ('349',340), ('344',339),
    ('455',297), ('265',307), ('117',315), ('157',295), ('294',295), ('368',271);

  select avg(peso), count(*), count(distinct numero) into v_media, v_qtd, v_distintos from tmp_pesagem_1010;
  if v_qtd <> 230 or v_distintos <> 230 then
    raise exception 'esperava 230 animais distintos, contei % (% distintos) - confira a lista', v_qtd, v_distintos;
  end if;

  insert into pesagens (data, lote_id, peso_medio_kg, observacao)
  values (
    v_data, v_lote_id, round(v_media,2),
    'Lancado a partir da caderneta Criabem (foto, 4 folhas). 56 animais marca 2S. Animal 418 anotado como doente. Alice 1 a 4 = animais sem numero na caderneta (Alice 3 e marca 2S).'
  )
  returning id into v_pesagem_id;

  insert into pesagens_animais (pesagem_id, numero_animal, peso_kg)
  select v_pesagem_id, numero, peso from tmp_pesagem_1010;

  raise notice 'pesagem id % criada no lote % (id %) em %, % animais, media % kg',
    v_pesagem_id, v_nomes, v_lote_id, v_data, v_qtd, round(v_media,2);
end $$;

-- ============================================================
-- CONFERENCIA - 230 animais, 64495 kg, media round(64495/230,2) = 280.41
-- ============================================================
select 1 as ordem, 'lote encontrado' as item,
       coalesce(string_agg(l.nome, ' / '), '-') as valor,
       case when count(*) = 1 then 'OK' else 'ERRO - esperava 1 lote, achei ' || count(*) end as situacao
  from lotes l where trim(l.nome) ilike '%bezerr%invernada%'
union all
select 2, 'peso medio da pesagem de 10/10/2026',
       coalesce(max(p.peso_medio_kg)::text, '-'),
       case when count(*) = 1 and max(p.peso_medio_kg) = 280.41 then 'OK, bate com 280.41'
            when count(*) = 0 then 'ERRO - pesagem nao gravada'
            else 'DIFERENTE do esperado (280.41) - confira' end
  from pesagens p join lotes l on l.id = p.lote_id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
union all
select 3, 'animais gravados / peso total',
       count(pa.id) || ' animais / ' || coalesce(sum(pa.peso_kg), 0) || ' kg',
       case when count(pa.id) = 230 and sum(pa.peso_kg) = 64495 then 'OK, bate com 230 / 64495' else 'DIFERENTE do esperado (230 / 64495) - confira' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
union all
select 4, 'numeros da pesagem ja cadastrados NESTE lote',
       count(*)::text, 'informativo'
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and exists (select 1 from animais a where a.lote_id = l.id and lower(trim(a.numero)) = lower(trim(pa.numero_animal)))
union all
select 5, 'numeros cadastrados em OUTRO lote',
       count(*)::text || coalesce(': ' || string_agg(pa.numero_animal, ', ' order by pa.numero_animal), ''),
       case when count(*) = 0 then 'OK' else 'conferir - mesmo animal mudou de lote ou e outro com o mesmo numero?' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and not exists (select 1 from animais a where a.lote_id = l.id and lower(trim(a.numero)) = lower(trim(pa.numero_animal)))
   and exists (select 1 from animais a where lower(trim(a.numero)) = lower(trim(pa.numero_animal)))
union all
select 6, 'numeros SEM cadastro nenhum',
       count(*)::text,
       case when count(*) = 0 then 'OK' else 'informativo - a pesagem aparece no lote, mas esses animais nao tem ficha individual' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and not exists (select 1 from animais a where lower(trim(a.numero)) = lower(trim(pa.numero_animal)))
order by 1;
