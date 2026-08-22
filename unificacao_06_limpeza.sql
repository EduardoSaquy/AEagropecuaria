-- ============================================================
-- PASSO 6 - LIMPEZA E FECHAMENTO DA UNIFICACAO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole o arquivo inteiro e aperte Run. Sao dois comandos.
--
-- Rodar SO depois de confirmar que os tres apps estao funcionando com o
-- banco unico, porque ele remove a ponte e as liberacoes antigas.
--
-- ------------------------------------------------------------
-- O QUE ELE FAZ, E POR QUE E O MAIOR GANHO DA UNIFICACAO
--
-- Enquanto os apps eram dois projetos separados, cada um precisava ler o
-- banco do outro sem ter login la. A unica forma era liberar leitura para
-- requisicao ANONIMA nas tabelas envolvidas. Isso significa que qualquer
-- pessoa com a chave publica do app (que fica a vista no HTML, basta abrir
-- o codigo-fonte da pagina) consegue ler essas tabelas inteiras sem login
-- nenhum: lote, dieta, custo, receita, tudo.
--
-- Com um banco so, nada disso e necessario. Este script derruba TODAS
-- essas liberacoes.
--
-- ATENCAO: ele remove as liberacoes de forma dinamica, nao por lista fixa.
-- Isso e proposital. Quando copiamos a estrutura da Pecuaria, vieram junto
-- as politicas de leitura anonima que existiam la, entao hoje elas estao
-- espalhadas em tabelas que eu nao teria como listar sem errar - foi
-- exatamente o tipo de suposicao que ja falhou duas vezes nesta migracao.
-- O script encontra e apaga o que existir, e lista o que apagou.
-- ============================================================

do $limpeza$
declare
  p record;
  n_politicas int := 0;
begin
  -- ---------- TRAVA ----------
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'lotes') then
    raise exception 'A unificacao ainda nao foi feita neste projeto.';
  end if;

  -- ---------- RELATORIO DO QUE FOI REMOVIDO ----------
  execute 'drop table if exists zz_limpeza_relatorio';
  execute 'create table zz_limpeza_relatorio (item text, detalhe text)';

  -- ---------- 1) DERRUBAR TODAS AS LIBERACOES ANONIMAS ----------
  -- Pega tanto pelo nome quanto pela regra, porque as politicas vieram de
  -- dois projetos diferentes e nao seguem um nome unico.
  for p in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and (
        policyname ilike '%anon%'
        or coalesce(qual, '') ilike '%auth.role()%anon%'
        or coalesce(qual, '') ilike '%''anon''%'
      )
  loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    execute format('insert into zz_limpeza_relatorio values (%L, %L)',
                   'politica anonima removida', p.tablename || ' -> ' || p.policyname);
    n_politicas := n_politicas + 1;
  end loop;

  -- ---------- 2) DERRUBAR A PONTE COM O BANCO ANTIGO ----------
  if exists (select 1 from information_schema.schemata where schema_name = 'pec_origem_dados') then
    execute 'drop schema pec_origem_dados cascade';
    execute format('insert into zz_limpeza_relatorio values (%L, %L)',
                   'ponte removida', 'schema pec_origem_dados');
  end if;

  if exists (select 1 from pg_foreign_server where srvname = 'pec_origem') then
    execute 'drop server pec_origem cascade';
    execute format('insert into zz_limpeza_relatorio values (%L, %L)',
                   'ponte removida', 'server pec_origem (a senha do banco antigo sai junto)');
  end if;

  -- ---------- 3) TABELAS TEMPORARIAS DA MIGRACAO ----------
  execute 'drop table if exists zz_conferencia_migracao';
  execute 'drop table if exists zz_resync_relatorio';
  execute 'drop table if exists zz_relatorio_permissoes';
  execute format('insert into zz_limpeza_relatorio values (%L, %L)',
                 'temporarias removidas', 'zz_conferencia_migracao, zz_resync_relatorio, zz_relatorio_permissoes');

  -- ---------- O QUE FICA DE PROPOSITO ----------
  -- profiles_backup_unificacao e funcionarios_backup_limpeza continuam.
  -- Sao pequenas e sao a sua rede de seguranca. Apague daqui a algumas
  -- semanas, quando tiver certeza de que esta tudo redondo:
  --   drop table profiles_backup_unificacao;
  --   drop table funcionarios_backup_limpeza;

  raise notice 'Limpeza concluida. % liberacao(oes) anonima(s) removida(s).', n_politicas;
end
$limpeza$;

-- ============================================================
-- RESULTADO
--
-- A primeira parte mostra o que foi removido.
-- A segunda TEM QUE VIR VAZIA: e a varredura por qualquer liberacao
-- anonima que tenha sobrado.
-- ============================================================
select * from zz_limpeza_relatorio
union all
select '--- SOBROU ALGUMA LIBERACAO ANONIMA? (esta lista tem que estar vazia) ---', ''
union all
select 'AINDA ABERTA: ' || tablename, policyname
from pg_policies
where schemaname = 'public'
  and (
    policyname ilike '%anon%'
    or coalesce(qual, '') ilike '%auth.role()%anon%'
    or coalesce(qual, '') ilike '%''anon''%'
  );
