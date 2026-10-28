-- ============================================================
-- Pecuaria - vaca 37: parto id 1 (23/07/2026, sem lote) e parto id 57
-- (13/08/2026, Vacas 07/08) sao o mesmo parto lancado duas vezes
-- (27/10/2026).
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Mesma regra dos outros duplicados (decisao do Eduardo): fica o
-- lancamento mais antigo, o id 1 (23/07/2026), no lote da vaca e do
-- outro parto, Vacas 07/08 (bezerro sem obito). Ele herda raca/sexo do
-- bezerro em branco e a desmama do id 57, que sai.
-- So mexe se os dois forem da vaca 37; senao nao muda nada.
-- Repetivel.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

create temp table if not exists parto_37b (ordem int, item text, valor text, situacao text);
truncate parto_37b;

do $$
declare
  fica   record;
  sai    record;
  v_0708 bigint;
  v_qtd  int;
begin
  select count(*), min(id) into v_qtd, v_0708 from lotes where lower(trim(nome)) = 'vacas 07/08';
  if v_qtd <> 1 then
    raise exception 'esperava 1 lote Vacas 07/08, achei % - nada feito', v_qtd;
  end if;

  select * into fica from partos where id = 1;
  select * into sai from partos where id = 57;

  if fica.id is null then
    insert into parto_37b values (3, 'PENDENTE', 'nao achei o parto id 1', 'conferir; nada foi mudado');
    return;
  end if;
  if ltrim(lower(trim(fica.numero_mae)), '0') <> '37' then
    insert into parto_37b values (3, 'PENDENTE', 'o parto id 1 nao e da vaca 37', 'conferir; nada foi mudado');
    return;
  end if;

  if sai.id is not null then
    if ltrim(lower(trim(sai.numero_mae)), '0') <> '37' then
      insert into parto_37b values (3, 'PENDENTE', 'o parto id 57 nao e da vaca 37', 'conferir; nada foi mudado');
      return;
    end if;
    if exists (select 1 from desmamas where parto_id = sai.id)
       and exists (select 1 from desmamas where parto_id = fica.id) then
      insert into parto_37b values (3, 'PENDENTE', 'os dois partos tem desmama', 'conferir; nada foi mudado');
      return;
    end if;
    if fica.tipo = 'nascimento' and sai.tipo = 'nascimento' then
      update partos
         set raca_bezerro = coalesce(raca_bezerro, sai.raca_bezerro),
             sexo_bezerro = coalesce(sexo_bezerro, sai.sexo_bezerro)
       where id = fica.id;
    end if;
    update desmamas set parto_id = fica.id where parto_id = sai.id;
    delete from partos where id = sai.id;
    insert into parto_37b values (1, 'vaca 37', 'saiu o parto id 57 (' || to_char(sai.data, 'DD/MM/YYYY') || ')', 'OK');
  end if;

  if fica.lote_id is distinct from v_0708 then
    update partos set lote_id = v_0708 where id = fica.id;
  end if;
  insert into parto_37b values (1, 'vaca 37', 'fica o parto id 1 (' || to_char(fica.data, 'DD/MM/YYYY') || ') no Vacas 07/08', 'OK');
end $$;

select ordem, item, valor, situacao from parto_37b
union all
select 4, 'partos da vaca 37',
       coalesce((select string_agg('id ' || p.id || ' em ' || to_char(p.data, 'DD/MM/YYYY') || ' no '
                                   || coalesce(trim(l.nome), 'sem lote')
                                   || ', bezerro ' || coalesce(p.sexo_bezerro, 'sem sexo')
                                   || case when exists (select 1 from desmamas d where d.parto_id = p.id) then ', desmamado' else '' end,
                                   ' | ' order by p.data)
                   from partos p left join lotes l on l.id = p.lote_id
                  where ltrim(lower(trim(p.numero_mae)), '0') = '37'), 'nenhum'),
       case when (select count(*) from partos where ltrim(lower(trim(numero_mae)), '0') = '37') = 1 then 'OK' else 'CONFERIR' end
union all
select 5, 'partos sem lote',
       (select count(*) from partos where lote_id is null)::text,
       case when (select count(*) from partos where lote_id is null) = 0 then 'OK' else 'CONFERIR' end
union all
select 6, 'vacas com parto repetido no mesmo lote',
       (select count(*) from (select lote_id, lower(trim(numero_mae)) from partos
                               where coalesce(trim(numero_mae), '') <> ''
                               group by 1, 2 having count(*) > 1) x)::text,
       case when exists (select 1 from partos where coalesce(trim(numero_mae), '') <> ''
                          group by lote_id, lower(trim(numero_mae)) having count(*) > 1)
            then 'CONFERIR' else 'OK' end
order by 1, 2;
