-- ============================================================
-- TIRA O NOME ANTIGO DO ERP DO BANCO (colunas, tabelas e textos)
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz), DEPOIS de o
-- site novo estar no ar (o app novo nao depende mais do nome gravado na
-- coluna `origem`, mas o antigo dependia).
-- Cole inteiro e rode de uma vez. Pode rodar mais de uma vez: cada passo so
-- age se ainda houver o que trocar. Se der erro, NADA muda (o editor roda
-- tudo numa transacao so).
--
-- O nome antigo e montado por pedacos ('con' || 'ag') de proposito: o
-- repositorio e publico e o Eduardo nao quer o nome escrito em lugar nenhum.
--
-- O QUE FAZ
--   1. coluna <antigo>_id vira erp_id em lancamentos_financeiros,
--      movimentos_financiamento e na view lancamentos_rateados;
--   2. indices e travas de unicidade com o nome antigo ganham nome novo;
--   3. a tabela de pouso do CSV (era temporaria) e apagada se a importacao
--      ja esta nos lancamentos; a do plano de contas so troca de nome;
--   4. movimentos_financiamento.origem passa de 'manual'/<antigo> para
--      'manual'/'erp';
--   5. textos que o PROPRIO SISTEMA escreveu: criado_por, observacao e
--      descricao dos lancamentos importados; observacao dos contratos;
--   6. comentarios das colunas e tabelas.
--
-- O QUE NAO TOCA: nome de fornecedor. Os fornecedores que tem o nome do ERP
-- no cadastro sao fornecedores de verdade e aparecem escritos em MAIUSCULAS;
-- as trocas abaixo so olham a escrita com so a primeira letra maiuscula, que
-- e a que o sistema usava.
--
-- O registro de alteracoes (log_alteracoes) fica desligado so durante a
-- troca dos textos, senao ele gravaria uma linha por lancamento (uns 9
-- mil) para uma mudanca de nome. Volta a ligar no fim do mesmo passo.
-- ============================================================

do $trava$
declare
  velho constant text := 'con' || 'ag';
  f record;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  -- Funcao escrita a mao que cite o nome antigo quebraria ao renomear a coluna
  -- (o banco acompanha view, indice e politica sozinho, mas nao texto de funcao).
  for f in select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosrc ilike '%' || velho || '%'
  loop
    raise exception 'A funcao % cita o nome antigo no codigo. Avise o Claude antes de continuar.', f.proname;
  end loop;
end
$trava$;

do $troca$
declare
  velho     constant text := 'con' || 'ag';
  velho_cap constant text := initcap('con' || 'ag');   -- so a primeira letra maiuscula
  c   record;
  n   bigint;
  gatilho_ligado boolean;
begin
  ----------------------------------------------------------------
  -- 1) COLUNAS
  ----------------------------------------------------------------
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'lancamentos_financeiros'
                and column_name = velho || '_id') then
    execute format('alter table public.lancamentos_financeiros rename column %I to erp_id', velho || '_id');
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'movimentos_financiamento'
                and column_name = velho || '_id') then
    execute format('alter table public.movimentos_financiamento rename column %I to erp_id', velho || '_id');
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'lancamentos_rateados'
                and column_name = velho || '_id') then
    execute format('alter view public.lancamentos_rateados rename column %I to erp_id', velho || '_id');
  end if;

  ----------------------------------------------------------------
  -- 2) INDICES E TRAVAS DE UNICIDADE (renomear o indice renomeia a trava)
  ----------------------------------------------------------------
  for c in select schemaname, indexname from pg_indexes
            where schemaname = 'public' and indexname ilike '%' || velho || '%'
  loop
    execute format('alter index %I.%I rename to %I',
                   c.schemaname, c.indexname, replace(lower(c.indexname), velho, 'erp'));
  end loop;

  ----------------------------------------------------------------
  -- 3) TABELAS
  ----------------------------------------------------------------
  if to_regclass('public.' || velho || '_staging') is not null then
    select count(*) into n from public.lancamentos_financeiros where erp_id is not null;
    if n >= 9000 then
      execute format('drop table public.%I', velho || '_staging');
      raise notice 'Tabela de pouso do CSV apagada (a importacao esta nos lancamentos: % linhas).', n;
    else
      raise notice 'Tabela de pouso do CSV MANTIDA: so % lancamentos importados.', n;
    end if;
  end if;

  if to_regclass('public.' || velho || '_plano_contas') is not null
     and to_regclass('public.erp_plano_contas') is null then
    execute format('alter table public.%I rename to erp_plano_contas', velho || '_plano_contas');
  end if;

  ----------------------------------------------------------------
  -- 4) movimentos_financiamento.origem: <antigo> -> 'erp'
  ----------------------------------------------------------------
  if to_regclass('public.movimentos_financiamento') is not null then
    for c in select conname from pg_constraint
              where conrelid = 'public.movimentos_financiamento'::regclass
                and contype = 'c' and pg_get_constraintdef(oid) ilike '%' || velho || '%'
    loop
      execute format('alter table public.movimentos_financiamento drop constraint %I', c.conname);
    end loop;

    update public.movimentos_financiamento set origem = 'erp' where origem = velho;

    if not exists (select 1 from pg_constraint
                    where conrelid = 'public.movimentos_financiamento'::regclass
                      and conname = 'movimentos_financiamento_origem_check') then
      alter table public.movimentos_financiamento
        add constraint movimentos_financiamento_origem_check check (origem in ('manual', 'erp'));
    end if;

    update public.movimentos_financiamento
       set descricao = replace(descricao, velho_cap, 'ERP')
     where descricao like '%' || velho_cap || '%';
  end if;

  ----------------------------------------------------------------
  -- 5) TEXTOS ESCRITOS PELO SISTEMA
  ----------------------------------------------------------------
  select exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.lancamentos_financeiros'::regclass
                    and t.tgname = 'trg_registrar_alteracao'
                    and not t.tgisinternal and t.tgenabled = 'O')
    into gatilho_ligado;
  if gatilho_ligado then
    alter table public.lancamentos_financeiros disable trigger trg_registrar_alteracao;
  end if;

  update public.lancamentos_financeiros set criado_por = 'ERP' where criado_por = velho_cap;
  get diagnostics n = row_count;
  raise notice 'criado_por trocado em % lancamentos.', n;

  -- '<Antigo> 12345 - Boleto' vira 'ERP 12345 - Boleto'
  update public.lancamentos_financeiros
     set observacao = 'ERP' || substr(observacao, length(velho) + 1)
   where observacao like velho_cap || ' %';
  get diagnostics n = row_count;
  raise notice 'observacao trocada em % lancamentos.', n;

  update public.lancamentos_financeiros
     set descricao = replace(descricao, velho_cap, 'ERP')
   where descricao like '%' || velho_cap || '%';
  get diagnostics n = row_count;
  raise notice 'descricao trocada em % lancamentos.', n;

  if gatilho_ligado then
    alter table public.lancamentos_financeiros enable trigger trg_registrar_alteracao;
  end if;

  if to_regclass('public.financiamentos') is not null then
    update public.financiamentos
       set observacao = replace(observacao, velho_cap, 'ERP')
     where observacao like '%' || velho_cap || '%';
  end if;
end
$troca$;

-- ------------------------------------------------------------
-- 6) COMENTARIOS (so aparecem no painel do Supabase). Se algum falhar, o
--    resto ja trocado fica: e so enfeite.
-- ------------------------------------------------------------
do $comentarios$
declare
  velho constant text := 'con' || 'ag';
  c record;
begin
  for c in
    select d.objsubid, d.description, cl.relkind, ns.nspname, cl.relname, a.attname
      from pg_description d
      join pg_class cl on cl.oid = d.objoid and d.classoid = 'pg_class'::regclass
      join pg_namespace ns on ns.oid = cl.relnamespace
      left join pg_attribute a on a.attrelid = cl.oid and a.attnum = d.objsubid and d.objsubid > 0
     where ns.nspname = 'public' and d.description ilike '%' || velho || '%'
  loop
    begin
      if c.objsubid = 0 then
        execute format('comment on %s %I.%I is %L',
                       case c.relkind when 'v' then 'view' when 'm' then 'materialized view'
                                      when 'i' then 'index' else 'table' end,
                       c.nspname, c.relname, regexp_replace(c.description, velho, 'ERP', 'gi'));
      else
        execute format('comment on column %I.%I.%I is %L',
                       c.nspname, c.relname, c.attname, regexp_replace(c.description, velho, 'ERP', 'gi'));
      end if;
    exception when others then
      raise notice 'Comentario de %.% ficou como estava: %', c.relname, coalesce(c.attname, ''), sqlerrm;
    end;
  end loop;

  for c in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as args, d.description
      from pg_description d
      join pg_proc p on p.oid = d.objoid and d.classoid = 'pg_proc'::regclass
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and d.description ilike '%' || velho || '%'
  loop
    begin
      execute format('comment on function %I.%I(%s) is %L',
                     c.nspname, c.proname, c.args, regexp_replace(c.description, velho, 'ERP', 'gi'));
    exception when others then
      raise notice 'Comentario da funcao % ficou como estava: %', c.proname, sqlerrm;
    end;
  end loop;
end
$comentarios$;

select 'Pronto. Rode agora o erp_21_confere_o_que_sobrou.sql para ver se sobrou algo.' as proximo_passo;
