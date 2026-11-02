-- ============================================================
-- Pecuaria - IATF out/2026: as 5 linhas que a planilha mostrou com
-- virgula (Eduardo, 02/11/2026, brincos reais):
--   linha  88: 0,3    -> 3
--   linha 154: 0,1 ES -> 1 ES
--   linha 155: 0,3 ES -> 3 ES
--   linha 156: 0,6 ES -> 6 ES
--   linha 157: 0,7 ES -> 7 ES
-- Lote Vacas Vazias Santa Alice, 19/10/2026, R$ 46,30.
--
-- Vaca sem ES (3): usa a femea 3 (ou 03/003) se ela ja estiver em
-- Vacas Vazias; se nao existir, cria a 3; se existir em outro lote,
-- fica PENDENTE (nao move sozinho).
-- Vaca ES: "ES" vai para o Nome. Se nao existir femea N (nem 0N),
-- vira N; se existir (e outro animal), vira N099, como a 19099.
-- Numero novo ja usado por outra vaca: para sem gravar nada.
-- Repetivel.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

drop table if exists tmp_iatf4;
create temp table tmp_iatf4 (linha int primary key, n text, es boolean, touro text,
  numero_final text, acao text, situacao text);
insert into tmp_iatf4 (linha, n, es, touro) values
  (88,  '3', false, 'MAGNO'),
  (154, '1', true,  'MAGNO'),
  (155, '3', true,  'INDICE SINO'),
  (156, '6', true,  'DOURADO'),
  (157, '7', true,  'DOURADO');

do $$
declare
  r record; v_vsa bigint; v_qtd int; v_id bigint; v_lote bigint; v_num text; v_lnome text;
  v_chave text; v_ins int := 0; v_cri int := 0;
begin
  select count(*), min(id) into v_qtd, v_vsa from lotes where lower(nome) like '%vazi%' and lower(nome) like '%alice%';
  if v_qtd <> 1 then raise exception 'Lote "Vacas Vazias Santa Alice": achei %', v_qtd; end if;

  for r in select * from tmp_iatf4 order by es, linha loop
    v_chave := 'IATF 19/10/2026 linha ' || r.linha || ' - touro ' || r.touro;

    -- ja gravada numa rodada anterior
    select numero_vaca into v_num from reproducao_custos where item = v_chave;
    if found then
      update tmp_iatf4 set numero_final = v_num, acao = 'ja gravada', situacao = 'OK' where linha = r.linha;
      continue;
    end if;

    if not r.es then
      select count(*), min(a.id), min(a.numero), min(a.lote_id) into v_qtd, v_id, v_num, v_lote
        from animais a where a.sexo = 'femea' and ltrim(trim(a.numero),'0') = r.n
         and upper(coalesce(a.nome,'')) !~ '(^|[^A-Z])ES([^A-Z]|$)';
      if v_qtd > 1 then
        update tmp_iatf4 set acao = 'pendente', situacao = 'PENDENTE: mais de uma femea ' || r.n || ' (com zero a esquerda)' where linha = r.linha;
        continue;
      elsif v_qtd = 1 and v_lote is distinct from v_vsa then
        select nome into v_lnome from lotes where id = v_lote;
        update tmp_iatf4 set acao = 'pendente',
          situacao = 'PENDENTE: a vaca ' || v_num || ' esta em ' || coalesce(v_lnome,'nenhum lote') || ': e a mesma? (nao movi)'
         where linha = r.linha;
        continue;
      elsif v_qtd = 0 then
        insert into animais (numero, lote_id, sexo, raca, criado_por)
        values (r.n, v_vsa, 'femea', 'nelore', 'Planilha IATF out/2026');
        v_num := r.n; v_cri := v_cri + 1;
      end if;
    else
      -- ES ja criada antes (mesmo numero ou N099 com Nome ES em Vacas Vazias)
      select a.numero into v_num from animais a
       where a.sexo = 'femea' and a.lote_id = v_vsa and a.criado_por = 'Planilha IATF out/2026'
         and lower(trim(a.numero)) in (r.n, r.n || '099') and a.nome = 'ES';
      if not found then
        if exists (select 1 from animais a where a.sexo = 'femea' and ltrim(trim(a.numero),'0') = r.n) then
          v_num := r.n || '099';
        else
          v_num := r.n;
        end if;
        if exists (select 1 from animais a where a.sexo = 'femea' and lower(trim(a.numero)) = v_num) then
          raise exception 'O numero % (para a % ES) ja e de outra vaca. Nada foi gravado.', v_num, r.n;
        end if;
        insert into animais (numero, lote_id, sexo, raca, nome, criado_por)
        values (v_num, v_vsa, 'femea', 'nelore', 'ES', 'Planilha IATF out/2026');
        v_cri := v_cri + 1;
      end if;
    end if;

    insert into reproducao_custos (data, lote_id, numero_vaca, raca_touro, qual_inseminacao, custo, item, criado_por)
    values ('2026-10-19', v_vsa, v_num, 'nelore', '1', 46.30, v_chave, 'Planilha IATF out/2026');
    v_ins := v_ins + 1;
    update tmp_iatf4 set numero_final = v_num, acao = 'gravada', situacao = 'OK' where linha = r.linha;
  end loop;

  raise notice 'vacas cadastradas %, inseminacoes gravadas %', v_cri, v_ins;
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, t.linha as sub,
         'linha ' || t.linha || ': ' || t.n || case when t.es then ' ES' else '' end || ' -> vaca ' || coalesce(t.numero_final,'?') as item,
         coalesce(l.nome,'-') || ' | Nome: ' || coalesce(a.nome,'-') as valor, t.situacao
    from tmp_iatf4 t
    left join animais a on a.sexo = 'femea' and lower(trim(a.numero)) = lower(trim(t.numero_final))
    left join lotes l on l.id = a.lote_id
  union all
  select 2, 0, 'TOTAL da planilha no banco',
         count(*)::text || ' de 239 | R$ ' || translate(to_char(coalesce(sum(custo),0), 'FM999G990D00'), ',.', '.,'),
         case when count(*) = 237 then 'OK, faltam 2 (as duas 50 ES)' else 'esperado 237 - confira' end
    from reproducao_custos where item like 'IATF %/10/2026 linha % - touro %'
) z
order by ordem, sub;
