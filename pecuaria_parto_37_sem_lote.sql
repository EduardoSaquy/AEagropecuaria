-- ============================================================
-- Pecuaria - parto id 1 (vaca 37, 23/07/2026) sem lote (27/10/2026).
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Regra do Eduardo: se o bezerro morreu (obito registrado no parto), o
-- parto e do Vacas Vazias Santa Alice; se nao morreu, e do Vacas 07/08.
-- Antes de gravar, confere se a vaca 37 ja tem outro parto nesse lote a
-- menos de 240 dias (seria lancamento em dobro): nesse caso nao muda
-- nada e mostra os dois. Mostra tambem onde esta o cadastro da vaca 37.
-- Repetivel.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

create temp table if not exists parto_37 (ordem int, item text, valor text, situacao text);
truncate parto_37;

do $$
declare
  p        record;
  v_0708   bigint;
  v_vazia  bigint;
  v_dest   bigint;
  v_qtd    int;
  outro    record;
begin
  select count(*), min(id) into v_qtd, v_0708 from lotes where lower(trim(nome)) = 'vacas 07/08';
  if v_qtd <> 1 then
    raise exception 'esperava 1 lote Vacas 07/08, achei % - nada feito', v_qtd;
  end if;
  select count(*), min(id) into v_qtd, v_vazia from lotes where lower(trim(nome)) like '%vazia%santa alice%';
  if v_qtd <> 1 then
    raise exception 'esperava 1 lote Vacas Vazias Santa Alice, achei % - nada feito', v_qtd;
  end if;

  select * into p from partos where id = 1;
  if p.id is null then
    insert into parto_37 values (1, 'parto id 1', 'nao existe mais', 'OK');
    return;
  end if;
  if p.lote_id is not null then
    insert into parto_37 values (1, 'parto id 1', 'ja esta no lote ' || (select trim(nome) from lotes where id = p.lote_id), 'OK');
    return;
  end if;
  if ltrim(lower(trim(p.numero_mae)), '0') <> '37' then
    insert into parto_37 values (3, 'PENDENTE parto id 1', 'a mae e ' || coalesce(p.numero_mae, '?') || ', nao a 37', 'conferir; nada foi mudado');
    return;
  end if;

  v_dest := case when p.data_obito is not null then v_vazia else v_0708 end;

  select * into outro from partos o
   where o.id <> p.id and o.lote_id = v_dest
     and ltrim(lower(trim(o.numero_mae)), '0') = '37'
     and abs(o.data - p.data) < 240
   order by o.data limit 1;
  if outro.id is not null then
    insert into parto_37 values (3, 'PENDENTE parto id 1 (vaca 37, ' || to_char(p.data, 'DD/MM/YYYY') || ')',
      'a 37 ja tem o parto id ' || outro.id || ' em ' || to_char(outro.data, 'DD/MM/YYYY') || ' no ' || (select trim(nome) from lotes where id = v_dest),
      'lancamento em dobro: dizer qual fica; nada foi mudado');
    return;
  end if;

  update partos set lote_id = v_dest where id = p.id;
  insert into parto_37 values (1, 'parto id 1 (vaca 37, ' || to_char(p.data, 'DD/MM/YYYY') || ')',
    case when p.data_obito is not null
         then 'bezerro morreu em ' || to_char(p.data_obito, 'DD/MM/YYYY') || ' -> Vacas Vazias Santa Alice'
         else 'bezerro sem obito registrado (vivo) -> Vacas 07/08' end,
    'OK');
end $$;

select ordem, item, valor, situacao from parto_37
union all
select 4, 'partos da vaca 37',
       coalesce((select string_agg('id ' || p.id || ' em ' || to_char(p.data, 'DD/MM/YYYY') || ' no '
                                   || coalesce(trim(l.nome), 'sem lote')
                                   || case when p.tipo = 'aborto' then ' (aborto)'
                                           when p.data_obito is not null then ' (bezerro morto)'
                                           else '' end, ' | ' order by p.data)
                   from partos p left join lotes l on l.id = p.lote_id
                  where ltrim(lower(trim(p.numero_mae)), '0') = '37'), 'nenhum'),
       'OK'
union all
select 5, 'cadastro da vaca 37',
       coalesce((select string_agg(a.numero || ' no ' || coalesce(trim(l.nome), 'sem lote') || ', nome: ' || coalesce(a.nome, '-'), ' | ')
                   from animais a left join lotes l on l.id = a.lote_id
                  where a.sexo = 'femea' and ltrim(lower(trim(a.numero)), '0') = '37'), 'sem cadastro'),
       'OK'
union all
select 6, 'partos sem lote',
       (select count(*) from partos where lote_id is null)::text,
       case when (select count(*) from partos where lote_id is null) = 0 then 'OK' else 'CONFERIR' end
order by 1, 2;
