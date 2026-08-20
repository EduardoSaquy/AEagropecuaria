-- ============================================================
-- PASSO 3 — COPIAR OS DADOS DA PECUÁRIA PARA O LAVOURA
--
-- RODAR NO PROJETO DO **LAVOURA/MATRIZ** (kmkystqgpvmzrccxvyaz),
-- depois que o passo 2 (estrutura) tiver terminado com sucesso.
--
-- O banco da Pecuária é apenas LIDO. Nada é alterado lá.
--
-- ⚠️ SENHA: troque SENHA_DO_BANCO_DA_PECUARIA no bloco A. É a mesma que
-- você usou no passo 2. Preencha você mesmo; não me mande.
--
-- ------------------------------------------------------------
-- COMO ESTE SCRIPT DESCOBRE A ORDEM DE CÓPIA
--
-- As tabelas têm chaves estrangeiras entre si, então a ordem importa:
-- não dá pra inserir um lote que aponta pra uma dieta que ainda não existe.
--
-- A versão anterior usava uma ordem que eu calculei a partir do arquivo de
-- schema do repositório — e ela estava errada, porque aquele arquivo está
-- desatualizado (a FK de lotes -> dietas foi criada depois, por alter table,
-- e não aparece lá).
--
-- Agora o script não depende de nenhuma ordem pré-definida: ele tenta
-- copiar todas as tabelas, guarda as que falharam por dependência, e repete
-- em rodadas até não sobrar nenhuma. Cada tentativa roda isolada, então uma
-- falha não contamina as outras. Se em alguma rodada nada avançar, ele para
-- e mostra o erro real — em vez de insistir para sempre.
--
-- A lista de tabelas também é descoberta na hora, comparando o que existe
-- nos dois bancos. Não há lista fixa em lugar nenhum deste script.
-- ============================================================


-- ------------------------------------------------------------
-- ⛔ TRAVA — selecione e rode ISTO sozinho primeiro.
-- Sem erro e sem resultado = tudo certo, pode seguir.
-- ------------------------------------------------------------
do $$
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
end $$;


-- ============================================================
-- BLOCO A — CONECTAR E COPIAR
--
-- Selecione do "create extension" até o "end $$;" final e rode.
-- Roda tudo numa transação: se travar, NADA é copiado.
-- ============================================================
create extension if not exists postgres_fdw;

do $$
declare
  -- >>> TROQUE SÓ A SENHA AQUI DENTRO <<<
  senha text := 'SENHA_DO_BANCO_DA_PECUARIA';

  pendentes  text[];
  restantes  text[];
  t          text;
  progresso  boolean;
  rodada     int := 0;
  ultimo_erro text := '(nenhum)';
  tem_identidade boolean;
  n_linhas   bigint;
  n_copiadas int := 0;
begin
  -- ---- ponte com o banco da Pecuária (só leitura) ----
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

  -- ---- descobrir quais tabelas copiar (as que existem dos dois lados) ----
  select array_agg(ft.foreign_table_name::text order by ft.foreign_table_name)
    into pendentes
  from information_schema.foreign_tables ft
  join information_schema.tables lo
    on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
  where ft.foreign_table_schema = 'pec_origem_dados'
    and ft.foreign_table_name not in ('profiles','fazendas');

  if pendentes is null then
    raise exception 'Nenhuma tabela em comum encontrada. A estrutura do passo 2 foi aplicada?';
  end if;

  raise notice 'Tabelas a copiar: %', array_length(pendentes, 1);

  -- ---- copiar em rodadas, até não sobrar nenhuma ----
  loop
    rodada    := rodada + 1;
    progresso := false;
    restantes := '{}';

    foreach t in array pendentes loop
      begin
        select exists (
          select 1 from pg_attribute a
          join pg_class c on c.oid = a.attrelid
          join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relname = t
            and a.attidentity <> '' and not a.attisdropped
        ) into tem_identidade;

        execute format(
          'insert into public.%I %s select * from pec_origem_dados.%I',
          t,
          case when tem_identidade then 'overriding system value' else '' end,
          t
        );

        execute format('select count(*) from public.%I', t) into n_linhas;
        raise notice '[rodada %] % -> % linhas', rodada, t, n_linhas;
        progresso   := true;
        n_copiadas  := n_copiadas + 1;

      exception when others then
        -- provavelmente depende de outra tabela ainda não copiada:
        -- guarda pra próxima rodada.
        ultimo_erro := t || ' -> ' || sqlerrm;
        restantes   := restantes || t;
      end;
    end loop;

    pendentes := restantes;
    exit when array_length(pendentes, 1) is null;

    if not progresso then
      raise exception E'TRAVOU com % tabela(s) pendente(s): %\n\nUltimo erro real:\n%\n\nNada foi copiado (a transacao voltou atras). Me mande esta mensagem.',
        array_length(pendentes, 1), array_to_string(pendentes, ', '), ultimo_erro;
    end if;

    if rodada > 40 then
      raise exception 'Rodadas demais (%). Algo esta errado.', rodada;
    end if;
  end loop;

  raise notice '=======================================';
  raise notice 'DADOS COPIADOS: % tabelas em % rodada(s)', n_copiadas, rodada;
  raise notice '=======================================';
end $$;


-- ============================================================
-- BLOCO B — ACERTAR AS SEQUÊNCIAS DE ID (rodar depois, separado)
--
-- Sem isto, o próximo cadastro feito pelo app tenta usar o id 1 e estoura
-- com "duplicate key". Reposiciona cada sequência acima do maior id.
-- ============================================================
do $$
declare
  t text;
  seq text;
  maxid bigint;
begin
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
      raise notice 'sequencia de % -> %', t, greatest(maxid, 1);
    end if;
  end loop;
end $$;


-- ============================================================
-- BLOCO C — ✅ CONFERÊNCIA (rodar depois, separado)
--
-- Compara origem x destino em todas as tabelas. Aborta se qualquer
-- contagem divergir. Me mande este resultado.
-- ============================================================
do $$
declare
  t text;
  n_orig bigint;
  n_dest bigint;
  divergencias int := 0;
  total int := 0;
begin
  raise notice '%-30s %10s %10s  %s', 'TABELA', 'ORIGEM', 'DESTINO', 'CONFERE';
  for t in
    select ft.foreign_table_name::text
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles','fazendas')
    order by 1
  loop
    execute format('select count(*) from pec_origem_dados.%I', t) into n_orig;
    execute format('select count(*) from public.%I', t) into n_dest;
    total := total + 1;
    if n_orig <> n_dest then divergencias := divergencias + 1; end if;
    raise notice '%-30s %10s %10s  %s', t, n_orig, n_dest,
      case when n_orig = n_dest then 'OK' else '*** DIFERENTE ***' end;
  end loop;

  if divergencias > 0 then
    raise exception '% de % tabelas com contagem diferente. NAO siga para o passo 4.', divergencias, total;
  else
    raise notice '=======================================';
    raise notice 'TODAS AS % TABELAS CONFEREM', total;
    raise notice '=======================================';
  end if;
end $$;
