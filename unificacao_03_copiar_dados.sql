-- ============================================================
-- PASSO 3 - COPIAR OS DADOS DA PECUARIA PARA O LAVOURA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- O banco da Pecuaria e apenas LIDO. Nada e alterado la.
--
-- COMO RODAR: cole o arquivo inteiro e aperte Run. Nao precisa
-- selecionar nada. Sao tres comandos que rodam em sequencia.
--
-- ANTES DE RODAR: troque SENHA_DO_BANCO_DA_PECUARIA pela senha do banco,
-- na primeira linha depois de "declare".
--
-- SEGURANCA: roda tudo numa transacao. Se qualquer coisa falhar, nada e
-- copiado e a mensagem diz onde parou. A trava de projeto esta dentro do
-- proprio bloco, entao nao ha como copiar no banco errado.
--
-- ORDEM DE COPIA: as tabelas tem chaves estrangeiras entre si, entao a
-- ordem importa. Este script nao usa ordem pre-definida: tenta copiar
-- todas, guarda as que falharam por dependencia e repete em rodadas ate
-- esvaziar. Cada tentativa fica isolada, entao uma falha nao derruba as
-- outras. Se uma rodada inteira nao avancar, ele para e mostra o erro
-- real em vez de insistir.
--
-- NOTA TECNICA: este arquivo evita de proposito qualquer cifrao no texto
-- dos comentarios. O editor de SQL do Supabase separa os comandos sem
-- ignorar comentarios, entao um delimitador citado dentro de um
-- comentario faz ele fechar o bloco no lugar errado e partir o codigo no
-- meio. Foi a causa dos erros "relation pendentes does not exist" e
-- "relation n_linhas does not exist" - nomes de variaveis internas que
-- ficaram orfas fora do bloco.
-- ============================================================

create extension if not exists postgres_fdw;

do $migrar$
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
  n_orig      bigint;
  n_dest      bigint;
begin
  -- ---------- TRAVAS ----------
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'lotes') then
    raise exception 'FORA DE ORDEM. A estrutura da Pecuaria ainda nao existe aqui. Rode antes o script do passo 2.';
  end if;

  if (select count(*) from lotes) > 0 then
    raise exception 'JA TEM DADO AQUI. A tabela lotes nao esta vazia, este script ja rodou. Rodar de novo duplicaria os lancamentos.';
  end if;

  -- ---------- PONTE COM O BANCO DA PECUARIA (somente leitura) ----------
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

  -- ---------- DESCOBRIR AS TABELAS QUE EXISTEM DOS DOIS LADOS ----------
  pendentes := (
    select array_agg(ft.foreign_table_name::text order by ft.foreign_table_name)
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles', 'fazendas')
  );

  if pendentes is null then
    raise exception 'Nenhuma tabela em comum. A estrutura do passo 2 foi aplicada?';
  end if;

  raise notice 'Tabelas a copiar: %', array_length(pendentes, 1);

  -- ---------- COPIAR EM RODADAS ----------
  loop
    rodada    := rodada + 1;
    progresso := false;
    restantes := '{}';

    foreach t in array pendentes loop
      begin
        -- "overriding system value" so vale onde existe coluna de
        -- identidade: sem ele o id original seria descartado; com ele
        -- numa tabela sem identidade, daria erro.
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
        raise notice 'rodada % : % com % linhas', rodada, t, n_linhas;
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
      raise exception 'TRAVOU com % tabela(s): % . Ultimo erro real: % . Nada foi copiado.',
        array_length(pendentes, 1), array_to_string(pendentes, ', '), ultimo_erro;
    end if;

    if rodada > 40 then
      raise exception 'Rodadas demais (%).', rodada;
    end if;
  end loop;

  -- ---------- ACERTAR AS SEQUENCIAS DE ID ----------
  -- Sem isto, o primeiro cadastro novo pelo app tentaria usar o id 1 e
  -- estouraria com erro de chave duplicada.
  for t in
    select ft.foreign_table_name::text
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles', 'fazendas')
    order by 1
  loop
    seq := pg_get_serial_sequence('public.' || t, 'id');
    if seq is not null then
      execute format('select coalesce(max(id), 0) from public.%I', t) into maxid;
      perform setval(seq, greatest(maxid, 1));
    end if;
  end loop;

  -- ---------- MONTAR A TABELA DE CONFERENCIA ----------
  -- Guardada numa tabela real para o ultimo comando poder exibir. As
  -- mensagens de notice nem sempre aparecem no painel do Supabase.
  execute 'drop table if exists zz_conferencia_migracao';
  execute 'create table zz_conferencia_migracao (tabela text, origem bigint, destino bigint, confere text)';

  for t in
    select ft.foreign_table_name::text
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles', 'fazendas')
    order by 1
  loop
    execute format('select count(*) from pec_origem_dados.%I', t) into n_orig;
    execute format('select count(*) from public.%I', t) into n_dest;
    execute format('insert into zz_conferencia_migracao values (%L, %s, %s, %L)',
      t, n_orig, n_dest,
      case when n_orig = n_dest then 'OK' else 'DIFERENTE' end);
  end loop;

  raise notice 'DADOS COPIADOS: % tabelas em % rodada(s)', n_copiadas, rodada;
end
$migrar$;

select * from zz_conferencia_migracao order by tabela;
