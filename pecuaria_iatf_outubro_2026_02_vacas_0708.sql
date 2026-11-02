-- ============================================================
-- Pecuaria - IATF out/2026, correcao: "VACAS MES 09" da planilha
-- e o lote "Vacas 07/08", nao "Vacas 09/10" (Eduardo, 02/11/2026).
--
-- 1) As inseminacoes das linhas 1 a 87 (19/10/2026) que o script
--    anterior gravou em Vacas 09/10 passam para Vacas 07/08.
-- 2) As 62 vacas dessas linhas que o script anterior moveu (54) ou
--    criou (8) em Vacas 09/10 voltam / vao para Vacas 07/08.
-- 3) As 24 linhas que ficaram pendentes por zero a esquerda (4 x 004
--    etc.) sao a mesma vaca: a 004 esta em Vacas 07/08, que e o lote
--    certo. Grava a inseminacao com o numero do cadastro (004), para
--    o app ligar a inseminacao a vaca. So grava se achar exatamente
--    uma femea com esse numero em Vacas 07/08.
-- Repetivel: rodar de novo nao duplica nem move nada a mais.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

drop table if exists tmp_iatf2;
create temp table tmp_iatf2 (linha int primary key, numero text, touro text,
  numero_cadastro text, qtd int, situacao text);

insert into tmp_iatf2 (linha, numero, touro) values
  (1,'4','DOURADO'), (2,'7','INDICE SINO'), (3,'9','INDICE SINO'), (4,'12','DOURADO'),
  (6,'17','INDICE SINO'), (7,'19','DOURADO'), (8,'22','DOURADO'), (9,'24','INDICE SINO'),
  (10,'26','DOURADO'), (11,'29','INDICE SINO'), (12,'35','INDICE SINO'), (13,'38','DOURADO'),
  (14,'40','DOURADO'), (15,'41','INDICE SINO'), (18,'48','INDICE SINO'), (19,'52','DOURADO'),
  (20,'55','INDICE SINO'), (21,'57','DOURADO'), (22,'59','DOURADO'), (24,'76','DOURADO'),
  (25,'80','INDICE SINO'), (26,'83','INDICE SINO'), (27,'89','DOURADO'), (28,'97','DOURADO');

do $$
declare
  v_0708 bigint; v_0910 bigint; v_qtd int;
  v_ins int; v_vacas int; v_novas int;
begin
  select count(*), min(id) into v_qtd, v_0708 from lotes where lower(trim(nome)) = 'vacas 07/08';
  if v_qtd <> 1 then raise exception 'Lote "Vacas 07/08": achei %', v_qtd; end if;
  select count(*), min(id) into v_qtd, v_0910 from lotes where lower(trim(nome)) = 'vacas 09/10';
  if v_qtd <> 1 then raise exception 'Lote "Vacas 09/10": achei %', v_qtd; end if;

  -- 1) inseminacoes das linhas 1 a 87
  update reproducao_custos set lote_id = v_0708
   where lote_id = v_0910
     and item ~ '^IATF 19/10/2026 linha [0-9]+ - touro '
     and substring(item from '^IATF 19/10/2026 linha ([0-9]+) ')::int between 1 and 87;
  get diagnostics v_ins = row_count;

  -- 2) vacas
  update animais set lote_id = v_0708
   where sexo = 'femea' and lote_id = v_0910
     and lower(trim(numero)) in (
       '16','46','47','173','401','407','408','711',
       '60','100','101','109','110','122','198','305','335','336','337','339','340','341',
       '342','343','344','348','349','350','352','353','354','357','359','360','362','364',
       '365','366','367','371','372','373','374','375','376','377','378','380','381','382',
       '383','384','385','387','388','389','390','905','19099','358','37');
  get diagnostics v_vacas = row_count;

  -- 3) as 24 pendentes por zero a esquerda
  update tmp_iatf2 t set
    qtd = (select count(*) from animais a where a.sexo='femea' and a.lote_id = v_0708
            and ltrim(trim(a.numero),'0') = t.numero),
    numero_cadastro = (select min(a.numero) from animais a where a.sexo='femea' and a.lote_id = v_0708
            and ltrim(trim(a.numero),'0') = t.numero);

  insert into reproducao_custos (data, lote_id, numero_vaca, raca_touro, qual_inseminacao, custo, item, criado_por)
  select '2026-10-19', v_0708, t.numero_cadastro, 'nelore',
         least(3, 1 + (select count(*) from reproducao_custos rc
                        where lower(trim(rc.numero_vaca)) = lower(trim(t.numero_cadastro))
                          and rc.data between date '2026-10-19' - 120 and date '2026-10-18'))::text,
         46.30, 'IATF 19/10/2026 linha ' || t.linha || ' - touro ' || t.touro, 'Planilha IATF out/2026'
    from tmp_iatf2 t
   where t.qtd = 1
     and not exists (select 1 from reproducao_custos rc
                      where rc.item = 'IATF 19/10/2026 linha ' || t.linha || ' - touro ' || t.touro);
  get diagnostics v_novas = row_count;

  update tmp_iatf2 set situacao = case when qtd = 1 then 'OK' when qtd = 0
    then 'PENDENTE: nenhuma femea ' || numero || ' (com ou sem zero) em Vacas 07/08'
    else 'PENDENTE: mais de uma femea ' || numero || ' em Vacas 07/08' end;

  raise notice 'inseminacoes trocadas de lote %, vacas para Vacas 07/08 %, inseminacoes novas %', v_ins, v_vacas, v_novas;
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, 0 as sub, 'inseminacoes da planilha em ' || l.nome as item,
         count(rc.id)::text || ' | R$ ' || translate(to_char(coalesce(sum(rc.custo),0), 'FM999G990D00'), ',.', '.,') as valor,
         case when lower(trim(l.nome)) = 'vacas 09/10' and count(rc.id) = 0 then 'OK, nenhuma (o lote certo e Vacas 07/08)'
              when lower(trim(l.nome)) = 'vacas 07/08' and count(rc.id) = 86 then 'OK, 86 de 87 (24 ES pendente)'
              when lower(trim(l.nome)) = 'vacas 07/08' then 'esperado 86 de 87 - confira as pendentes abaixo'
              else 'OK' end as situacao
    from lotes l
    left join reproducao_custos rc on rc.lote_id = l.id and rc.item like 'IATF %/10/2026 linha % - touro %'
   where lower(trim(l.nome)) in ('vacas 07/08','vacas 09/10')
   group by l.nome
  union all
  select 2, 0, 'TOTAL da planilha no banco', count(*)::text || ' de 239 | R$ ' || translate(to_char(coalesce(sum(custo),0), 'FM999G990D00'), ',.', '.,'),
         'faltam ' || (239 - count(*)) || ' (as pendentes de numero)'
    from reproducao_custos where item like 'IATF %/10/2026 linha % - touro %'
  union all
  select 3, 0, 'vacas das linhas 1 a 87 ainda em Vacas 09/10', count(*)::text,
         case when count(*) = 0 then 'OK' else 'DIFERENTE: ' || string_agg(a.numero, ', ') end
    from animais a join lotes l on l.id = a.lote_id
   where lower(trim(l.nome)) = 'vacas 09/10' and a.sexo = 'femea'
     and lower(trim(a.numero)) in (
       '16','46','47','173','401','407','408','711',
       '60','100','101','109','110','122','198','305','335','336','337','339','340','341',
       '342','343','344','348','349','350','352','353','354','357','359','360','362','364',
       '365','366','367','371','372','373','374','375','376','377','378','380','381','382',
       '383','384','385','387','388','389','390','905','19099','358','37')
  union all
  select 4, linha, 'linha ' || linha || ': ' || numero || ' -> vaca ' || coalesce(numero_cadastro,'?'), touro, situacao
    from tmp_iatf2 where situacao <> 'OK'
  union all
  select 5, 0, 'linhas de zero a esquerda resolvidas', count(*)::text || ' de 24',
         case when count(*) = 24 then 'OK' else 'faltam ' || (24 - count(*)) || ' (acima)' end
    from tmp_iatf2 where situacao = 'OK'
) z
order by ordem, sub;
