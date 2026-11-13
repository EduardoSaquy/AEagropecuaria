-- Saidas de racao sem lote (13/11/2026), decisao do Eduardo:
--  A) 11, 18 e 23 (23/07, sem dieta e sem lote, sem baixa de estoque): lancadas por engano, saem.
--  B) 49 (ADAP 01, 520 kg): metade Curral 1, metade Curral 2.
--  C) 14 saidas da dieta Sequestro (24 a 29/07): "sao dos bezerros", divididas em partes iguais entre
--     Bez. Conf. Femeas, Bezerros venda e Bezerros machos.
--     A baixa de estoque (movimentos) acompanha: cada parte leva a sua fracao, o total por ingrediente nao muda.
--  D) trava: saida de racao nova so grava com lote e com dieta.
-- As 3 saidas de pasto (703, 1317, 1318) ficam sem lote ate ele dizer o lote.
-- Tudo ou nada. Copias fechadas zz_backup_racao01_*. Desfazer no fim do arquivo.

do $$
declare
  ids_seq bigint[] := array[32,41,56,62,68,74,110,117,123,130,137,143,150,158];
  v_dieta_adap bigint; v_dieta_seq bigint;
  l_c1 bigint; l_c2 bigint; l_fem bigint; l_venda bigint; l_machos bigint;
  r record; mv record; lotes bigint[]; n int; i int; v_novo bigint; v_parte numeric; v_resto numeric;
  v_mparte numeric; v_mresto numeric;
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO: este script e do banco do AE';
  end if;
  if to_regclass('public.zz_backup_racao01_saidas') is not null then
    raise exception 'Ja rodou: a copia zz_backup_racao01_saidas existe. Nada foi alterado.';
  end if;

  select id into v_dieta_adap from dietas where nome = 'ADAP 01';
  select id into v_dieta_seq from dietas where nome = 'Bezerros Confinamento (Sequestro)';
  select id into l_c1 from lotes where nome = 'Curral 1';
  select id into l_c2 from lotes where nome = 'Curral 2';
  select id into l_fem from lotes where nome = 'Bez. Conf. Fêmeas';
  select id into l_venda from lotes where nome = 'Bezerros venda';
  select id into l_machos from lotes where nome = 'Bezerros machos';
  if v_dieta_adap is null or v_dieta_seq is null or l_c1 is null or l_c2 is null or l_fem is null or l_venda is null or l_machos is null then
    raise exception 'Nao achei uma das dietas ou um dos lotes pelo nome. Nada foi alterado.';
  end if;

  -- travas: o estado tem de ser exatamente o que foi conferido
  if (select count(*) from saidas_racao s where s.id in (11,18,23) and s.lote_id is null and s.dieta_id is null
        and not exists (select 1 from movimentos m where m.saida_racao_id = s.id)) <> 3
     or (select coalesce(sum(quantidade_kg),0) from saidas_racao where id in (11,18,23)) <> 1443 then
    raise exception 'As saidas 11, 18 e 23 nao estao como conferido (sem lote, sem dieta, sem baixa, 1443 kg). Nada foi alterado.';
  end if;
  if (select count(*) from saidas_racao where id = 49 and lote_id is null and dieta_id = v_dieta_adap and quantidade_kg = 520) <> 1
     or (select count(*) from movimentos where saida_racao_id = 49) <> 5 then
    raise exception 'A saida 49 nao esta como conferido (ADAP 01, 520 kg, sem lote, 5 baixas). Nada foi alterado.';
  end if;
  if (select count(*) from saidas_racao where id = any(ids_seq) and lote_id is null and dieta_id = v_dieta_seq) <> 14
     or (select sum(quantidade_kg) from saidas_racao where id = any(ids_seq)) <> 6440
     or (select count(*) from movimentos where saida_racao_id = any(ids_seq)) <> 84 then
    raise exception 'As 14 saidas da dieta Sequestro nao estao como conferido (sem lote, 6440 kg, 84 baixas). Nada foi alterado.';
  end if;

  -- copias fechadas
  create table public.zz_backup_racao01_saidas as select * from saidas_racao where id = any(array[11,18,23,49] || ids_seq);
  create table public.zz_backup_racao01_movimentos as select * from movimentos where saida_racao_id = any(array[49] || ids_seq);
  create table public.zz_backup_racao01_novas (saida_racao_id bigint primary key);
  alter table public.zz_backup_racao01_saidas enable row level security;
  alter table public.zz_backup_racao01_movimentos enable row level security;
  alter table public.zz_backup_racao01_novas enable row level security;
  revoke all on public.zz_backup_racao01_saidas, public.zz_backup_racao01_movimentos, public.zz_backup_racao01_novas from anon, authenticated, public;
  if to_regprocedure('public.segundo_fator_ok()') is not null then
    execute 'create policy exige_segundo_fator on public.zz_backup_racao01_saidas as restrictive for all to authenticated using ((select public.segundo_fator_ok()))';
    execute 'create policy exige_segundo_fator on public.zz_backup_racao01_movimentos as restrictive for all to authenticated using ((select public.segundo_fator_ok()))';
    execute 'create policy exige_segundo_fator on public.zz_backup_racao01_novas as restrictive for all to authenticated using ((select public.segundo_fator_ok()))';
  end if;

  -- A) apaga as 3 lancadas por engano
  delete from saidas_racao where id in (11,18,23);

  -- B) e C) divide cada saida em partes iguais entre os lotes
  for r in select s.* from saidas_racao s where s.id = 49 or s.id = any(ids_seq) order by s.id loop
    if r.id = 49 then lotes := array[l_c1, l_c2]; else lotes := array[l_fem, l_venda, l_machos]; end if;
    n := array_length(lotes, 1);
    v_parte := round(r.quantidade_kg / n, 3);
    v_resto := r.quantidade_kg - v_parte * (n - 1);
    -- a propria saida fica com o primeiro lote
    update saidas_racao set lote_id = lotes[1], quantidade_kg = v_parte where id = r.id;
    for i in 2..n loop
      insert into saidas_racao (data, dieta_id, lote_id, quantidade_kg, criado_por, criado_em)
      values (r.data, r.dieta_id, lotes[i], case when i = n then v_resto else v_parte end, r.criado_por, r.criado_em)
      returning id into v_novo;
      insert into zz_backup_racao01_novas values (v_novo);
      for mv in select * from movimentos where saida_racao_id = r.id loop
        v_mparte := round(mv.quantidade / n, 6);
        v_mresto := mv.quantidade - v_mparte * (n - 1);
        insert into movimentos (data, ingrediente_id, tipo, quantidade, saida_racao_id, pasto_id, preco_kg, producao_racao_id, ajuste)
        values (mv.data, mv.ingrediente_id, mv.tipo, case when i = n then v_mresto else v_mparte end, v_novo, mv.pasto_id, mv.preco_kg, mv.producao_racao_id, mv.ajuste);
      end loop;
    end loop;
    update movimentos set quantidade = round(quantidade / n, 6) where saida_racao_id = r.id;
  end loop;
end $$;

-- D) trava: saida nova so com lote e dieta (o app ja exige; isto vale para qualquer caminho)
create or replace function public.saida_racao_exige_lote_e_dieta() returns trigger
language plpgsql set search_path = public as $$
begin
  -- lote ou dieta apagados (on delete set null) nao sao barrados
  if pg_trigger_depth() > 1 then return new; end if;
  -- edicao que nao mexe em lote nem dieta passa (saidas antigas)
  if tg_op = 'UPDATE' and new.lote_id is not distinct from old.lote_id and new.dieta_id is not distinct from old.dieta_id then
    return new;
  end if;
  if new.lote_id is null then
    raise exception 'Saida de racao sem lote: escolha o lote antes de salvar.' using errcode = '23514';
  end if;
  if new.dieta_id is null then
    raise exception 'Saida de racao sem dieta: escolha a dieta antes de salvar.' using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists trg_saida_racao_exige_lote_e_dieta on public.saidas_racao;
create trigger trg_saida_racao_exige_lote_e_dieta before insert or update on public.saidas_racao
  for each row execute function public.saida_racao_exige_lote_e_dieta();

-- Conferencia
with ids as (select unnest(array[32,41,56,62,68,74,110,117,123,130,137,143,150,158,49]) id
             union select saida_racao_id from zz_backup_racao01_novas)
select 'saidas 11, 18 e 23 apagadas' item, (select count(*) from saidas_racao where id in (11,18,23))::text valor,
       case when (select count(*) from saidas_racao where id in (11,18,23)) = 0 then 'OK' else 'ERRO' end situacao
union all select 'kg das saidas divididas (era 6960)', (select sum(quantidade_kg) from saidas_racao where id in (select id from ids))::text,
       case when (select sum(quantidade_kg) from saidas_racao where id in (select id from ids)) = 6960 then 'OK' else 'ERRO' end
union all select 'baixa de estoque igual a antes, ingrediente a ingrediente',
       (select count(*) from (select ingrediente_id, sum(quantidade) q from zz_backup_racao01_movimentos group by 1) a
          full join (select ingrediente_id, sum(quantidade) q from movimentos where saida_racao_id in (select id from ids) group by 1) b using (ingrediente_id)
          where a.q is distinct from b.q)::text || ' diferentes',
       case when (select count(*) from (select ingrediente_id, sum(quantidade) q from zz_backup_racao01_movimentos group by 1) a
          full join (select ingrediente_id, sum(quantidade) q from movimentos where saida_racao_id in (select id from ids) group by 1) b using (ingrediente_id)
          where a.q is distinct from b.q) = 0 then 'OK' else 'ERRO' end
union all select 'cada parte tem baixa que fecha com os kg',
       (select count(*) from saidas_racao s where s.id in (select id from ids)
          and abs((select sum(quantidade) from movimentos m where m.saida_racao_id = s.id) - s.quantidade_kg) > 0.01)::text || ' que nao fecham',
       case when (select count(*) from saidas_racao s where s.id in (select id from ids)
          and abs((select sum(quantidade) from movimentos m where m.saida_racao_id = s.id) - s.quantidade_kg) > 0.01) = 0 then 'OK' else 'ERRO' end
union all select 'Curral 1 / Curral 2 (ADAP 01, kg)',
       (select string_agg(l.nome || ' ' || s.quantidade_kg, ' / ' order by l.nome) from saidas_racao s join lotes l on l.id = s.lote_id
          where s.dieta_id = (select id from dietas where nome = 'ADAP 01') and s.id in (select id from ids)), 'OK'
union all select 'bezerros (Sequestro, kg por lote)',
       (select string_agg(nome || ' ' || kg, ' / ' order by nome) from (select l.nome, sum(s.quantidade_kg) kg from saidas_racao s join lotes l on l.id = s.lote_id
          where s.dieta_id = (select id from dietas where nome = 'Bezerros Confinamento (Sequestro)') and s.id in (select id from ids) group by l.nome) x), 'OK'
union all select 'saidas ainda sem lote (as 3 de pasto)', (select count(*) from saidas_racao where lote_id is null)::text,
       case when (select count(*) from saidas_racao where lote_id is null) = 3 then 'OK' else 'CONFERIR' end
union all select 'trava de lote e dieta instalada', (select count(*) from pg_trigger where tgname = 'trg_saida_racao_exige_lote_e_dieta')::text,
       case when exists (select 1 from pg_trigger where tgname = 'trg_saida_racao_exige_lote_e_dieta') then 'OK' else 'ERRO' end;

/* DESFAZER (so se precisar; rodar sozinho, de uma vez):
drop trigger if exists trg_saida_racao_exige_lote_e_dieta on public.saidas_racao;
drop function if exists public.saida_racao_exige_lote_e_dieta();
delete from movimentos where saida_racao_id in (select saida_racao_id from zz_backup_racao01_novas);
delete from saidas_racao where id in (select saida_racao_id from zz_backup_racao01_novas);
update movimentos m set quantidade = b.quantidade from zz_backup_racao01_movimentos b where b.id = m.id;
update saidas_racao s set lote_id = b.lote_id, quantidade_kg = b.quantidade_kg from zz_backup_racao01_saidas b where b.id = s.id;
insert into saidas_racao select * from zz_backup_racao01_saidas b where b.id in (11,18,23) and not exists (select 1 from saidas_racao s where s.id = b.id);
drop table zz_backup_racao01_saidas, zz_backup_racao01_movimentos, zz_backup_racao01_novas;
*/
