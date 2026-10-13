-- ============================================================
-- Pecuaria - bezerros da Invernada, pesagem de 10/10/2026:
-- o bezerro de 305 kg (folha TER) foi gravado como 300, mas 300 e
-- um macho adulto do Curral 2 (ficha certa, confirmado pelo
-- Eduardo). Eduardo definiu o numero 302 pro bezerro.
--
-- 1) troca 300 -> 302 na linha de 305 kg da pesagem de 10/10/2026
--    do lote de bezerros da Invernada (so essa linha);
-- 2) cria a ficha 302 macho/nelore nesse lote.
-- Nao mexe no 300 do Curral 2.
--
-- Para (nada gravado) se ja existir macho 302 em qualquer lote.
-- Repetivel: se a pesagem ja tiver o 302, nao faz nada.
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
  v_lote_id     bigint;
  v_lotes       int;
  v_pesagem_id  bigint;
  v_linhas      int;
  v_ocupado     text;
begin
  select count(*), min(id) into v_lotes, v_lote_id
    from lotes where trim(nome) ilike '%bezerr%invernada%';
  if v_lotes <> 1 then
    raise exception 'esperava 1 lote de bezerros da Invernada, achei % - nada feito', v_lotes;
  end if;

  select id into v_pesagem_id from pesagens where lote_id = v_lote_id and data = '2026-10-10';
  if v_pesagem_id is null then
    raise exception 'pesagem de 10/10/2026 do lote nao encontrada - nada feito';
  end if;

  if exists (select 1 from pesagens_animais
              where pesagem_id = v_pesagem_id and trim(numero_animal) = '302') then
    raise notice 'a pesagem ja tem o 302 - nada feito';
    return;
  end if;

  select coalesce(l.nome, '(sem lote)') into v_ocupado
    from animais a left join lotes l on l.id = a.lote_id
   where lower(trim(a.numero)) = '302' and a.sexo = 'macho'
   limit 1;
  if v_ocupado is not null then
    raise exception 'ja existe macho 302 cadastrado (lote %) - nada feito, escolha outro numero', v_ocupado;
  end if;

  update pesagens_animais
     set numero_animal = '302'
   where pesagem_id = v_pesagem_id and trim(numero_animal) = '300' and peso_kg = 305;
  get diagnostics v_linhas = row_count;
  if v_linhas <> 1 then
    raise exception 'esperava 1 linha 300 com 305 kg nessa pesagem, achei % - nada feito', v_linhas;
  end if;

  insert into animais (numero, lote_id, sexo, raca, criado_por)
  values ('302', v_lote_id, 'macho', 'nelore',
          'Eduardo (cadastro via SQL a partir da pesagem de 10/10/2026)');

  raise notice 'pesagem corrigida (300 -> 302, 305 kg) e ficha 302 macho/nelore criada no lote id %', v_lote_id;
end $$;

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, '302 na pesagem de 10/10/2026 (deve ter 305 kg)' as item,
       coalesce(string_agg(pa.peso_kg::text || ' kg', ', '), 'nao encontrado') as valor,
       case when count(*) = 1 and max(pa.peso_kg) = 305 then 'OK' else 'confira' end as situacao
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and trim(pa.numero_animal) = '302'
union all
select 2, '300 que sobrou na pesagem de 10/10/2026',
       count(*)::text,
       case when count(*) = 0 then 'OK, nenhum' else 'ainda tem 300 na pesagem - confira' end
  from pesagens p join lotes l on l.id = p.lote_id
  join pesagens_animais pa on pa.pesagem_id = p.id
 where trim(l.nome) ilike '%bezerr%invernada%' and p.data = '2026-10-10'
   and trim(pa.numero_animal) = '300'
union all
select 3, 'ficha 302 macho',
       coalesce(string_agg(l.nome, ', '), 'nao encontrada'),
       case when count(*) = 1 and bool_and(l.nome ilike '%bezerr%invernada%') then 'OK' else 'confira' end
  from animais a join lotes l on l.id = a.lote_id
 where lower(trim(a.numero)) = '302' and a.sexo = 'macho'
union all
select 4, 'ficha 300 macho (Curral 2, nao pode ter mudado)',
       coalesce(string_agg(l.nome, ', '), 'nao encontrada'),
       case when count(*) = 1 and bool_and(l.nome ilike 'Curral 2') then 'OK, intocado' else 'confira' end
  from animais a join lotes l on l.id = a.lote_id
 where lower(trim(a.numero)) = '300' and a.sexo = 'macho'
order by 1;
