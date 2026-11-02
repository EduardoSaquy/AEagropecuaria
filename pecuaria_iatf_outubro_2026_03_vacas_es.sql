-- ============================================================
-- Pecuaria - IATF out/2026: as 6 vacas "ES" cujo numero ja e de
-- outra vaca (Eduardo, 02/11/2026: sao animais diferentes).
-- Numero novo = numero + 099 (mesmo padrao da 19099), "ES" no Nome.
--   linha  85: 24 ES -> 24099 (Vacas 07/08)
--   linha 158: 11 ES -> 11099 (Vacas Vazias Santa Alice)
--   linha 160: 26 ES -> 26099
--   linha 163: 34 ES -> 34099
--   linha 165: 40 ES -> 40099
--   linha 172: 59 ES -> 59099
-- Cria a vaca (femea, nelore) e grava a inseminacao de 19/10/2026,
-- R$ 46,30. Para sem gravar nada se o numero novo ja for de outra
-- femea. Repetivel.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

drop table if exists tmp_iatf3;
create temp table tmp_iatf3 (linha int primary key, planilha text, novo text, touro text, grupo text, lote_id bigint);
insert into tmp_iatf3 (linha, planilha, novo, touro, grupo) values
  (85,  '24 ES', '24099', 'DOURADO',     'V0708'),
  (158, '11 ES', '11099', 'DOURADO',     'VSA'),
  (160, '26 ES', '26099', 'DOURADO',     'VSA'),
  (163, '34 ES', '34099', 'DOURADO',     'VSA'),
  (165, '40 ES', '40099', 'MAGNO',       'VSA'),
  (172, '59 ES', '59099', 'INDICE SINO', 'VSA');

do $$
declare
  v_0708 bigint; v_vsa bigint; v_qtd int; v_conf text; v_cri int; v_ins int;
begin
  select count(*), min(id) into v_qtd, v_0708 from lotes where lower(trim(nome)) = 'vacas 07/08';
  if v_qtd <> 1 then raise exception 'Lote "Vacas 07/08": achei %', v_qtd; end if;
  select count(*), min(id) into v_qtd, v_vsa from lotes where lower(nome) like '%vazi%' and lower(nome) like '%alice%';
  if v_qtd <> 1 then raise exception 'Lote "Vacas Vazias Santa Alice": achei %', v_qtd; end if;

  update tmp_iatf3 set lote_id = case grupo when 'V0708' then v_0708 else v_vsa end;

  -- numero novo ja usado por outra femea que nao e esta ES: para tudo
  select string_agg(a.numero || ' (' || coalesce(a.nome,'sem nome') || ')', ', ') into v_conf
    from animais a join tmp_iatf3 t on lower(trim(a.numero)) = t.novo
   where a.sexo = 'femea' and coalesce(a.criado_por,'') <> 'Planilha IATF out/2026';
  if v_conf is not null then
    raise exception 'Numero novo ja existe em outra vaca: %. Nada foi gravado; escolha outro numero.', v_conf;
  end if;

  insert into animais (numero, lote_id, sexo, raca, nome, criado_por)
  select t.novo, t.lote_id, 'femea', 'nelore', 'ES', 'Planilha IATF out/2026'
    from tmp_iatf3 t
   where not exists (select 1 from animais a where lower(trim(a.numero)) = t.novo and a.sexo = 'femea');
  get diagnostics v_cri = row_count;

  insert into reproducao_custos (data, lote_id, numero_vaca, raca_touro, qual_inseminacao, custo, item, criado_por)
  select '2026-10-19', t.lote_id, t.novo, 'nelore', '1', 46.30,
         'IATF 19/10/2026 linha ' || t.linha || ' - touro ' || t.touro, 'Planilha IATF out/2026'
    from tmp_iatf3 t
   where not exists (select 1 from reproducao_custos rc
                      where rc.item = 'IATF 19/10/2026 linha ' || t.linha || ' - touro ' || t.touro);
  get diagnostics v_ins = row_count;

  raise notice 'vacas cadastradas %, inseminacoes gravadas %', v_cri, v_ins;
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, t.linha as sub, 'linha ' || t.linha || ': ' || t.planilha || ' -> ' || t.novo as item,
         coalesce(l.nome, 'sem lote') || ' | Nome: ' || coalesce(a.nome, '-') as valor,
         case when a.id is not null and rc.id is not null and a.lote_id = t.lote_id then 'OK'
              else 'DIFERENTE: falta cadastro, lote ou inseminacao' end as situacao
    from tmp_iatf3 t
    left join animais a on lower(trim(a.numero)) = t.novo and a.sexo = 'femea'
    left join lotes l on l.id = a.lote_id
    left join reproducao_custos rc on rc.item = 'IATF 19/10/2026 linha ' || t.linha || ' - touro ' || t.touro
  union all
  select 2, 0, 'TOTAL da planilha no banco',
         count(*)::text || ' de 239 | R$ ' || translate(to_char(coalesce(sum(custo),0), 'FM999G990D00'), ',.', '.,'),
         case when count(*) = 232 then 'OK, faltam 7 (0,1 / 0,3 / 0,3 ES / 0,6 / 0,7 e as duas 50 ES)'
              else 'esperado 232 - confira' end
    from reproducao_custos where item like 'IATF %/10/2026 linha % - touro %'
) z
order by ordem, sub;
