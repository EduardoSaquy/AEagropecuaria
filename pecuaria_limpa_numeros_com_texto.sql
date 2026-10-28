-- ============================================================
-- Pecuaria - limpeza dos numeros de animal com texto (27/10/2026).
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz), DEPOIS de
-- pecuaria_parto_aborto_obito_nome_animal.sql. Cole inteiro e rode.
--
-- Decisao do Eduardo (27/10/2026): o numero do animal fica so com
-- algarismos e o texto vai para animais.nome (Alice, 2S, ES e a
-- observacao da vaca 351). O que era um evento escrito no numero vira
-- o lancamento certo:
--   721 abortou          parto 197 vira aborto da vaca 721; o cadastro
--                        "721 abortou" (duplicado, criado pelo parto) sai
--   368 e 370 pariu morto  nascimento com obito no dia, causa nasceu morto
-- Espaco sobrando em volta de numero (ex.: "721 ") sai.
--
-- Trava: um numero so e trocado se nao existir outro animal do mesmo
-- sexo com ele (senao dois animais virariam um so). O que nao der fica
-- PENDENTE na lista do fim, sem mudar nada dele (previsto: "512 2S",
-- porque ja existe o 512 macho do Curral 2).
-- Repetivel: rodar de novo so mexe no que ainda estiver com texto.
-- Termina com a lista item / valor / situacao do que fez e do que falta.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'animais' and column_name = 'nome')
     or not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'partos' and column_name = 'tipo') then
    raise exception 'Rode antes o pecuaria_parto_aborto_obito_nome_animal.sql (faltam animais.nome ou partos.tipo).';
  end if;
end $$;

create temp table if not exists limpeza_numeros (ordem int, item text, valor text, situacao text);
truncate limpeza_numeros;

do $$
declare
  m record;
  a record;
  conflito int;
  pendente boolean;
  n int;
  total int;
  -- indice antigo so por numero (sem sexo), se ainda existir, vale mais
  so_numero boolean := exists (select 1 from pg_indexes
                                where schemaname = 'public' and tablename = 'animais'
                                  and indexname = 'animais_numero_ci_unique');
begin
  -- ---------- 1) numero + texto que vira nome ----------
  for m in
    select * from (values
      ('19 es',  '19',  'ES'),
      ('37 es',  '37',  'ES'),
      ('351 n' || chr(227) || 'o quis o bezerro descarte', '351', 'n' || chr(227) || 'o quis o bezerro - descarte'),
      ('512 2s', '512', '2S'),
      ('alice 1', '1', 'Alice'),
      ('alice 2', '2', 'Alice'),
      ('alice 3', '3', 'Alice'),
      ('alice 4', '4', 'Alice')
    ) v(antigo, numero, nome)
  loop
    pendente := false;
    for a in select * from animais where lower(trim(numero)) = m.antigo loop
      select count(*) into conflito from animais o
       where o.id <> a.id and lower(trim(o.numero)) = m.numero
         and (so_numero or o.sexo is not distinct from a.sexo);
      if conflito > 0 then
        pendente := true;
        insert into limpeza_numeros values (3, 'PENDENTE animal "' || a.numero || '" (' || coalesce(a.sexo, 'sem sexo') || ')',
          'ja existe outro animal ' || m.numero || ' do mesmo sexo', 'escolher outro numero para ele; nada foi mudado');
      else
        update animais
           set numero = m.numero,
               nome = case when coalesce(trim(nome), '') = '' then m.nome
                           when position(lower(m.nome) in lower(nome)) > 0 then nome
                           else nome || ' / ' || m.nome end
         where id = a.id;
        insert into limpeza_numeros values (1, 'animal "' || a.numero || '"', 'agora ' || m.numero || ', nome: ' || m.nome, 'OK');
      end if;
    end loop;

    -- lancamentos que citam esse texto: so se o cadastro mudou (ou nao ha
    -- cadastro com o texto), senao apontariam para o animal errado
    if not pendente then
      total := 0;
      update partos set numero_mae = m.numero where lower(trim(numero_mae)) = m.antigo;
      get diagnostics n = row_count; total := total + n;
      update diagnosticos_gestacionais set numero_vaca = m.numero where lower(trim(numero_vaca)) = m.antigo;
      get diagnostics n = row_count; total := total + n;
      update reproducao_custos set numero_vaca = m.numero where lower(trim(numero_vaca)) = m.antigo;
      get diagnostics n = row_count; total := total + n;
      update pesagens_animais set numero_animal = m.numero where lower(trim(numero_animal)) = m.antigo;
      get diagnostics n = row_count; total := total + n;
      update protocolos_inseminacao set numero_animal = m.numero where lower(trim(numero_animal)) = m.antigo;
      get diagnostics n = row_count; total := total + n;
      if total > 0 then
        insert into limpeza_numeros values (1, 'lancamentos com "' || m.antigo || '"', total || ' passaram a ' || m.numero, 'OK');
      end if;
    end if;
  end loop;

  -- ---------- 2) 721 abortou ----------
  for a in select * from animais where lower(trim(numero)) = '721 abortou' loop
    if exists (select 1 from animais o where o.id <> a.id and lower(trim(o.numero)) = '721'
                and (so_numero or o.sexo is not distinct from a.sexo)) then
      delete from animais where id = a.id;
      insert into limpeza_numeros values (1, 'animal "721 abortou"', 'apagado (duplicado da vaca 721)', 'OK');
    else
      update animais set numero = '721' where id = a.id;
      insert into limpeza_numeros values (1, 'animal "721 abortou"', 'agora 721 (nao havia outra 721)', 'OK');
    end if;
  end loop;
  update diagnosticos_gestacionais set numero_vaca = '721' where lower(trim(numero_vaca)) = '721 abortou';
  update reproducao_custos set numero_vaca = '721' where lower(trim(numero_vaca)) = '721 abortou';
  update pesagens_animais set numero_animal = '721' where lower(trim(numero_animal)) = '721 abortou';
  update protocolos_inseminacao set numero_animal = '721' where lower(trim(numero_animal)) = '721 abortou';

  update partos
     set numero_mae = '721', tipo = 'aborto', sexo_bezerro = null, raca_bezerro = null,
         data_obito = null, causa_obito = null
   where id = 197
     and lower(trim(numero_mae)) in ('721', '721 abortou')
     and tipo = 'nascimento'
     and not exists (select 1 from desmamas d where d.parto_id = partos.id);
  get diagnostics n = row_count;
  if n = 1 then
    insert into limpeza_numeros values (1, 'parto 197', 'aborto da vaca 721', 'OK');
  elsif exists (select 1 from partos where id = 197 and tipo = 'aborto') then
    insert into limpeza_numeros values (1, 'parto 197', 'ja era aborto', 'OK');
  else
    insert into limpeza_numeros values (3, 'PENDENTE parto 197', 'nao estava como esperado (mae 721, nascimento, sem desmama)', 'conferir no app; nada foi mudado');
  end if;

  -- ---------- 3) 368 e 370 pariu morto ----------
  for a in select * from partos where lower(trim(numero_mae)) in ('368 pariu morto', '370 pariu morto') loop
    if a.tipo = 'nascimento' and not exists (select 1 from desmamas d where d.parto_id = a.id) then
      update partos set numero_mae = substring(trim(a.numero_mae) from '^[0-9]+'),
                        data_obito = a.data, causa_obito = 'nasceu morto'
       where id = a.id;
      insert into limpeza_numeros values (1, 'parto ' || a.id || ' ("' || trim(a.numero_mae) || '")',
        'mae ' || substring(trim(a.numero_mae) from '^[0-9]+') || ', nasceu morto em ' || to_char(a.data, 'DD/MM/YYYY'), 'OK');
    else
      insert into limpeza_numeros values (3, 'PENDENTE parto ' || a.id || ' ("' || trim(a.numero_mae) || '")',
        'tem desmama ou nao e nascimento', 'conferir no app; nada foi mudado');
    end if;
  end loop;

  -- ---------- 4) espaco sobrando em volta de numero ----------
  total := 0;
  update partos set numero_mae = trim(numero_mae) where numero_mae <> trim(numero_mae) and trim(numero_mae) ~ '^[0-9]+$';
  get diagnostics n = row_count; total := total + n;
  update diagnosticos_gestacionais set numero_vaca = trim(numero_vaca) where numero_vaca <> trim(numero_vaca) and trim(numero_vaca) ~ '^[0-9]+$';
  get diagnostics n = row_count; total := total + n;
  update reproducao_custos set numero_vaca = trim(numero_vaca) where numero_vaca <> trim(numero_vaca) and trim(numero_vaca) ~ '^[0-9]+$';
  get diagnostics n = row_count; total := total + n;
  update pesagens_animais set numero_animal = trim(numero_animal) where numero_animal <> trim(numero_animal) and trim(numero_animal) ~ '^[0-9]+$';
  get diagnostics n = row_count; total := total + n;
  update protocolos_inseminacao set numero_animal = trim(numero_animal) where numero_animal <> trim(numero_animal) and trim(numero_animal) ~ '^[0-9]+$';
  get diagnostics n = row_count; total := total + n;
  update animais an set numero = trim(an.numero)
   where an.numero <> trim(an.numero) and trim(an.numero) ~ '^[0-9]+$'
     and not exists (select 1 from animais o where o.id <> an.id and lower(trim(o.numero)) = trim(an.numero)
                      and (so_numero or o.sexo is not distinct from an.sexo));
  get diagnostics n = row_count; total := total + n;
  if total > 0 then
    insert into limpeza_numeros values (1, 'numeros com espaco sobrando', total || ' corrigidos', 'OK');
  end if;
end $$;

-- ============================================================
-- o que foi feito, o que ficou pendente e o que ainda tem texto
-- ============================================================
with com_texto as (
  select 'animais' as campo, numero as valor from animais where numero !~ '^[0-9]+$'
  union all select 'partos', numero_mae from partos where numero_mae !~ '^[0-9]+$'
  union all select 'diagnosticos', numero_vaca from diagnosticos_gestacionais where numero_vaca !~ '^[0-9]+$'
  union all select 'inseminacoes', numero_vaca from reproducao_custos where numero_vaca !~ '^[0-9]+$'
  union all select 'pesagens por animal', numero_animal from pesagens_animais where numero_animal !~ '^[0-9]+$'
  union all select 'protocolos', numero_animal from protocolos_inseminacao where numero_animal !~ '^[0-9]+$'
)
select ordem, item, valor, situacao from limpeza_numeros
union all
select 4, 'ainda com texto em ' || campo, count(*)::text || ' -> ' || left(string_agg(distinct valor, ' | '), 300),
       'resolver no app ou com o Claude'
  from com_texto group by campo
union all
select 5, 'numeros de animal com texto (todas as tabelas)', (select count(*) from com_texto)::text,
       case when not exists (select 1 from com_texto) then 'OK' else 'ver linhas acima' end
order by 1, 2;
