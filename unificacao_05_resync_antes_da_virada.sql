-- ============================================================
-- PASSO 5 - RE-SINCRONIZAR ANTES DA VIRADA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz),
-- IMEDIATAMENTE ANTES de subir os HTMLs novos.
--
-- ------------------------------------------------------------
-- PARA QUE SERVE
--
-- Entre a copia dos dados (passo 3) e a virada dos apps, o AE Pecuaria
-- continua no ar apontando para o banco antigo. Todo lancamento feito
-- nesse intervalo entra la e NAO esta na copia.
--
-- Este script traz apenas o que entrou depois: compara os identificadores
-- ja existentes aqui com os de la e insere so a diferenca. Nao duplica
-- nada e nao altera nenhuma linha que ja veio.
--
-- Pode rodar quantas vezes quiser. Rode uma ultima vez com o pessoal ja
-- avisado para nao lancar mais nada, e so entao suba os HTMLs.
--
-- ------------------------------------------------------------
-- LIMITACAO IMPORTANTE, LEIA
--
-- Ele cobre INCLUSOES. Nao cobre edicoes nem exclusoes feitas no banco
-- antigo depois da copia:
--
--   * um lancamento novo la  -> vem para ca  (resolvido)
--   * um lancamento editado la -> a versao antiga continua aqui
--   * um lancamento apagado la -> continua existindo aqui
--
-- Na pratica isso raramente importa se a janela for curta e o pessoal
-- estiver so lancando. Se alguem passou o dia corrigindo lancamentos
-- antigos, me avise antes de virar: nesse caso o certo e refazer a copia
-- do zero, e nao remendar.
--
-- O relatorio no fim mostra quantas linhas entraram por tabela e alerta
-- se alguma tabela ficou com MENOS linhas la do que aqui, que e o sinal
-- de que houve exclusao no banco antigo.
-- ============================================================

do $resync$
declare
  senha text := 'SENHA_DO_BANCO_DA_PECUARIA';   -- <<< TROQUE AQUI

  pendentes    text[];
  restantes    text[];
  t            text;
  progresso    boolean;
  rodada       int  := 0;
  ultimo_erro  text := '(nenhum)';
  tem_ident    boolean;
  tem_id       boolean;
  n_antes      bigint;
  n_depois     bigint;
  n_origem     bigint;
begin
  -- ---------- TRAVAS ----------
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'lotes') then
    raise exception 'FORA DE ORDEM. A estrutura da Pecuaria ainda nao existe aqui.';
  end if;

  if (select count(*) from lotes) = 0 then
    raise exception 'A copia inicial (passo 3) ainda nao foi feita. Rode ela primeiro.';
  end if;

  -- ---------- REABRIR A PONTE ----------
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

  execute 'drop table if exists zz_resync_relatorio';
  execute 'create table zz_resync_relatorio (
             tabela text, aqui_antes bigint, na_origem bigint,
             inseridas bigint, situacao text)';

  pendentes := (
    select array_agg(ft.foreign_table_name::text order by ft.foreign_table_name)
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles', 'fazendas')
  );

  -- ---------- TRAZER SO O QUE FALTA, EM RODADAS ----------
  loop
    rodada    := rodada + 1;
    progresso := false;
    restantes := '{}';

    foreach t in array pendentes loop
      begin
        -- so da para comparar diferenca se a tabela tiver coluna id
        tem_id := (
          select exists (
            select 1 from information_schema.columns
            where table_schema = 'public' and table_name = t and column_name = 'id'
          )
        );
        if not tem_id then
          raise exception 'tabela % nao tem coluna id, nao da para sincronizar por diferenca', t;
        end if;

        tem_ident := (
          select exists (
            select 1 from pg_attribute a
            join pg_class c on c.oid = a.attrelid
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = t
              and a.attidentity <> '' and not a.attisdropped
          )
        );

        execute format('select count(*) from public.%I', t) into n_antes;

        execute format(
          'insert into public.%I %s
             select * from pec_origem_dados.%I o
             where not exists (select 1 from public.%I d where d.id = o.id)',
          t,
          case when tem_ident then 'overriding system value' else '' end,
          t, t
        );

        execute format('select count(*) from public.%I', t) into n_depois;
        execute format('select count(*) from pec_origem_dados.%I', t) into n_origem;

        execute format(
          'insert into zz_resync_relatorio values (%L, %s, %s, %s, %L)',
          t, n_antes, n_origem, n_depois - n_antes,
          case
            when n_origem < n_antes then 'ATENCAO: origem tem MENOS linhas (houve exclusao la)'
            when n_depois <> n_origem then 'ATENCAO: contagem ainda diferente'
            when n_depois - n_antes > 0 then 'sincronizada'
            else 'sem novidade'
          end
        );

        progresso := true;

      exception when others then
        ultimo_erro := t || ' -> ' || sqlerrm;
        restantes   := restantes || t;
      end;
    end loop;

    pendentes := restantes;
    exit when array_length(pendentes, 1) is null;

    if not progresso then
      raise exception 'TRAVOU com % tabela(s): % . Ultimo erro: % . Nada foi alterado.',
        array_length(pendentes, 1), array_to_string(pendentes, ', '), ultimo_erro;
    end if;
    if rodada > 40 then
      raise exception 'Rodadas demais (%).', rodada;
    end if;
  end loop;

  -- ---------- SEQUENCIAS ----------
  for t in
    select ft.foreign_table_name::text
    from information_schema.foreign_tables ft
    join information_schema.tables lo
      on lo.table_schema = 'public' and lo.table_name = ft.foreign_table_name
    where ft.foreign_table_schema = 'pec_origem_dados'
      and ft.foreign_table_name not in ('profiles', 'fazendas')
  loop
    if pg_get_serial_sequence('public.' || t, 'id') is not null then
      execute format(
        'select setval(%L, greatest((select coalesce(max(id),0) from public.%I), 1))',
        pg_get_serial_sequence('public.' || t, 'id'), t
      );
    end if;
  end loop;

  raise notice 'Re-sincronizacao concluida em % rodada(s).', rodada;
end
$resync$;

-- Leia com atencao a coluna situacao: qualquer ATENCAO merece uma conversa
-- antes de subir os HTMLs.
select * from zz_resync_relatorio order by
  case when situacao like 'ATENCAO%' then 0 else 1 end,
  inseridas desc,
  tabela;
