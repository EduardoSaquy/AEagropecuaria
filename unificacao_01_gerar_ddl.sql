-- ============================================================
-- PASSO 2 — GERAR O DDL DA PECUÁRIA A PARTIR DO BANCO VIVO
--
-- RODAR NO PROJETO DA **PECUÁRIA** (leojfqlbdtlriemdgnyw).
-- Este é o ÚNICO script da unificação que roda nesse projeto.
-- Não grava nada: são só SELECTs.
--
-- Por que gerar do banco em vez de usar o supabase_schema.sql do repositório:
-- aquele arquivo está desatualizado (o check de papel lá diz
-- ('admin','funcionario'), mas o banco vivo usa
-- ('admin','proprietario','colaborador','consultor')). Ler do catálogo
-- elimina o risco de recriar a estrutura errada.
--
-- ⚠️ COMO RODAR: o SQL Editor do Supabase só mostra o resultado do ÚLTIMO
-- comando. Por isso este arquivo tem DOIS blocos separados — rode UM DE CADA
-- VEZ, selecionando o texto do bloco com o mouse e apertando Run (o editor
-- executa só o trecho selecionado).
-- ============================================================


-- ------------------------------------------------------------
-- ⛔ TRAVA DE PROJETO — selecione e rode ISTO primeiro, sozinho.
--
-- Se der "PROJETO ERRADO", você está no Lavoura: troque pra Pecuária.
-- Se não devolver nada e não der erro, está no projeto certo. Siga.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'lotes'
  ) or exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'talhoes_areas'
  ) then
    raise exception E'PROJETO ERRADO.\nEste script e da PECUARIA (leojfqlbdtlriemdgnyw).\nTodos os outros scripts da unificacao rodam no Lavoura; so este roda aqui.\nTroque de projeto e rode de novo.';
  end if;
end $$;


-- ============================================================
-- BLOCO A — O DDL COMPLETO, NUMA CÉLULA SÓ
--
-- Selecione daqui até o ponto-e-vírgula final do bloco e rode.
-- O resultado é UMA linha, UMA coluna. Clique na célula, copie o conteúdo
-- inteiro e me mande (ou guarde pra colar no Lavoura no próximo passo).
--
-- Sai na ordem certa de execução:
--   1. create table  2. enable RLS  3. PK/unique/check  4. FK
--   5. índices       6. policies
--
-- O replace() no final trata o único conflito real da unificação: as chaves
-- de permissão 'financeiro' e 'resultados' existem nos DOIS projetos com
-- significados diferentes. Do lado da Pecuária elas viram 'pec_financeiro'
-- e 'pec_resultados'. As outras 9 chaves não colidem e ficam como estão.
--
-- profiles e fazendas ficam de fora de propósito: já existem no Lavoura.
-- ============================================================
with
ddl_tabelas as (
  select 10 as ord, c.relname as obj,
    'create table if not exists ' || c.relname || E' (\n  ' ||
    string_agg(
      a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
      || case when a.attidentity <> '' then ' generated always as identity' else '' end
      || case when ad.adbin is not null and a.attidentity = ''
              then ' default ' || pg_get_expr(ad.adbin, ad.adrelid) else '' end
      || case when a.attnotnull then ' not null' else '' end,
      E',\n  ' order by a.attnum
    ) || E'\n);' as ddl
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
  where n.nspname = 'public' and c.relkind = 'r'
    and c.relname not in ('profiles','fazendas')
  group by c.relname
),
ddl_rls as (
  select 20 as ord, tablename as obj,
    'alter table ' || tablename || ' enable row level security;' as ddl
  from pg_tables
  where schemaname = 'public' and tablename not in ('profiles','fazendas')
),
ddl_constraints as (
  select
    30 + case con.contype when 'p' then 0 when 'u' then 1 when 'c' then 2 else 3 end as ord,
    rel.relname as obj,
    'alter table ' || rel.relname || ' add constraint ' || con.conname
      || ' ' || pg_get_constraintdef(con.oid) || ';' as ddl
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace n on n.oid = rel.relnamespace
  where n.nspname = 'public' and rel.relname not in ('profiles','fazendas')
),
ddl_indices as (
  select 50 as ord, tablename as obj, indexdef || ';' as ddl
  from pg_indexes
  where schemaname = 'public'
    and tablename not in ('profiles','fazendas')
    and indexname not in (
      select con.conname from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace n on n.oid = rel.relnamespace
      where n.nspname = 'public' and con.contype in ('p','u')
    )
),
ddl_policies as (
  select 60 as ord, tablename as obj,
    replace(
      replace(
        'create policy "' || policyname || '" on ' || tablename
        || case when permissive = 'RESTRICTIVE' then ' as restrictive' else '' end
        || ' for ' || lower(cmd)
        || case when roles::text not in ('{public}','{}')
                then ' to ' || array_to_string(roles, ', ') else '' end
        || case when qual is not null then ' using (' || qual || ')' else '' end
        || case when with_check is not null then ' with check (' || with_check || ')' else '' end
        || ';',
        'tem_permissao(''financeiro''', 'tem_permissao(''pec_financeiro'''
      ),
      'tem_permissao(''resultados''', 'tem_permissao(''pec_resultados'''
    ) as ddl
  from pg_policies
  where schemaname = 'public' and tablename not in ('profiles','fazendas')
),
tudo as (
  select * from ddl_tabelas
  union all select * from ddl_rls
  union all select * from ddl_constraints
  union all select * from ddl_indices
  union all select * from ddl_policies
)
select string_agg(ddl, E'\n' order by ord, obj) as ddl_completo from tudo;


-- ============================================================
-- BLOCO B — CONTAGEM DE LINHAS (rodar depois, separado)
--
-- GUARDE ESTE RESULTADO. No passo 4, os números do lado do Lavoura têm que
-- bater exatamente com estes. É a checagem que prova que nada se perdeu.
-- ============================================================
select relname as tabela, n_live_tup as linhas
from pg_stat_user_tables
where schemaname = 'public'
order by relname;
