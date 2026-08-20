-- ============================================================
-- PASSO 2+3 — CRIAR A ESTRUTURA DA PECUÁRIA NO LAVOURA, AUTOMÁTICO
--
-- RODAR NO PROJETO DO **LAVOURA/MATRIZ** (kmkystqgpvmzrccxvyaz).
--
-- Substitui o vai-e-vem de copiar DDL entre os dois SQL Editors: este script
-- se conecta na Pecuária, lê a estrutura de lá (tabelas, chaves, índices,
-- RLS e políticas) e aplica aqui, sem você copiar nada.
--
-- É SEGURO PORQUE:
--   * o banco da Pecuária é apenas LIDO — nada é alterado lá;
--   * roda tudo dentro de uma transação: se um único comando falhar,
--     NADA é aplicado (volta ao estado atual) e a mensagem diz exatamente
--     qual comando quebrou;
--   * só cria tabelas novas. Não encosta em nenhuma tabela que já existe
--     no Lavoura.
--
-- ⚠️ SENHA: troque SENHA_DO_BANCO_DA_PECUARIA no bloco A.
-- Onde achar: projeto da Pecuária -> Project Settings -> Database ->
-- Database password. Ela NÃO é a senha da sua conta Supabase e não fica
-- visível depois de criada — se não tiver anotada, clique em
-- "Reset database password" e use a nova.
-- Resetar é seguro: nenhum app usa essa senha (eles usam a chave
-- publishable). Preencha você mesmo. Não me mande essa senha.
-- ============================================================


-- ------------------------------------------------------------
-- ⛔ TRAVA — selecione e rode ISTO sozinho primeiro.
-- Sem erro e sem resultado = projeto certo, pode seguir.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'talhoes_areas'
  ) then
    raise exception E'PROJETO ERRADO.\nEste script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).\nTroque de projeto e rode de novo.';
  end if;
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'lotes'
  ) then
    raise exception E'JA FOI APLICADO.\nA tabela lotes ja existe aqui: a estrutura da Pecuaria ja foi criada.\nNao rode este script de novo — siga para o passo de copia dos dados.';
  end if;
end $$;


-- ============================================================
-- BLOCO A — BUSCAR E APLICAR A ESTRUTURA
--
-- Selecione deste "create extension" até o "end $$;" final e rode.
-- Deve terminar dizendo quantos comandos foram aplicados.
-- ============================================================
create extension if not exists dblink;

do $$
declare
  -- >>> TROQUE SÓ A SENHA AQUI DENTRO <<<
  conexao text := 'host=db.leojfqlbdtlriemdgnyw.supabase.co port=5432 dbname=postgres user=postgres password=SENHA_DO_BANCO_DA_PECUARIA';

  consulta_remota text := $REMOTO$
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
    select ddl from tudo order by ord, obj
  $REMOTO$;

  comando text;
  atual   text;
  n_total int := 0;
begin
  for comando in
    select ddl from dblink(conexao, consulta_remota) as t(ddl text)
  loop
    atual := comando;
    execute comando;
    n_total := n_total + 1;
  end loop;

  raise notice '=======================================';
  raise notice 'ESTRUTURA APLICADA: % comandos', n_total;
  raise notice '=======================================';

exception
  when others then
    raise exception E'FALHOU depois de % comandos.\n\nComando que quebrou:\n%\n\nErro: %\n\nNada foi aplicado (a transacao voltou atras). Me mande esta mensagem.',
      n_total, atual, sqlerrm;
end $$;


-- ============================================================
-- BLOCO B — CONFERÊNCIA (rodar depois, separado)
--
-- Deve listar as 24 tabelas novas da Pecuária, todas com 0 linhas
-- (os dados vêm no próximo passo) e rls_ligada = true.
-- ============================================================
select
  t.tablename            as tabela,
  c.relrowsecurity       as rls_ligada,
  (select count(*) from pg_policies p
    where p.schemaname = 'public' and p.tablename = t.tablename) as politicas
from pg_tables t
join pg_class c on c.relname = t.tablename
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where t.schemaname = 'public'
  and t.tablename in (
    'lotes','abates','animais','config_fazenda','config_financeiro','custos_fixos',
    'partos','desmamas','diagnosticos_gestacionais','dietas','ingredientes',
    'investimentos','leituras_cocho','manejos','movimentos','pasto','pesagens',
    'pesagens_animais','precos_arroba','producoes_racao','protocolos_inseminacao',
    'receitas','reproducao_custos','saidas_racao'
  )
order by t.tablename;
