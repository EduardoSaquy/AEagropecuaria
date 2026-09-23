-- ============================================================
-- Pecuaria - cadastra e realoca os animais do lote "Curral 1" a
-- partir da conferencia feita em 23/09/2026 (pesagem de 108 animais,
-- ver pecuaria_pesagem_curral1_23_09_2026.sql, PR #199).
--
-- Resultado da conferencia dos 107 numeros distintos:
--   - 14 ja estavam cadastrados no proprio Curral 1 -- nao mexe.
--   -  6 estavam cadastrados em OUTRO lote -- Eduardo confirmou que
--        sao os mesmos animais e pediu pra mudar de lote:
--        019, 057, 076, 080, 083, 147.
--   - 87 nunca tinham cadastro -- criados agora como macho/Nelore
--        (raca confirmada pelo Eduardo).
--
-- Guarda de colisao no passo B: so move um animal pro Curral 1 se
-- nao existir OUTRO animal com o mesmo numero+sexo 'macho' -- isso
-- protegeria contra um caso de brinco reaproveitado que passasse
-- despercebido (nao deveria acontecer aqui, ja que o Eduardo conferiu
-- os 6, mas o indice unico animais_numero_sexo_unique bloquearia esse
-- caso de qualquer forma -- o passo so evita que o bloqueio pare o
-- script inteiro no meio).
--
-- Repetivel: passo A so cria quem ainda nao existe (por numero, sem
-- olhar sexo -- ja que numero sozinho e unico nesses 87, nenhum tinha
-- cadastro nenhum antes). Passo B so move quem ainda nao esta no
-- Curral 1.
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
  v_lote_id  bigint;
  v_criados  int;
  v_movidos  int;
  v_pulados  int;
begin
  select id into v_lote_id from lotes where trim(nome) ilike 'Curral 1';
  if v_lote_id is null then
    raise exception 'lote "Curral 1" nao encontrado - confira o nome cadastrado no app';
  end if;

  -- Passo A: cadastra os 87 numeros sem cadastro nenhum
  -- raca em minusculo -- e o que o check constraint animais_raca_check
  -- aceita ('angus','nelore','outro'), igual o app grava pelo <select>
  insert into animais (numero, lote_id, sexo, raca, criado_por)
  select t.numero, v_lote_id, 'macho', 'nelore', 'Eduardo (cadastro via SQL a partir da pesagem de 23/09/2026)'
    from (values
      ('002'), ('003'), ('005'), ('008'), ('010'), ('016'), ('021'), ('033'), ('053'), ('058'),
      ('063'), ('075'), ('079'), ('103'), ('111'), ('121'), ('126'), ('128'), ('139'), ('141'),
      ('143'), ('149'), ('151'), ('159'), ('162'), ('163'), ('166'), ('176'), ('179'), ('182'),
      ('183'), ('191'), ('195'), ('196'), ('205'), ('207'), ('212'), ('214'), ('215'), ('218'),
      ('223'), ('225'), ('234'), ('236'), ('239'), ('245'), ('250'), ('300'), ('301'), ('303'),
      ('304'), ('308'), ('310'), ('311'), ('316'), ('318'), ('321'), ('322'), ('328'), ('329'),
      ('330'), ('332'), ('333'), ('413'), ('419'), ('512'), ('642'), ('644'), ('646'), ('2396'),
      ('2714'), ('2741'), ('2952'), ('2956'), ('2959'), ('2962'), ('2963'), ('2965'), ('2969'), ('2970'),
      ('2972'), ('2990'), ('2996'), ('3009'), ('3016'), ('3028'), ('3029')
    ) as t(numero)
   where not exists (
     select 1 from animais a where lower(trim(a.numero)) = lower(trim(t.numero))
   );
  get diagnostics v_criados = row_count;

  -- Passo B: move pro Curral 1 os 6 que ja existiam em outro lote,
  -- alinhando sexo/raca com o que o Eduardo confirmou pra esse lote.
  -- So mexe em quem ainda nao esta no Curral 1 (idempotente) e so
  -- se nao colidir com outro animal ja macho com o mesmo numero.
  with alvo as (
    select a.id
      from animais a
     where lower(trim(a.numero)) in ('019','057','076','080','083','147')
       and a.lote_id is distinct from v_lote_id
       and not exists (
         select 1 from animais a2
          where a2.id <> a.id
            and lower(trim(a2.numero)) = lower(trim(a.numero))
            and a2.sexo = 'macho'
       )
  )
  update animais a
     set lote_id = v_lote_id, sexo = 'macho', raca = coalesce(a.raca, 'nelore')
    from alvo
   where a.id = alvo.id;
  get diagnostics v_movidos = row_count;

  select count(*) into v_pulados from animais a
   where lower(trim(a.numero)) in ('019','057','076','080','083','147')
     and a.lote_id is distinct from v_lote_id;

  raise notice 'cadastrados %, movidos pro Curral 1 %, ainda fora do Curral 1 (colisao ou ja tratado) %',
    v_criados, v_movidos, v_pulados;
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1::numeric as ordem, item, valor, situacao from (
  select 'animais cadastrados no Curral 1 apos o script' as item,
         count(*)::text as valor,
         case when count(*) = 107 then 'OK, bate com 107 (os 108 numeros da pesagem, 301 conta uma vez)'
              else 'DIFERENTE de 107 - confira quem ficou de fora' end as situacao
    from animais a
    join lotes l on l.id = a.lote_id
   where trim(l.nome) ilike 'Curral 1'
     and lower(trim(a.numero)) in (
       '002','003','005','008','010','016','019','021','033','053','057','058','063','075','076',
       '079','080','083','103','111','119','121','126','128','139','141','143','147','149','151',
       '159','160','162','163','166','173','176','179','180','182','183','191','193','195','196',
       '205','207','210','212','214','215','218','223','225','227','229','234','236','239','245',
       '247','249','250','300','301','303','304','306','308','310','311','313','316','318','321',
       '322','328','329','330','332','333','413','419','512','642','644','646',
       '2396','2714','2727','2741','2952','2956','2959','2962','2963','2965','2969','2970','2972',
       '2978','2990','2996','3009','3016','3028','3029'
     )
) x
union all
select 2::numeric, item, valor, situacao from (
  select 'numeros da pesagem ainda em outro lote (colisao real ou faltou tratar)' as item,
         coalesce(string_agg(a.numero || ' (' || l.nome || ', ' || coalesce(a.sexo,'sem sexo') || ')', ', '), 'nenhum') as valor,
         case when count(*) = 0 then 'OK' else 'CONFIRA - ver detalhe na coluna valor' end as situacao
    from animais a
    join lotes l on l.id = a.lote_id
   where lower(trim(a.numero)) in ('019','057','076','080','083','147')
     and trim(l.nome) not ilike 'Curral 1'
) x
order by 1;
