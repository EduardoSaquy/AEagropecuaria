-- ============================================================
-- Pecuaria - unifica os 13 partos lancados em dobro e completa a raca
-- das vacas em branco (27/10/2026).
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Decisao do Eduardo (27/10/2026): os partos repetidos da mesma vaca no
-- mesmo lote sao lancamento em dobro (nao ha gemeos) e podem ser
-- unificados. Fica o lancamento mais antigo (o lote de 27/10 veio todo
-- com a data do dia); na 316 fica o de 26/09 (o de 22/09 nao tem autor).
--   025: fica 175, sai 181      095: fica 140, sai 146
--   032: fica 174, sai 180      305: fica 126, sai 137
--   069: fica 176, sai 182      316: fica 152, saem 153 e 159
--   090: fica 177, sai 183      388: fica 68,  sai 110
--   694: fica 190, sai 222      335: fica 54,  sai 83
--   741: fica 185, sai 202      713: fica 189, sai 220
-- Unificar: o que fica herda raca/sexo do bezerro que estiver em branco
-- nele e preenchido no que sai; desmama do que sai passa para o que fica
-- (se o que fica nao tiver). Cada par so e mexido se os dois partos forem
-- da mesma vaca no mesmo lote; senao fica PENDENTE sem mudar nada.
-- Tambem: vaca (femea) com raca em branco vira nelore (decisao do Eduardo).
-- Repetivel. Termina com a conferencia, que lista o parto sem lote que
-- ainda sobrou.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

create temp table if not exists unifica_partos (ordem int, item text, valor text, situacao text);
truncate unifica_partos;

do $$
declare
  par record;
  fica record;
  sai record;
  n int;
begin
  for par in
    select * from (values
      ('025', 175, 181), ('032', 174, 180), ('069', 176, 182), ('090', 177, 183),
      ('095', 140, 146), ('305', 126, 137), ('316', 152, 153), ('316', 152, 159),
      ('388', 68, 110), ('694', 190, 222), ('741', 185, 202), ('335', 54, 83),
      ('713', 189, 220)
    ) v(vaca, id_fica, id_sai)
  loop
    select * into fica from partos where id = par.id_fica;
    select * into sai from partos where id = par.id_sai;
    if sai.id is null then
      if fica.id is not null then
        insert into unifica_partos values (1, 'vaca ' || par.vaca, 'parto ' || par.id_sai || ' ja tinha saido', 'OK');
      else
        insert into unifica_partos values (3, 'PENDENTE vaca ' || par.vaca, 'nao achei os partos ' || par.id_fica || ' e ' || par.id_sai, 'conferir; nada foi mudado');
      end if;
      continue;
    end if;
    if fica.id is null
       or ltrim(lower(trim(fica.numero_mae)), '0') <> ltrim(par.vaca, '0')
       or ltrim(lower(trim(sai.numero_mae)), '0') <> ltrim(par.vaca, '0')
       or fica.lote_id is distinct from sai.lote_id then
      insert into unifica_partos values (3, 'PENDENTE vaca ' || par.vaca,
        'partos ' || par.id_fica || ' e ' || par.id_sai || ' nao sao da mesma vaca no mesmo lote', 'conferir; nada foi mudado');
      continue;
    end if;

    if exists (select 1 from desmamas where parto_id = sai.id)
       and exists (select 1 from desmamas where parto_id = fica.id) then
      insert into unifica_partos values (3, 'PENDENTE vaca ' || par.vaca,
        'os dois partos tem desmama', 'conferir; nada foi mudado');
      continue;
    end if;
    -- o que fica herda o que estiver em branco nele
    if fica.tipo = 'nascimento' and sai.tipo = 'nascimento' then
      update partos
         set raca_bezerro = coalesce(raca_bezerro, sai.raca_bezerro),
             sexo_bezerro = coalesce(sexo_bezerro, sai.sexo_bezerro)
       where id = fica.id;
    end if;
    -- desmama do que sai vai para o que fica
    update desmamas set parto_id = fica.id where parto_id = sai.id;

    delete from partos where id = sai.id;
    insert into unifica_partos values (1, 'vaca ' || par.vaca,
      'fica ' || fica.id || ' (' || to_char(fica.data, 'DD/MM/YYYY') || '), saiu ' || sai.id || ' (' || to_char(sai.data, 'DD/MM/YYYY') || ')', 'OK');
  end loop;

  -- vaca com raca em branco vira nelore
  update animais set raca = 'nelore'
   where sexo = 'femea' and coalesce(trim(raca), '') = '';
  get diagnostics n = row_count;
  insert into unifica_partos values (2, 'vacas com raca em branco', n || ' passaram a nelore', 'OK');
end $$;

-- ============================================================
-- conferencia
-- ============================================================
with repetidos as (
  select lote_id, lower(trim(numero_mae)) as num, count(*) as qtd
    from partos
   where coalesce(trim(numero_mae), '') <> ''
   group by 1, 2
  having count(*) > 1
),
resumo as (
  select trim(l.nome) as nome, coalesce(l.numero_animais, 0) as cabecas,
         (select count(*) from partos p where p.lote_id = l.id) as partos,
         (select count(distinct lower(trim(p.numero_mae))) from partos p where p.lote_id = l.id) as vacas
    from lotes l
   where exists (select 1 from partos p where p.lote_id = l.id)
)
select ordem, item, valor, situacao from unifica_partos
union all
select 4, 'vacas com parto repetido no mesmo lote',
       (select count(*) from repetidos)::text,
       case when not exists (select 1 from repetidos) then 'OK' else 'CONFERIR' end
union all
select 5, 'lote ' || r.nome,
       'cabecas: ' || r.cabecas || ' | partos: ' || r.partos || ' | vacas que pariram: ' || r.vacas,
       case when r.partos <> r.vacas then 'CONFERIR: parto repetido'
            when r.vacas > r.cabecas then 'CONFERIR: mais vacas paridas que cabecas'
            else 'OK' end
  from resumo r
union all
select 6, 'parto sem lote: id ' || p.id,
       'vaca ' || coalesce(p.numero_mae, '?') || ', ' || to_char(p.data, 'DD/MM/YYYY') || ', lancado por ' || coalesce(p.criado_por, '?'),
       'dizer em qual lote fica'
  from partos p
 where p.lote_id is null
union all
select 7, 'vacas (femeas) ainda sem raca',
       (select count(*) from animais where sexo = 'femea' and coalesce(trim(raca), '') = '')::text,
       case when (select count(*) from animais where sexo = 'femea' and coalesce(trim(raca), '') = '') = 0 then 'OK' else 'CONFERIR' end
order by 1, 2;
