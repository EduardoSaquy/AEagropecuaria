-- ===================================================================
-- AE Combustível — remove centro de custo do rateio de abastecimento
-- ===================================================================
-- Decisão do Eduardo em 30/08/2026: o custo do combustível entra em
-- lançamentos financeiros à parte (ainda não integrado, por ora
-- controle próprio) — quem classifica por centro de custo é quem
-- lança lá, não o abastecimento individual. Rateio por talhão/área
-- continua (identifica a frente pra volume/L, não R$), e a "Operação"
-- (Transporte, Deslocamento etc., já cadastrada) cobre o mesmo papel
-- que centro de custo cobria pro combustível sem talhão específico.
--
-- Depois de rodar: talhão/área vira opcional em vez de "pelo menos um
-- dos dois com centro de custo" — um abastecimento sem talhão (uso
-- geral) cai em frente "geral" automaticamente, como já acontecia.
--
-- SÓ COLE DEPOIS de já ter rodado combustivel_unificado_01_schema.sql
-- e combustivel_unificado_02_libera_geo_para_combustivel.sql.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='abastecimentos') then
    raise exception 'abastecimentos nao existe - rode o combustivel_unificado_01_schema.sql primeiro.';
  end if;
  if not exists (select 1 from pg_proc where proname = 'pode_acessar_frente_combustivel') then
    raise exception 'pode_acessar_frente_combustivel nao existe - rode o combustivel_unificado_02_libera_geo_para_combustivel.sql primeiro.';
  end if;
end $$;

-- 1. Derruba as 4 policies de abastecimentos -- dependem da versão de
--    2 parâmetros das funções abaixo, tem que sair antes delas.
drop policy if exists "select abastecimentos" on abastecimentos;
drop policy if exists "inserir abastecimentos" on abastecimentos;
drop policy if exists "atualizar abastecimentos" on abastecimentos;
drop policy if exists "excluir abastecimentos" on abastecimentos;

-- 2. Troca as funções pela versão sem centro de custo. O DROP explícito
--    da assinatura de 2 parâmetros cobre a primeira vez que este script
--    roda (CREATE OR REPLACE sozinho não trocaria a lista de parâmetros
--    -- criaria uma segunda função ao lado da antiga). CREATE OR REPLACE
--    (em vez de só CREATE) cobre rodar este script de novo depois que já
--    rodou uma vez -- sem isso, "CREATE FUNCTION" trava dizendo que a
--    função de 1 parâmetro já existe.
drop function if exists pode_acessar_frente_combustivel(bigint, bigint);
drop function if exists frente_do_rateio_combustivel(bigint, bigint);

create or replace function frente_do_rateio_combustivel(p_talhao_area_id bigint) returns text
language sql security definer set search_path = public stable as $$
  select coalesce(
    (select c.frente from talhoes_areas t join culturas c on c.id = t.cultura_id where t.id = p_talhao_area_id),
    'geral'
  );
$$;

create or replace function pode_acessar_frente_combustivel(p_talhao_area_id bigint) returns boolean
language sql security definer set search_path = public stable as $$
  select case
    when is_admin() then true
    when (select coalesce(cardinality(frentes), 0) from profiles where id = auth.uid()) = 0 then true
    else frente_do_rateio_combustivel(p_talhao_area_id) = 'geral'
      or frente_do_rateio_combustivel(p_talhao_area_id) = any(
        select unnest(frentes) from profiles where id = auth.uid()
      )
  end;
$$;

-- 3. Recria as policies com a função de 1 parâmetro.
create policy "select abastecimentos" on abastecimentos for select
  using (tem_permissao('combustivel_abastecimento','visualizar') and pode_acessar_frente_combustivel(talhao_area_id));
create policy "inserir abastecimentos" on abastecimentos for insert
  with check (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id));
create policy "atualizar abastecimentos" on abastecimentos for update
  using (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id))
  with check (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id));
create policy "excluir abastecimentos" on abastecimentos for delete
  using (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id));

-- 4. Tira a obrigação de "talhão OU centro de custo" -- talhão/área
--    vira sozinho e opcional (abastecimento sem talhão cai em "geral").
alter table abastecimentos drop constraint if exists abastecimento_precisa_rateio;

-- 5. Derruba a coluna em si -- não sobra mais nada gravando nela.
alter table abastecimentos drop column if exists centro_custo_id;

select 1::numeric as ordem, item, valor, situacao from (
  select 'coluna centro_custo_id em abastecimentos (esperado: 0)' as item,
         count(*)::text as valor,
         case when count(*)=0 then 'OK' else 'ERRO - coluna ainda existe' end as situacao
    from information_schema.columns
   where table_schema='public' and table_name='abastecimentos' and column_name='centro_custo_id'
  union all
  select 'constraint abastecimento_precisa_rateio (esperado: 0)',
         count(*)::text,
         case when count(*)=0 then 'OK' else 'ERRO - constraint ainda existe' end
    from pg_constraint where conname='abastecimento_precisa_rateio'
  union all
  select 'policies de abastecimentos (esperado: 4)',
         count(*)::text,
         case when count(*)=4 then 'OK' else 'ERRO - esperava 4 policies' end
    from pg_policies where schemaname='public' and tablename='abastecimentos'
  union all
  select 'funcao pode_acessar_frente_combustivel(bigint) existe (esperado: 1)',
         count(*)::text,
         case when count(*)=1 then 'OK' else 'ERRO' end
    from pg_proc where proname='pode_acessar_frente_combustivel' and pronargs=1
) x order by 1;
