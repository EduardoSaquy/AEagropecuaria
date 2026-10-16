-- ============================================================
-- CONFERE O QUE AINDA TEM O NOME ANTIGO DO ERP NO BANCO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz), depois do
-- erp_20_tira_o_nome_antigo_do_banco.sql. So le: o unico que cria e uma
-- tabela temporaria (some quando a conexao fecha).
--
-- Uma lista so (tipo / onde / linhas). O que se espera ver:
--   - tipo 'texto' em lancamentos_financeiros.fornecedor e .descricao (e em
--     entidades.nome, se houver): sao fornecedores de verdade, escritos em
--     MAIUSCULAS, e ficam como estao;
--   - tipo 'texto' em log_alteracoes (antes/depois): e o historico de
--     alteracoes, que nao se reescreve.
-- Qualquer outra linha e coisa que sobrou e precisa ser tratada.
--
-- O nome antigo e montado por pedacos para nao ficar escrito no repositorio.
-- ============================================================

drop table if exists pg_temp.sobrou;
create temp table sobrou (tipo text, onde text, linhas bigint);

do $conf$
declare
  velho constant text := 'con' || 'ag';
  r record;
  n bigint;
begin
  -- tabelas, views, indices e sequencias com o nome no proprio nome
  insert into sobrou
  select 'objeto', cl.relkind::text || ' ' || cl.relname, null
    from pg_class cl
    join pg_namespace ns on ns.oid = cl.relnamespace
   where ns.nspname = 'public' and cl.relname ilike '%' || velho || '%';

  -- colunas (de tabela ou de view) com o nome
  insert into sobrou
  select 'coluna', col.table_name || '.' || col.column_name, null
    from information_schema.columns col
   where col.table_schema = 'public' and col.column_name ilike '%' || velho || '%';

  -- funcoes: no nome ou no codigo
  insert into sobrou
  select 'funcao', pr.proname, null
    from pg_proc pr
    join pg_namespace ns on ns.oid = pr.pronamespace
   where ns.nspname = 'public'
     and (pr.proname ilike '%' || velho || '%' or pr.prosrc ilike '%' || velho || '%');

  -- travas e checagens que citam o nome
  insert into sobrou
  select 'trava', cn.conrelid::regclass::text || ' ' || cn.conname, null
    from pg_constraint cn
    join pg_namespace ns on ns.oid = cn.connamespace
   where ns.nspname = 'public'
     and (cn.conname ilike '%' || velho || '%' or pg_get_constraintdef(cn.oid) ilike '%' || velho || '%');

  -- comentarios (os que aparecem no painel do Supabase)
  insert into sobrou
  select 'comentario', d.classoid::regclass::text || ' ' || d.objoid::text || '.' || d.objsubid::text, null
    from pg_description d
   where d.description ilike '%' || velho || '%'
     and d.classoid in ('pg_class'::regclass, 'pg_proc'::regclass);

  -- texto gravado nas tabelas: uma contagem por coluna de texto
  for r in
    select col.table_schema as esquema, col.table_name as tabela, col.column_name as coluna
      from information_schema.columns col
      join information_schema.tables tb
        on tb.table_schema = col.table_schema and tb.table_name = col.table_name
       and tb.table_type = 'BASE TABLE'
     where col.table_schema = 'public'
       and col.data_type in ('text', 'character varying', 'character', 'jsonb', 'json', 'ARRAY')
  loop
    execute format('select count(*) from %I.%I where %I::text ilike %L',
                   r.esquema, r.tabela, r.coluna, '%' || velho || '%')
       into n;
    if n > 0 then
      insert into sobrou values ('texto', r.tabela || '.' || r.coluna, n);
    end if;
  end loop;
end
$conf$;

select tipo, onde, linhas from sobrou order by tipo, onde;
