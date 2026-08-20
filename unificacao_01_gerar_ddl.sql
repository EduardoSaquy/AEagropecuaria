-- ============================================================
-- PASSO 1 — GERAR O DDL DA PECUÁRIA A PARTIR DO BANCO VIVO
--
-- RODAR NO PROJETO DA **PECUÁRIA** (leojfqlbdtlriemdgnyw).
-- Não grava nada: são só SELECTs que devolvem texto.
--
-- Por que gerar em vez de usar o supabase_schema.sql que já temos: aquele
-- arquivo está desatualizado (o check de papel lá diz ('admin','funcionario'),
-- mas o banco vivo usa ('admin','proprietario','colaborador','consultor')).
-- Ler do catálogo elimina o risco de recriar a estrutura errada.
--
-- COMO USAR: rode um bloco por vez, copie a coluna de resultado inteira
-- (o painel deixa copiar a coluna) e guarde num arquivo de texto. No PASSO 2
-- você cola isso no SQL Editor do LAVOURA.
-- ============================================================


-- ------------------------------------------------------------
-- ⛔ TRAVA DE PROJETO — não remova
--
-- Este é o ÚNICO script que roda na Pecuária. Aborta se estiver no Lavoura.
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


-- ------------------------------------------------------------
-- 1.1 — CREATE TABLE de cada tabela (colunas, tipos, defaults, not null)
--
-- Pula profiles e fazendas de propósito: já existem no Lavoura.
-- profiles vira merge (passo 4) e fazendas da Pecuária está morta desde a
-- centralização do cadastro no Matriz.
-- ------------------------------------------------------------
select
  'create table if not exists ' || c.relname || E' (\n  ' ||
  string_agg(
    a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
    || case when a.attidentity <> '' then ' generated always as identity' else '' end
    || case when ad.adbin is not null and a.attidentity = ''
            then ' default ' || pg_get_expr(ad.adbin, ad.adrelid) else '' end
    || case when a.attnotnull then ' not null' else '' end,
    E',\n  ' order by a.attnum
  ) || E'\n);'
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef ad on ad.adrelid = c.oid and ad.adnum = a.attnum
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname not in ('profiles','fazendas')
group by c.relname
order by c.relname;


-- ------------------------------------------------------------
-- 1.2 — Chaves primárias, únicas, checks e estrangeiras
--
-- Sai depois das tabelas de propósito: as FKs só podem ser criadas quando
-- todas as tabelas já existem.
-- ------------------------------------------------------------
select
  'alter table ' || rel.relname || ' add constraint ' || con.conname
  || ' ' || pg_get_constraintdef(con.oid) || ';'
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace n on n.oid = rel.relnamespace
where n.nspname = 'public'
  and rel.relname not in ('profiles','fazendas')
order by
  case con.contype when 'p' then 1 when 'u' then 2 when 'c' then 3 else 4 end,
  rel.relname, con.conname;


-- ------------------------------------------------------------
-- 1.3 — Índices (só os que não vieram junto com PK/unique)
-- ------------------------------------------------------------
select indexdef || ';'
from pg_indexes
where schemaname = 'public'
  and tablename not in ('profiles','fazendas')
  and indexname not in (
    select con.conname from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace n on n.oid = rel.relnamespace
    where n.nspname = 'public' and con.contype in ('p','u')
  )
order by tablename, indexname;


-- ------------------------------------------------------------
-- 1.4 — RLS: ligar nas tabelas + recriar as políticas
--
-- IMPORTANTE — o replace() no final é o tratamento do único conflito real:
-- as chaves de permissão 'financeiro' e 'resultados' existem nos DOIS
-- projetos com significados diferentes. Do lado da Pecuária elas viram
-- 'pec_financeiro' e 'pec_resultados'. As outras 9 chaves da Pecuária
-- (manejo, cadastro, insumos, dietas, lotesGeral, confinamento, pasto,
-- cria, vendas) não colidem com nada e ficam como estão.
--
-- Confira no resultado: as linhas alteradas devem ser só das tabelas
-- config_financeiro, custos_fixos, investimentos, precos_arroba, receitas,
-- abates, config_fazenda.
-- ------------------------------------------------------------
select 'alter table ' || tablename || ' enable row level security;'
from pg_tables
where schemaname = 'public' and tablename not in ('profiles','fazendas')
order by tablename;

select
  replace(
    replace(
      'create policy "' || policyname || '" on ' || tablename
      || ' for ' || lower(cmd)
      || case when qual is not null then ' using (' || qual || ')' else '' end
      || case when with_check is not null then ' with check (' || with_check || ')' else '' end
      || ';',
      'tem_permissao(''financeiro''', 'tem_permissao(''pec_financeiro'''
    ),
    'tem_permissao(''resultados''', 'tem_permissao(''pec_resultados'''
  ) as ddl_politica
from pg_policies
where schemaname = 'public'
  and tablename not in ('profiles','fazendas')
order by tablename, policyname;


-- ------------------------------------------------------------
-- 1.5 — CONFERÊNCIA: contagem de linhas de cada tabela
--
-- Guarde ESTE resultado. No PASSO 3 os números do lado do Lavoura têm que
-- bater exatamente com estes. É a checagem que prova que nada se perdeu.
-- ------------------------------------------------------------
select relname as tabela, n_live_tup as linhas_aprox
from pg_stat_user_tables
where schemaname = 'public'
order by relname;
