-- ============================================================
-- ARREMATA O QUE A PRIMEIRA TROCA DE NOME DEIXOU PARA TRAS
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz), depois do
-- erp_20_tira_o_nome_antigo_do_banco.sql. Pode rodar mais de uma vez. Se der
-- erro, nada muda (o editor roda tudo numa transacao so).
--
-- O QUE FAZ (achado pela conferencia erp_21, em 16/10/2026)
--   1. observacao de lancamento escrita com o nome no MEIO do texto
--      ("Importado da <antigo> (soma dos funcionarios ...)"): o erp_20 so
--      trocava a que COMECAVA com o nome. Aqui "da <antigo>" vira "do ERP";
--   2. custos_fixos (tabela antiga da Pecuaria, ja migrada para
--      lancamentos_financeiros e sem uso no app): nome e observacao, para
--      continuarem batendo com a descricao dos lancamentos migrados;
--   3. a tabela de pouso do CSV, que o erp_20 manteve porque a trava de 9 mil
--      lancamentos era alta demais (a duplicidade de 2026 tirou uns 900). O
--      CSV original continua guardado na pasta de dados privados do computador.
--
-- NAO TOCA: nome de fornecedor (entidades, fornecedor e descricao escritos em
-- MAIUSCULAS) nem o historico de alteracoes (log_alteracoes).
--
-- No fim vem a mesma conferencia do erp_21: cole o resultado para o Claude.
-- O nome antigo e montado por pedacos para nao ficar escrito no repositorio.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'lancamentos_financeiros'
                   and column_name = 'erp_id') then
    raise exception 'Rode antes o erp_20_tira_o_nome_antigo_do_banco.sql.';
  end if;
end
$trava$;

-- "da <antigo>" vira "do ERP" (o nome era feminino na frase), o resto vira "ERP".
create or replace function pg_temp.sem_o_nome_antigo(t text) returns text
language sql stable as $f$
  select replace(replace(replace(replace(t,
           ' da '   || initcap('con' || 'ag'), ' do ERP'),
           ' na '   || initcap('con' || 'ag'), ' no ERP'),
           ' pela ' || initcap('con' || 'ag'), ' pelo ERP'),
           initcap('con' || 'ag'), 'ERP')
$f$;

do $arremata$
declare
  velho     constant text := 'con' || 'ag';
  velho_cap constant text := initcap('con' || 'ag');
  n   bigint;
  gatilho_ligado boolean;
begin
  -- 1) observacao dos lancamentos (o registro de alteracoes fica desligado so
  --    durante a troca: senao gravaria uma linha por lancamento)
  select exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.lancamentos_financeiros'::regclass
                    and t.tgname = 'trg_registrar_alteracao'
                    and not t.tgisinternal and t.tgenabled = 'O')
    into gatilho_ligado;
  if gatilho_ligado then
    alter table public.lancamentos_financeiros disable trigger trg_registrar_alteracao;
  end if;

  update public.lancamentos_financeiros
     set observacao = pg_temp.sem_o_nome_antigo(observacao)
   where observacao like '%' || velho_cap || '%';
  get diagnostics n = row_count;
  raise notice 'observacao trocada em % lancamentos.', n;

  if gatilho_ligado then
    alter table public.lancamentos_financeiros enable trigger trg_registrar_alteracao;
  end if;

  -- 2) custos_fixos (tabela antiga)
  if to_regclass('public.custos_fixos') is not null then
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'custos_fixos' and column_name = 'nome') then
      update public.custos_fixos
         set nome = pg_temp.sem_o_nome_antigo(nome)
       where nome like '%' || velho_cap || '%';
    end if;
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'custos_fixos' and column_name = 'observacao') then
      update public.custos_fixos
         set observacao = pg_temp.sem_o_nome_antigo(observacao)
       where observacao like '%' || velho_cap || '%';
    end if;
  end if;

  -- 3) tabela de pouso do CSV (so some se a importacao esta nos lancamentos)
  if to_regclass('public.' || velho || '_staging') is not null then
    select count(*) into n from public.lancamentos_financeiros where erp_id is not null;
    if n >= 5000 then
      execute format('drop table public.%I', velho || '_staging');
      raise notice 'Tabela de pouso do CSV apagada (a importacao esta nos lancamentos: % linhas).', n;
    else
      raise notice 'Tabela de pouso do CSV MANTIDA: so % lancamentos importados.', n;
    end if;
  end if;
end
$arremata$;

-- ------------------------------------------------------------
-- CONFERENCIA (igual a do erp_21): o que ainda tem o nome antigo.
-- Esperado: so os fornecedores de verdade (lancamentos_financeiros.fornecedor
-- e .descricao, entidades.nome) e o historico (log_alteracoes).
-- ------------------------------------------------------------
drop table if exists pg_temp.sobrou;
create temp table sobrou (tipo text, onde text, linhas bigint);

do $conf$
declare
  velho constant text := 'con' || 'ag';
  r record;
  n bigint;
begin
  insert into sobrou
  select 'objeto', cl.relkind::text || ' ' || cl.relname, null
    from pg_class cl
    join pg_namespace ns on ns.oid = cl.relnamespace
   where ns.nspname = 'public' and cl.relname ilike '%' || velho || '%';

  insert into sobrou
  select 'coluna', col.table_name || '.' || col.column_name, null
    from information_schema.columns col
   where col.table_schema = 'public' and col.column_name ilike '%' || velho || '%';

  insert into sobrou
  select 'funcao', pr.proname, null
    from pg_proc pr
    join pg_namespace ns on ns.oid = pr.pronamespace
   where ns.nspname = 'public'
     and (pr.proname ilike '%' || velho || '%' or pr.prosrc ilike '%' || velho || '%');

  insert into sobrou
  select 'trava', cn.conrelid::regclass::text || ' ' || cn.conname, null
    from pg_constraint cn
    join pg_namespace ns on ns.oid = cn.connamespace
   where ns.nspname = 'public'
     and (cn.conname ilike '%' || velho || '%' or pg_get_constraintdef(cn.oid) ilike '%' || velho || '%');

  insert into sobrou
  select 'comentario', d.classoid::regclass::text || ' ' || d.objoid::text || '.' || d.objsubid::text, null
    from pg_description d
   where d.description ilike '%' || velho || '%'
     and d.classoid in ('pg_class'::regclass, 'pg_proc'::regclass);

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
