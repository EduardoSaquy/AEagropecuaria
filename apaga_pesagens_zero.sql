-- ============================================================
-- APAGA AS DUAS PESAGENS DE 0 KG (#9 e #10, de 11/08/2026)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- O QUE ACHOU A saude_do_banco_02 (item D3): duas pesagens com peso medio 0 kg, as duas de 11/08/2026:
--   #9  no lote #3  (Vacas Invernada; o lote tem outra pesagem, de 339 kg, no mesmo dia)
--   #10 no lote #33 (Vacas 07/08; era a unica pesagem do lote)
-- Peso 0 kg nao e peso: atrapalha o ganho de peso (GMD) e a arroba do lote. O Eduardo mandou apagar.
--
-- O QUE FAZ (tudo ou nada): so apaga se as duas estiverem como o relatorio descreveu
--   (ids 9 e 10, datas 11/08/2026, peso 0, lotes 3 e 33) e se NAO houver peso individual real
--   (pesagens_animais com peso maior que zero) ligado a elas; se houver, para e diz quantos.
-- Guarda copia das pesagens e dos pesos individuais em zz_backup_pesagens_zero_2026_11_06 e
-- zz_backup_pesagens_animais_zero_2026_11_06 (fechadas: so o dono do banco le), apaga e confere.
-- Rodar de novo recusa (a copia ja existe).
--
-- PARA DESFAZER:
--   insert into pesagens overriding system value select * from zz_backup_pesagens_zero_2026_11_06;
--   insert into pesagens_animais overriding system value select * from zz_backup_pesagens_animais_zero_2026_11_06;
-- ============================================================
do $apaga$
declare
  n int;
  reais int;
  esperadas int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_pesagens_zero_2026_11_06') is not null then
    raise exception 'Este script ja rodou (a copia zz_backup_pesagens_zero_2026_11_06 existe). Nao mexo em nada.';
  end if;

  select count(*) into n from pesagens where id in (9, 10);
  if n <> 2 then
    raise exception 'Achei % das 2 pesagens (#9 e #10). Nao mexo em nada.', n;
  end if;

  select count(*) into esperadas from pesagens
   where (id = 9 and lote_id = 3 and data = date '2026-08-11' and peso_medio_kg = 0)
      or (id = 10 and lote_id = 33 and data = date '2026-08-11' and peso_medio_kg = 0);
  if esperadas <> 2 then
    raise exception 'As pesagens #9 e #10 nao estao como o relatorio descreveu (lotes 3 e 33, 11/08/2026, 0 kg). Nao mexo em nada.';
  end if;

  select count(*) into reais from pesagens_animais where pesagem_id in (9, 10) and peso_kg > 0;
  if reais > 0 then
    raise exception 'Ha % peso(s) individual(is) real(is) ligados a essas pesagens. Nao mexo em nada.', reais;
  end if;

  create table zz_backup_pesagens_zero_2026_11_06 as select * from pesagens where id in (9, 10);
  create table zz_backup_pesagens_animais_zero_2026_11_06 as select * from pesagens_animais where pesagem_id in (9, 10);
  alter table zz_backup_pesagens_zero_2026_11_06 enable row level security;
  alter table zz_backup_pesagens_animais_zero_2026_11_06 enable row level security;
  revoke all on zz_backup_pesagens_zero_2026_11_06 from anon, authenticated;
  revoke all on zz_backup_pesagens_animais_zero_2026_11_06 from anon, authenticated;

  delete from pesagens where id in (9, 10);

  select count(*) into n from pesagens where id in (9, 10);
  if n <> 0 then
    raise exception 'Depois de apagar ainda sobraram % pesagem(ns). Desfeito.', n;
  end if;
end
$apaga$;

select 'pesagens #9 e #10' as item,
       (select count(*) from pesagens where id in (9, 10))::text || ' restantes' as valor,
       'copia: ' || (select count(*) from zz_backup_pesagens_zero_2026_11_06)::text || ' pesagem(ns) e '
         || (select count(*) from zz_backup_pesagens_animais_zero_2026_11_06)::text || ' peso(s) individual(is)'
         || ' | pesagens com peso fora de 20 a 1000 kg hoje: '
         || (select count(*) from pesagens where peso_medio_kg < 20 or peso_medio_kg > 1000)::text as situacao;
