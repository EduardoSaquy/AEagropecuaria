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
--
-- Roda tudo numa transação: se qualquer tabela falhar, NADA é copiado
-- (volta atrás) e a mensagem diz em qual tabela parou.
--
-- A ordem das tabelas respeita as chaves estrangeiras (pai antes de filho)
-- e foi calculada a partir das FKs reais da Pecuária. Não reordene.
--
-- 'overriding system value' é aplicado só nas tabelas que têm coluna de
-- identidade — sem ele, o id original seria descartado e a numeração
-- histórica se perderia; com ele em tabela sem identidade, daria erro.
-- Por isso o script decide tabela a tabela, em vez de assumir.
-- ============================================================
create extension if not exists postgres_fdw;

do $$
declare
  -- >>> TROQUE SÓ A SENHA AQUI DENTRO <<<
  senha text := 'SENHA_DO_BANCO_DA_PECUARIA';

  tabelas text[] := array[
    'lotes','abates','animais','config_fazenda','config_financeiro','custos_fixos',
    'partos','desmamas','diagnosticos_gestacionais','dietas','ingredientes',
    'investimentos','leituras_cocho','manejos','movimentos','pasto','pesagens',
    'pesagens_animais','precos_arroba','producoes_racao','protocolos_inseminacao',
    'receitas','reproducao_custos','saidas_racao'
  ];
  t text;
  tem_identidade boolean;
  n_linhas bigint;
  atual text := '(preparando conexao)';
begin
  -- ---- ponte com o banco da Pecuária ----
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

  -- ---- cópia, na ordem das FKs ----
  foreach t in array tabelas loop
    atual := t;

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
    raise notice '% -> % linhas', t, n_linhas;
  end loop;

  raise notice '=======================================';
  raise notice 'DADOS COPIADOS';
  raise notice '=======================================';

exception
  when others then
    raise exception E'FALHOU na tabela: %\n\nErro: %\n\nNada foi copiado (a transacao voltou atras). Me mande esta mensagem.',
      atual, sqlerrm;
end $$;


-- ============================================================
-- BLOCO B — ACERTAR AS SEQUÊNCIAS DE ID (rodar depois, separado)
--
-- Sem isto, o próximo cadastro feito pelo app tenta usar o id 1 e estoura
-- com "duplicate key". Reposiciona cada sequência logo acima do maior id.
-- ============================================================
do $$
declare
  t text;
  seq text;
  maxid bigint;
begin
  foreach t in array array[
    'lotes','abates','animais','config_fazenda','config_financeiro','custos_fixos',
    'partos','desmamas','diagnosticos_gestacionais','dietas','ingredientes',
    'investimentos','leituras_cocho','manejos','movimentos','pasto','pesagens',
    'pesagens_animais','precos_arroba','producoes_racao','protocolos_inseminacao',
    'receitas','reproducao_custos','saidas_racao'
  ] loop
    seq := pg_get_serial_sequence('public.' || t, 'id');
    if seq is not null then
      execute format('select coalesce(max(id), 0) from public.%I', t) into maxid;
      perform setval(seq, greatest(maxid, 1));
      raise notice 'sequencia de % -> %', t, greatest(maxid, 1);
    end if;
  end loop;
end $$;


-- ============================================================
-- BLOCO C — ✅ CONFERÊNCIA OBRIGATÓRIA (rodar depois, separado)
--
-- Compara origem x destino, linha a linha. A coluna "confere" tem que dar
-- OK em TODAS as 24 tabelas. Se alguma der DIFERENTE, pare e me chame
-- antes de seguir para o passo 4.
--
-- Me mande este resultado inteiro.
-- ============================================================
do $$
declare
  t text;
  n_orig bigint;
  n_dest bigint;
  divergencias int := 0;
begin
  raise notice '%-28s %10s %10s  %s', 'TABELA', 'ORIGEM', 'DESTINO', 'CONFERE';
  foreach t in array array[
    'lotes','abates','animais','config_fazenda','config_financeiro','custos_fixos',
    'partos','desmamas','diagnosticos_gestacionais','dietas','ingredientes',
    'investimentos','leituras_cocho','manejos','movimentos','pasto','pesagens',
    'pesagens_animais','precos_arroba','producoes_racao','protocolos_inseminacao',
    'receitas','reproducao_custos','saidas_racao'
  ] loop
    execute format('select count(*) from pec_origem_dados.%I', t) into n_orig;
    execute format('select count(*) from public.%I', t) into n_dest;
    if n_orig <> n_dest then divergencias := divergencias + 1; end if;
    raise notice '%-28s %10s %10s  %s', t, n_orig, n_dest,
      case when n_orig = n_dest then 'OK' else '*** DIFERENTE ***' end;
  end loop;

  if divergencias > 0 then
    raise exception '% tabela(s) com contagem diferente. NAO siga para o passo 4.', divergencias;
  else
    raise notice '=======================================';
    raise notice 'TODAS AS 24 TABELAS CONFEREM';
    raise notice '=======================================';
  end if;
end $$;
