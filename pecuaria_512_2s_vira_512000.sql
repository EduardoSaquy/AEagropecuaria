-- ============================================================
-- Pecuaria - bezerro "512 2S" (Bezerros Invernada) vira 512000.
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Decisao do Eduardo (27/10/2026): o numero ja era do macho adulto 512
-- do Curral 2 (vendido, sai em 28/10/2026, mas o historico de pesagem
-- dele continua com o 512). O bezerro passa a 512000 e a marca 2S vai
-- para o Nome. Troca o cadastro e as pesagens por animal dele.
-- Para sem mudar nada se nao achar exatamente um macho 512 2S ou se o
-- 512000 ja for de outro animal. Repetivel: rodar de novo nao muda nada.
-- ============================================================

do $$
declare
  v_id  bigint;
  v_qtd int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'animais' and column_name = 'nome') then
    raise exception 'Rode antes o pecuaria_parto_aborto_obito_nome_animal.sql (falta animais.nome).';
  end if;

  select count(*), min(id) into v_qtd, v_id
    from animais where lower(trim(numero)) = '512 2s' and sexo = 'macho';
  if v_qtd = 0 then
    if exists (select 1 from animais where numero = '512000' and sexo = 'macho') then
      raise notice 'ja feito antes: o 512000 existe e nao ha mais 512 2S';
      return;
    end if;
    raise exception 'nao achei o macho 512 2S - nada feito';
  end if;
  if v_qtd > 1 then
    raise exception 'achei % machos 512 2S - nada feito', v_qtd;
  end if;
  if exists (select 1 from animais where id <> v_id and lower(trim(numero)) = '512000') then
    raise exception 'ja existe outro animal 512000 - nada feito, escolha outro numero';
  end if;

  update animais
     set numero = '512000',
         nome = case when coalesce(trim(nome), '') = '' then '2S'
                     when position('2s' in lower(nome)) > 0 then nome
                     else nome || ' / 2S' end
   where id = v_id;
  update pesagens_animais set numero_animal = '512000' where lower(trim(numero_animal)) = '512 2s';
  update partos set numero_mae = '512000' where lower(trim(numero_mae)) = '512 2s';
  update diagnosticos_gestacionais set numero_vaca = '512000' where lower(trim(numero_vaca)) = '512 2s';
  update reproducao_custos set numero_vaca = '512000' where lower(trim(numero_vaca)) = '512 2s';
  update protocolos_inseminacao set numero_animal = '512000' where lower(trim(numero_animal)) = '512 2s';
end $$;

-- conferencia
select 1 as ordem, 'animal 512000' as item,
       coalesce((select string_agg(a.sexo || ', ' || coalesce(l.nome, 'sem lote') || ', nome: ' || coalesce(a.nome, '-'), ' | ')
                   from animais a left join lotes l on l.id = a.lote_id
                  where a.numero = '512000'), 'nao encontrado') as valor,
       case when (select count(*) from animais where numero = '512000') = 1 then 'OK' else 'CONFERIR' end as situacao
union all
select 2, 'pesagens por animal do 512000',
       (select count(*) from pesagens_animais where numero_animal = '512000')::text,
       case when (select count(*) from pesagens_animais where numero_animal = '512000') > 0 then 'OK' else 'CONFERIR (esperava a pesagem de 10/10/2026)' end
union all
select 3, 'ainda com 512 2S (qualquer tabela)',
       ((select count(*) from animais where lower(trim(numero)) = '512 2s')
        + (select count(*) from pesagens_animais where lower(trim(numero_animal)) = '512 2s'))::text,
       case when (select count(*) from animais where lower(trim(numero)) = '512 2s')
               + (select count(*) from pesagens_animais where lower(trim(numero_animal)) = '512 2s') = 0
            then 'OK' else 'CONFERIR' end
union all
select 4, '512 do Curral 2 (nao mexido)',
       coalesce((select string_agg(coalesce(l.nome, 'sem lote') || ', ' || a.status, ' | ')
                   from animais a left join lotes l on l.id = a.lote_id
                  where a.numero = '512' and a.sexo = 'macho'), 'nao encontrado'),
       'OK'
order by 1;
