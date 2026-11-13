-- ============================================================
-- SEGURANCA 07b - PRECOS TRANCADOS NO BANCO (12/11/2026)
--
-- Rodar DEPOIS do 07a e DEPOIS de publicar os apps novos (que leem
-- pelas visoes <tabela>_leitura). Tira de quem esta logado a leitura
-- direta das colunas de preco; as outras colunas continuam liberadas
-- como antes (a RLS de cada tabela segue valendo). Gravar o preco
-- continua liberado (quem lanca a compra digita o preco).
--
-- Quem le preco passa a ler pela visao, que so preenche o preco para
-- quem pode (ver o 07a).
--
-- Coluna nova numa dessas tabelas fica sem leitura ate rodar este de
-- novo (e o 07a, para entrar na visao).
-- Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_config_precos_trancados') is null then
    raise exception 'FORA DE ORDEM. Rode o seguranca_07a antes.';
  end if;
end $guarda$;

do $trava$
declare
  c record; v_cols text;
begin
  for c in select * from public.zz_config_precos_trancados loop
    if to_regclass('public.' || c.tabela) is null then continue; end if;
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols
      from pg_attribute a
     where a.attrelid = ('public.' || c.tabela)::regclass and a.attnum > 0 and not a.attisdropped
       and not (a.attname = any (c.colunas));
    execute format('revoke select on public.%I from authenticated, public, anon', c.tabela);
    -- revoga tambem grants de coluna antigos (de uma rodada anterior)
    execute format('revoke select (%s) on public.%I from authenticated, public, anon',
                   (select string_agg(quote_ident(a.attname), ', ') from pg_attribute a
                     where a.attrelid = ('public.' || c.tabela)::regclass and a.attnum > 0 and not a.attisdropped),
                   c.tabela);
    execute format('grant select (%s) on public.%I to authenticated', v_cols, c.tabela);
  end loop;
end $trava$;

-- Conferencia
select item, valor, situacao from (
  select 1 o, 'colunas de preco que quem esta logado ainda le direto' item,
         coalesce(string_agg(c.tabela || '.' || col, ', '), '0') valor,
         case when count(*) = 0 then 'OK' else 'ABERTA' end situacao
    from public.zz_config_precos_trancados c, unnest(c.colunas) col
   where to_regclass('public.' || c.tabela) is not null
     and has_column_privilege('authenticated', ('public.' || c.tabela)::regclass, col, 'SELECT')
  union all
  select 2, 'colunas sem preco que quem esta logado deixou de ler', coalesce(string_agg(a.attrelid::regclass || '.' || a.attname, ', '), '0'),
         case when count(*) = 0 then 'OK' else 'FALTA LIBERAR' end
    from public.zz_config_precos_trancados c
    join pg_attribute a on a.attrelid = to_regclass('public.' || c.tabela) and a.attnum > 0 and not a.attisdropped
   where not (a.attname = any (c.colunas))
     and not has_column_privilege('authenticated', a.attrelid, a.attname, 'SELECT')
  union all
  select 3, 'gravar preco continua liberado', coalesce(string_agg(c.tabela, ', ') filter (where not ok), '0'),
         case when bool_and(ok) then 'OK' else 'SEM INSERT/UPDATE' end
    from (select c.tabela, has_table_privilege('authenticated', ('public.' || c.tabela)::regclass, 'INSERT')
                         and has_table_privilege('authenticated', ('public.' || c.tabela)::regclass, 'UPDATE') ok
            from public.zz_config_precos_trancados c where to_regclass('public.' || c.tabela) is not null) c
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar):
-- do $d$ declare c record; begin for c in select tabela from public.zz_config_precos_trancados loop
--   if to_regclass('public.' || c.tabela) is not null then
--     execute format('grant select on public.%I to authenticated', c.tabela); end if; end loop; end $d$;
-- ============================================================
