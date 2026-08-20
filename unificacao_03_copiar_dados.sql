-- ============================================================
-- PASSO 3 — COPIAR OS DADOS DA PECUÁRIA PARA O LAVOURA
--
-- RODAR NO PROJETO DO **LAVOURA/MATRIZ** (kmkystqgpvmzrccxvyaz).
--
-- O banco da Pecuária é apenas LIDO. Nada é alterado lá.
--
-- ⚠️ SENHA: troque SENHA_DO_BANCO_DA_PECUARIA lá embaixo, no BLOCO 2.
--
-- ------------------------------------------------------------
-- COMO RODAR — leia, mudou
--
-- Agora são só DOIS blocos. Você pode simplesmente colar o arquivo
-- inteiro e apertar Run: eles rodam em sequência sem problema.
--
-- Se preferir ir um de cada vez, selecione o bloco inteiro — do
-- "do $nome$" até o "$nome$;" correspondente, incluindo as duas linhas.
--
-- Cada bloco usa um delimitador com nome ($copia$, $confere$) em vez do
-- $$ genérico. Com $$ repetido várias vezes no mesmo arquivo, o editor
-- pode fechar o bloco no lugar errado e partir o código no meio — foi o
-- que gerou o erro "relation pendentes does not exist" (pendentes é uma
-- variável interna, que só existe dentro do bloco).
--
-- ------------------------------------------------------------
-- COMO A ORDEM DE CÓPIA É RESOLVIDA
--
-- As tabelas têm chaves estrangeiras entre si, então a ordem importa.
-- Este script não usa nenhuma ordem pré-definida: tenta copiar todas,
-- guarda as que falharam por dependência e repete em rodadas até
-- esvaziar. Cada tentativa fica isolada, então uma falha não derruba as
-- outras. Se uma rodada inteira não avançar, ele para e mostra o erro
-- real em vez de insistir.
-- ============================================================


-- ============================================================
-- BLOCO 1 — TRAVA DE SEGURANÇA
-- ============================================================
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception E'PROJETO ERRADO.\nEste script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='lotes') then
    raise exception E'FORA DE ORDEM.\nA estrutura da Pecuaria ainda nao foi criada aqui.\nRode antes o unificacao_02_estrutura_automatica.sql.';
  end if;
  if (select count(*) from lotes) > 0 then
    raise exception E'JA TEM DADO AQUI.\nA tabela lotes nao esta vazia — este script ja rodou.\nRodar de novo duplicaria todos os lancamentos.';
  end if;
  raise notice 'Trava OK — pode copiar.';
end
$trava$;


-- ============================================================
-- BLOCO 2 — CONECTAR, COPIAR E ACERTAR AS SEQUÊNCIAS
--
-- ⚠️ A SENHA VAI NA PRIMEIRA LINHA DEPOIS DO "declare".
-- ============================================================
create extension if not exists postgres_fdw;

do $copia$
declare
  senha text := 'SENHA_DO_BANCO_DA_PECUARIA';   -- <<< TROQUE AQUI

  pendentes   text[];
  restantes   text[];
  t           text;
  progresso   boolean;
  rodada      int  := 0;
  ultimo_erro text := '(nenhum)';
  tem_ident   boolean;
  n_linhas    bigint;
  n_copiadas  int  := 0;
  seq         text;
  maxid       bigint;
begin
  -- ---- ponte com o banco da Pecuária (somente leitura) ----
  execute 'drop server if exists pec_origem cascade';
  execute 'create server pec_origem foreign data wrapper postgres_fdw options ('
       || 'host ''db.leojfqlbdtlriemdgnyw.supabase.co'', port ''5432'', dbname ''postgres'')';
  execute format(
    'create user mapping for current_user server pec_origem options (user %L, password %L)',
    'postgres', senha
  );
  execute 'drop schema if exists pec_origem_dados cascade';
  execute 'create schema pec_origem_dados';
  execute 'import foreign schema public from server pec_origem into pec_origem_dados';

  -- ---- descobrir as tabelas que existem dos dois lados ----
  pendentes := (
    select array_agg(ft.foreign_table_name::text order by ft.foreign_table_name)
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles','fazendas')
  );

  if pendentes is null then
    raise exception 'Nenhuma tabela em comum. A estrutura do passo 2 foi aplicada?';
  end if;
  raise notice 'Tabelas a copiar: %', array_length(pendentes, 1);

  -- ---- copiar em rodadas ----
  loop
    rodada    := rodada + 1;
    progresso := false;
    restantes := '{}';

    foreach t in array pendentes loop
      begin
        tem_ident := (
          select exists (
            select 1 from pg_attribute a
            join pg_class c on c.oid = a.attrelid
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = t
              and a.attidentity <> '' and not a.attisdropped
          )
        );

        execute format(
          'insert into public.%I %s select * from pec_origem_dados.%I',
          t,
          case when tem_ident then 'overriding system value' else '' end,
          t
        );

        execute format('select count(*) from public.%I', t) into n_linhas;
        raise notice '[rodada %] % -> % linhas', rodada, t, n_linhas;
        progresso  := true;
        n_copiadas := n_copiadas + 1;

      exception when others then
        ultimo_erro := t || ' -> ' || sqlerrm;
        restantes   := restantes || t;
      end;
    end loop;

    pendentes := restantes;
    exit when array_length(pendentes, 1) is null;

    if not progresso then
      raise exception E'TRAVOU com % tabela(s): %\n\nUltimo erro real:\n%\n\nNada foi copiado. Me mande esta mensagem.',
        array_length(pendentes, 1), array_to_string(pendentes, ', '), ultimo_erro;
    end if;
    if rodada > 40 then
      raise exception 'Rodadas demais (%).', rodada;
    end if;
  end loop;

  -- ---- acertar as sequências de id ----
  -- Sem isto, o primeiro cadastro novo pelo app tentaria usar o id 1 e
  -- estouraria com "duplicate key".
  for t in
    select ft.foreign_table_name::text
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles','fazendas')
    order by 1
  loop
    seq := pg_get_serial_sequence('public.' || t, 'id');
    if seq is not null then
      execute format('select coalesce(max(id), 0) from public.%I', t) into maxid;
      perform setval(seq, greatest(maxid, 1));
    end if;
  end loop;

  raise notice '=======================================';
  raise notice 'DADOS COPIADOS: % tabelas em % rodada(s)', n_copiadas, rodada;
  raise notice 'Sequencias de id reposicionadas.';
  raise notice '=======================================';
end
$copia$;


-- ============================================================
-- BLOCO 3 — ✅ CONFERÊNCIA
--
-- Compara origem x destino. Devolve uma tabela — me mande ela inteira.
-- ============================================================
select
  ft.foreign_table_name as tabela,
  (xpath('/row/c/text()',
     query_to_xml(format('select count(*) as c from pec_origem_dados.%I', ft.foreign_table_name),
                  false, true, '')))[1]::text::bigint as origem,
  (xpath('/row/c/text()',
     query_to_xml(format('select count(*) as c from public.%I', ft.foreign_table_name),
                  false, true, '')))[1]::text::bigint as destino,
  case when
    (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from pec_origem_dados.%I', ft.foreign_table_name), false, true, '')))[1]::text::bigint
    =
    (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', ft.foreign_table_name), false, true, '')))[1]::text::bigint
  then 'OK' else '*** DIFERENTE ***' end as confere
from information_schema.foreign_tables ft
join information_schema.tables lo
  on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
where ft.foreign_table_schema = 'pec_origem_dados'
  and ft.foreign_table_name not in ('profiles','fazendas')
order by 1;
