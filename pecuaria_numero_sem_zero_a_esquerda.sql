-- ============================================================
-- Pecuaria - numero do animal sem zero a esquerda (Eduardo,
-- 02/11/2026: "57 e 057 sao o mesmo animal, zero a esquerda nao
-- conta"). Troca 057 por 57 no cadastro (animais) e em todo
-- lancamento que guarda o numero: partos, inseminacoes,
-- diagnosticos, pesagens por animal e protocolos de inseminacao.
-- O app novo ja tira o zero ao digitar.
--
-- Para SEM MUDAR NADA se a troca juntar dois animais do mesmo sexo
-- (ex.: ja existe a 57 e a 057 femeas): lista quais sao.
-- Repetivel (na segunda vez nao acha mais nada para trocar).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

do $$
declare v_conflito text;
begin
  select string_agg(numeros || ' (' || coalesce(sexo,'sem sexo') || ')', '; ') into v_conflito
    from (select sexo, string_agg(numero, ' e ' order by numero) as numeros
            from animais
           group by sexo, coalesce(nullif(ltrim(trim(numero),'0'),''),'0')
          having count(*) > 1
             and bool_or(trim(numero) ~ '^0+[0-9]+$')) x;
  if v_conflito is not null then
    raise exception 'Nada foi trocado: estes animais virariam o mesmo numero: %. Diga se sao o mesmo animal.', v_conflito;
  end if;
end $$;

drop table if exists tmp_zeros;
create temp table tmp_zeros (tabela text, trocados int);

do $$
declare n int;
begin
  update animais set numero = regexp_replace(trim(numero), '^0+(?=[0-9])', '') where trim(numero) ~ '^0+[0-9]+$';
  get diagnostics n = row_count; insert into tmp_zeros values ('animais', n);
  update partos set numero_mae = regexp_replace(trim(numero_mae), '^0+(?=[0-9])', '') where trim(numero_mae) ~ '^0+[0-9]+$';
  get diagnostics n = row_count; insert into tmp_zeros values ('partos', n);
  update reproducao_custos set numero_vaca = regexp_replace(trim(numero_vaca), '^0+(?=[0-9])', '') where trim(numero_vaca) ~ '^0+[0-9]+$';
  get diagnostics n = row_count; insert into tmp_zeros values ('reproducao_custos', n);
  update diagnosticos_gestacionais set numero_vaca = regexp_replace(trim(numero_vaca), '^0+(?=[0-9])', '') where trim(numero_vaca) ~ '^0+[0-9]+$';
  get diagnostics n = row_count; insert into tmp_zeros values ('diagnosticos_gestacionais', n);
  update pesagens_animais set numero_animal = regexp_replace(trim(numero_animal), '^0+(?=[0-9])', '') where trim(numero_animal) ~ '^0+[0-9]+$';
  get diagnostics n = row_count; insert into tmp_zeros values ('pesagens_animais', n);
  update protocolos_inseminacao set numero_animal = regexp_replace(trim(numero_animal), '^0+(?=[0-9])', '') where trim(numero_animal) ~ '^0+[0-9]+$';
  get diagnostics n = row_count; insert into tmp_zeros values ('protocolos_inseminacao', n);
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, 'trocados agora em ' || tabela as item, trocados::text as valor, 'OK' as situacao from tmp_zeros
  union all
  select 2, 'ainda com zero a esquerda (todas as tabelas)',
         (select count(*) from animais where trim(numero) ~ '^0+[0-9]+$')
       + (select count(*) from partos where trim(numero_mae) ~ '^0+[0-9]+$')
       + (select count(*) from reproducao_custos where trim(numero_vaca) ~ '^0+[0-9]+$')
       + (select count(*) from diagnosticos_gestacionais where trim(numero_vaca) ~ '^0+[0-9]+$')
       + (select count(*) from pesagens_animais where trim(numero_animal) ~ '^0+[0-9]+$')
       + (select count(*) from protocolos_inseminacao where trim(numero_animal) ~ '^0+[0-9]+$') || '',
         'deve ser 0'
) z
order by ordem, item;
