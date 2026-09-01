-- ===================================================================
-- AE Matriz — Contas a Pagar/Receber não exige mais Financeiro junto
-- ===================================================================
-- Achado ao investigar por que a tela de permissões avisava "exige
-- também o Financeiro acima": não era só um detalhe de tela. A regra
-- original (contas_01_estrutura.sql, comentário "REGRA COMBINADA")
-- exige de propósito as DUAS permissões — quem só tem 'contas' não via
-- nada. Decisão do Eduardo em 01/09/2026 inverte essa regra: não é
-- legal quem só mexe em boleto enxergar todos os lançamentos e
-- recebimentos (que é o que Financeiro libera). 'contas' passa a
-- bastar sozinha.
--
-- Continua igual: admin/proprietário entram direto (is_dono()), e
-- quem só tem Financeiro (sem 'contas') continua sem ver título
-- nenhum — isso nunca dependeu de Financeiro sozinho, só da chave
-- 'contas'.
--
-- Excluir não muda (contas_07_exclusao_so_dono.sql já deixou
-- só admin/proprietário, sem depender de Financeiro nem de 'contas').
--
-- SÓ COLE DEPOIS de já ter rodado contas_01_estrutura.sql.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='titulos') then
    raise exception 'titulos nao existe - rode contas_01_estrutura.sql primeiro.';
  end if;
end $$;

do $rls$
declare
  ve    text := '(is_dono() or tem_permissao(''contas'',''visualizar''))';
  edita text := '(is_dono() or tem_permissao(''contas'',''editar''))';
  t     text;
begin
  foreach t in array array['entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas'] loop
    execute format('drop policy if exists "ve %1$s"     on %1$I', t);
    execute format('drop policy if exists "cria %1$s"   on %1$I', t);
    execute format('drop policy if exists "altera %1$s" on %1$I', t);

    execute format('create policy "ve %1$s"     on %1$I for select using (%2$s)', t, ve);
    execute format('create policy "cria %1$s"   on %1$I for insert with check (%2$s)', t, edita);
    execute format('create policy "altera %1$s" on %1$I for update using (%2$s) with check (%2$s)', t, edita);
    -- "exclui %s" (delete) não é tocada aqui -- continua a policy do
    -- contas_07_exclusao_so_dono.sql (só admin/proprietário).
  end loop;
end $rls$;

select 1::numeric as ordem, item, valor, situacao from (
  select 'policies de select sem depender de matriz_financeiro (esperado: 5)' as item,
         count(*)::text as valor,
         case when count(*)=5 then 'OK' else 'ERRO' end as situacao
    from pg_policies
   where schemaname='public' and policyname like 've %'
     and tablename in ('entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas')
     and qual not ilike '%matriz_financeiro%'
  union all
  select 'policies de select exigindo a chave contas (esperado: 5)',
         count(*)::text,
         case when count(*)=5 then 'OK' else 'ERRO' end
    from pg_policies
   where schemaname='public' and policyname like 've %'
     and tablename in ('entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas')
     and qual ilike '%''contas''%'
) x order by 1;
