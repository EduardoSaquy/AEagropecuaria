-- ============================================================
-- Pecuaria - IATF out/2026: linha 88, vaca 3 (touro MAGNO).
-- Eduardo, 02/11/2026: e a mesma vaca; lanca a inseminacao e passa
-- a vaca para o lote Vacas Vazias Santa Alice.
-- Acha a femea 3 (ou 03/003) sem ES no Nome. Se houver mais de uma,
-- para sem gravar nada. Se nao houver nenhuma, cria a 3.
-- 19/10/2026, R$ 46,30. Repetivel.
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
  v_vsa bigint; v_qtd int; v_id bigint; v_num text; v_lote_antigo text;
  v_chave text := 'IATF 19/10/2026 linha 88 - touro MAGNO';
begin
  select count(*), min(id) into v_qtd, v_vsa from lotes where lower(nome) like '%vazi%' and lower(nome) like '%alice%';
  if v_qtd <> 1 then raise exception 'Lote "Vacas Vazias Santa Alice": achei %', v_qtd; end if;

  select count(*), min(a.id), min(a.numero) into v_qtd, v_id, v_num
    from animais a
   where a.sexo = 'femea' and ltrim(trim(a.numero),'0') = '3'
     and upper(coalesce(a.nome,'')) !~ '(^|[^A-Z])ES([^A-Z]|$)';
  if v_qtd > 1 then
    raise exception 'Ha % femeas com numero 3 (03/003) sem ES. Nada foi gravado; diga qual e.', v_qtd;
  elsif v_qtd = 0 then
    insert into animais (numero, lote_id, sexo, raca, criado_por)
    values ('3', v_vsa, 'femea', 'nelore', 'Planilha IATF out/2026') returning id, numero into v_id, v_num;
    v_lote_antigo := 'nao existia, cadastrada agora';
  else
    select coalesce(l.nome,'sem lote') into v_lote_antigo
      from animais a left join lotes l on l.id = a.lote_id where a.id = v_id;
    update animais set lote_id = v_vsa, raca = coalesce(raca, 'nelore') where id = v_id;
  end if;

  if not exists (select 1 from reproducao_custos where item = v_chave) then
    insert into reproducao_custos (data, lote_id, numero_vaca, raca_touro, qual_inseminacao, custo, item, criado_por)
    values ('2026-10-19', v_vsa, v_num, 'nelore', '1', 46.30, v_chave, 'Planilha IATF out/2026');
  end if;

  raise notice 'vaca % (antes: %) agora em Vacas Vazias, inseminacao da linha 88 gravada', v_num, v_lote_antigo;
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, 'linha 88: vaca 3 -> ' || rc.numero_vaca as item,
         coalesce(l.nome,'-') || ' | R$ ' || translate(to_char(rc.custo, 'FM999G990D00'), ',.', '.,') as valor,
         case when a.lote_id = rc.lote_id then 'OK, vaca e inseminacao no mesmo lote'
              else 'DIFERENTE: vaca fora do lote da inseminacao' end as situacao
    from reproducao_custos rc
    left join animais a on a.sexo = 'femea' and lower(trim(a.numero)) = lower(trim(rc.numero_vaca))
    left join lotes l on l.id = rc.lote_id
   where rc.item = 'IATF 19/10/2026 linha 88 - touro MAGNO'
  union all
  select 2, 'TOTAL da planilha no banco',
         count(*)::text || ' de 239 | R$ ' || translate(to_char(coalesce(sum(custo),0), 'FM999G990D00'), ',.', '.,'),
         case when count(*) = 238 then 'OK, falta 1 (segunda 50 ES, linha 168)' else 'esperado 238 - confira' end
    from reproducao_custos where item like 'IATF %/10/2026 linha % - touro %'
) z
order by ordem;
