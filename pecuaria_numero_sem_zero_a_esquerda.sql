-- ============================================================
-- Pecuaria - numero do animal sem zero a esquerda (Eduardo,
-- 02/11/2026: "57 e 057 sao o mesmo animal, zero a esquerda nao
-- conta"). Troca 057 por 57 no cadastro (animais) e em todo
-- lancamento que guarda o numero: partos, inseminacoes,
-- diagnosticos, pesagens por animal e protocolos de inseminacao.
-- O app novo ja tira o zero ao digitar.
--
-- Se a troca juntar dois animais do mesmo sexo: o de lote encerrado
-- fica com o zero (bois 001/002/003 dos Currais 1 e 2 x bezerros
-- 1/2/3 Alice); se os dois estiverem em lote ativo, para sem mudar
-- nada e lista quais sao.
-- Repetivel (na segunda vez nao acha mais nada para trocar).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

-- Numero com zero que, sem o zero, ficaria igual ao de outro animal do
-- mesmo sexo: se o animal com zero esta em lote ENCERRADO (vendido, ex.
-- bois 001/002/003 dos Currais 1 e 2), ele e o historico dele ficam como
-- estao (sao outros animais, nao os bezerros 1/2/3). Se os dois estao em
-- lote ativo, para sem mudar nada e lista quais sao.
drop table if exists tmp_manter;
create temp table tmp_manter as
select distinct trim(a.numero) as numero, a.sexo
  from animais a
  join animais b on b.id <> a.id and b.sexo is not distinct from a.sexo
                and coalesce(nullif(ltrim(trim(b.numero),'0'),''),'0') = coalesce(nullif(ltrim(trim(a.numero),'0'),''),'0')
 where trim(a.numero) ~ '^0+[0-9]+$';

do $$
declare v_conflito text;
begin
  select string_agg(m.numero || ' (' || coalesce(m.sexo,'sem sexo') || ', lote ' || coalesce(l.nome,'nenhum') || ')', '; ') into v_conflito
    from tmp_manter m
    join animais a on trim(a.numero) = m.numero and a.sexo is not distinct from m.sexo
    left join lotes l on l.id = a.lote_id
   where l.id is null or l.data_fim is null;
  if v_conflito is not null then
    raise exception 'Nada foi trocado: sem o zero estes animais ficariam com o numero de outro animal, e estao em lote ativo: %. Diga se sao o mesmo animal.', v_conflito;
  end if;
end $$;

drop table if exists tmp_zeros;
create temp table tmp_zeros (tabela text, trocados int);

do $$
declare n int;
begin
  update animais set numero = regexp_replace(trim(numero), '^0+(?=[0-9])', '') where trim(numero) ~ '^0+[0-9]+$'
     and not exists (select 1 from tmp_manter m where m.numero = trim(animais.numero) and m.sexo is not distinct from animais.sexo);
  get diagnostics n = row_count; insert into tmp_zeros values ('animais', n);
  update partos set numero_mae = regexp_replace(trim(numero_mae), '^0+(?=[0-9])', '') where trim(numero_mae) ~ '^0+[0-9]+$'
     and trim(numero_mae) not in (select numero from tmp_manter);
  get diagnostics n = row_count; insert into tmp_zeros values ('partos', n);
  update reproducao_custos set numero_vaca = regexp_replace(trim(numero_vaca), '^0+(?=[0-9])', '') where trim(numero_vaca) ~ '^0+[0-9]+$'
     and trim(numero_vaca) not in (select numero from tmp_manter);
  get diagnostics n = row_count; insert into tmp_zeros values ('reproducao_custos', n);
  update diagnosticos_gestacionais set numero_vaca = regexp_replace(trim(numero_vaca), '^0+(?=[0-9])', '') where trim(numero_vaca) ~ '^0+[0-9]+$'
     and trim(numero_vaca) not in (select numero from tmp_manter);
  get diagnostics n = row_count; insert into tmp_zeros values ('diagnosticos_gestacionais', n);
  update pesagens_animais set numero_animal = regexp_replace(trim(numero_animal), '^0+(?=[0-9])', '') where trim(numero_animal) ~ '^0+[0-9]+$'
     and trim(numero_animal) not in (select numero from tmp_manter);
  get diagnostics n = row_count; insert into tmp_zeros values ('pesagens_animais', n);
  update protocolos_inseminacao set numero_animal = regexp_replace(trim(numero_animal), '^0+(?=[0-9])', '') where trim(numero_animal) ~ '^0+[0-9]+$'
     and trim(numero_animal) not in (select numero from tmp_manter);
  get diagnostics n = row_count; insert into tmp_zeros values ('protocolos_inseminacao', n);
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, 'trocados agora em ' || tabela as item, trocados::text as valor, 'OK' as situacao from tmp_zeros
  union all
  select 2, 'mantidos com zero (lote encerrado, outro animal tem o mesmo numero sem zero)',
         coalesce(string_agg(numero || ' ' || coalesce(sexo,''), ', ' order by numero), 'nenhum'), 'OK' from tmp_manter
  union all
  select 3, 'ainda com zero a esquerda, fora os mantidos',
         ((select count(*) from animais where trim(numero) ~ '^0+[0-9]+$' and trim(numero) not in (select numero from tmp_manter))
       + (select count(*) from partos where trim(numero_mae) ~ '^0+[0-9]+$' and trim(numero_mae) not in (select numero from tmp_manter))
       + (select count(*) from reproducao_custos where trim(numero_vaca) ~ '^0+[0-9]+$' and trim(numero_vaca) not in (select numero from tmp_manter))
       + (select count(*) from diagnosticos_gestacionais where trim(numero_vaca) ~ '^0+[0-9]+$' and trim(numero_vaca) not in (select numero from tmp_manter))
       + (select count(*) from pesagens_animais where trim(numero_animal) ~ '^0+[0-9]+$' and trim(numero_animal) not in (select numero from tmp_manter))
       + (select count(*) from protocolos_inseminacao where trim(numero_animal) ~ '^0+[0-9]+$' and trim(numero_animal) not in (select numero from tmp_manter)))::text,
         'deve ser 0'
) z
order by ordem, item;
