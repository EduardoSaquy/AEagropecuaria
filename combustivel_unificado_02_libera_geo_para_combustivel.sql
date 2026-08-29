-- ===================================================================
-- AE Combustível — libera fazendas/talhões/centros de custo/culturas/
-- safras pra quem só tem permissão de Combustível
-- ===================================================================
-- SÓ COLE DEPOIS de rodar o combustivel_unificado_01_schema.sql.
--
-- As policies de SELECT de fazendas/talhoes_areas/centros_custo/
-- culturas/safras hoje exigem UMA de várias permissões específicas
-- (matriz_fazendas, cana_cadastros, pec_financeiro, etc.) — nenhuma
-- delas cobre o Combustível. Sem isso, um usuário só-de-combustível
-- não conseguiria nem ver a lista de fazenda/talhão no formulário de
-- abastecimento, mesmo já logado.
--
-- Este arquivo acrescenta as permissões do combustível na MESMA lista
-- "OU" que cada uma dessas 5 tabelas já usa — mesmo padrão já usado
-- quando Cana/Cereais/Pecuária entraram nessa lista antes. Não tira
-- nada de ninguém, só adiciona mais uma condição que também libera.
--
-- Também adiciona profiles.frentes (array — em quais frentes a pessoa
-- atua) e a restrição de abastecimento por frente: quem tem frentes
-- definidas só vê/lança abastecimento das frentes dela (ou "geral").
-- Quem não tem frente definida (o padrão) e administradores continuam
-- sem restrição — nada muda pra ninguém até um admin atribuir frentes
-- pela tela de Usuários.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='tanques') then
    raise exception 'Rode o combustivel_unificado_01_schema.sql primeiro.';
  end if;
end $$;

drop policy if exists "ler fazendas" on fazendas;
create policy "ler fazendas" on fazendas for select using (
  is_admin() OR tem_permissao('cana_cadastros', 'visualizar') OR tem_permissao('cereais_cadastros', 'visualizar')
  OR tem_permissao('cadastros', 'visualizar') OR tem_permissao('operacoes', 'visualizar') OR tem_permissao('operacoes_graos', 'visualizar')
  OR tem_permissao('matriz_painel', 'visualizar') OR tem_permissao('matriz_resultados', 'visualizar') OR tem_permissao('matriz_financeiro', 'visualizar')
  OR tem_permissao('matriz_fazendas', 'visualizar') OR tem_permissao('pec_financeiro', 'visualizar') OR tem_permissao('pec_resultados', 'visualizar')
  OR tem_permissao('combustivel_cadastros', 'visualizar') OR tem_permissao('combustivel_estoque', 'visualizar')
  OR tem_permissao('combustivel_abastecimento', 'visualizar') OR tem_permissao('combustivel_alertas', 'visualizar')
);

drop policy if exists "ler culturas" on culturas;
create policy "ler culturas" on culturas for select using (
  is_admin() OR tem_permissao('cana_cadastros', 'visualizar') OR tem_permissao('cereais_cadastros', 'visualizar')
  OR tem_permissao('cadastros', 'visualizar') OR tem_permissao('operacoes', 'visualizar') OR tem_permissao('operacoes_graos', 'visualizar')
  OR tem_permissao('matriz_painel', 'visualizar') OR tem_permissao('matriz_resultados', 'visualizar') OR tem_permissao('matriz_financeiro', 'visualizar')
  OR tem_permissao('matriz_fazendas', 'visualizar') OR tem_permissao('pec_financeiro', 'visualizar') OR tem_permissao('pec_resultados', 'visualizar')
  OR tem_permissao('combustivel_cadastros', 'visualizar') OR tem_permissao('combustivel_estoque', 'visualizar')
  OR tem_permissao('combustivel_abastecimento', 'visualizar') OR tem_permissao('combustivel_alertas', 'visualizar')
);

drop policy if exists "ler talhoes_areas" on talhoes_areas;
create policy "ler talhoes_areas" on talhoes_areas for select using (
  is_admin() OR tem_permissao('cana_cadastros', 'visualizar') OR tem_permissao('cereais_cadastros', 'visualizar')
  OR tem_permissao('cadastros', 'visualizar') OR tem_permissao('operacoes', 'visualizar') OR tem_permissao('operacoes_graos', 'visualizar')
  OR tem_permissao('matriz_painel', 'visualizar') OR tem_permissao('matriz_resultados', 'visualizar') OR tem_permissao('matriz_financeiro', 'visualizar')
  OR tem_permissao('matriz_fazendas', 'visualizar') OR tem_permissao('pec_financeiro', 'visualizar') OR tem_permissao('pec_resultados', 'visualizar')
  OR tem_permissao('combustivel_cadastros', 'visualizar') OR tem_permissao('combustivel_estoque', 'visualizar')
  OR tem_permissao('combustivel_abastecimento', 'visualizar') OR tem_permissao('combustivel_alertas', 'visualizar')
);

drop policy if exists "ler centros_custo" on centros_custo;
create policy "ler centros_custo" on centros_custo for select using (
  is_admin() OR tem_permissao('cana_cadastros', 'visualizar') OR tem_permissao('cereais_cadastros', 'visualizar')
  OR tem_permissao('cadastros', 'visualizar') OR tem_permissao('operacoes', 'visualizar') OR tem_permissao('operacoes_graos', 'visualizar')
  OR tem_permissao('matriz_painel', 'visualizar') OR tem_permissao('matriz_resultados', 'visualizar') OR tem_permissao('matriz_financeiro', 'visualizar')
  OR tem_permissao('matriz_fazendas', 'visualizar') OR tem_permissao('pec_financeiro', 'visualizar') OR tem_permissao('pec_resultados', 'visualizar')
  OR tem_permissao('combustivel_cadastros', 'visualizar') OR tem_permissao('combustivel_estoque', 'visualizar')
  OR tem_permissao('combustivel_abastecimento', 'visualizar') OR tem_permissao('combustivel_alertas', 'visualizar')
);

drop policy if exists "ler safras" on safras;
create policy "ler safras" on safras for select using (
  is_admin() OR tem_permissao('cana_cadastros', 'visualizar') OR tem_permissao('cereais_cadastros', 'visualizar')
  OR tem_permissao('cadastros', 'visualizar') OR tem_permissao('operacoes', 'visualizar') OR tem_permissao('operacoes_graos', 'visualizar')
  OR tem_permissao('matriz_painel', 'visualizar') OR tem_permissao('matriz_resultados', 'visualizar') OR tem_permissao('matriz_financeiro', 'visualizar')
  OR tem_permissao('matriz_fazendas', 'visualizar') OR tem_permissao('pec_financeiro', 'visualizar') OR tem_permissao('pec_resultados', 'visualizar')
  OR tem_permissao('combustivel_cadastros', 'visualizar') OR tem_permissao('combustivel_estoque', 'visualizar')
  OR tem_permissao('combustivel_abastecimento', 'visualizar') OR tem_permissao('combustivel_alertas', 'visualizar')
);

-- ===================================================================
-- Restrição de abastecimento por frente de negócio (opcional, por
-- colaborador) — mesma lógica do combustivel_schema.sql original.
-- ===================================================================

alter table profiles add column if not exists frentes text[] not null default '{}';

create or replace function frente_do_rateio_combustivel(p_talhao_area_id bigint, p_centro_custo_id bigint) returns text
language sql security definer set search_path = public stable as $$
  select coalesce(
    (select c.frente from talhoes_areas t join culturas c on c.id = t.cultura_id where t.id = p_talhao_area_id),
    (select cc.frente from centros_custo cc where cc.id = p_centro_custo_id),
    'geral'
  );
$$;

create or replace function pode_acessar_frente_combustivel(p_talhao_area_id bigint, p_centro_custo_id bigint) returns boolean
language sql security definer set search_path = public stable as $$
  select case
    when is_admin() then true
    when (select coalesce(cardinality(frentes), 0) from profiles where id = auth.uid()) = 0 then true
    else frente_do_rateio_combustivel(p_talhao_area_id, p_centro_custo_id) = 'geral'
      or frente_do_rateio_combustivel(p_talhao_area_id, p_centro_custo_id) = any(
        select unnest(frentes) from profiles where id = auth.uid()
      )
  end;
$$;

drop policy if exists "select abastecimentos" on abastecimentos;
drop policy if exists "inserir abastecimentos" on abastecimentos;
drop policy if exists "atualizar abastecimentos" on abastecimentos;
drop policy if exists "excluir abastecimentos" on abastecimentos;

create policy "select abastecimentos" on abastecimentos for select
  using (tem_permissao('combustivel_abastecimento','visualizar') and pode_acessar_frente_combustivel(talhao_area_id, centro_custo_id));
create policy "inserir abastecimentos" on abastecimentos for insert
  with check (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id, centro_custo_id));
create policy "atualizar abastecimentos" on abastecimentos for update
  using (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id, centro_custo_id))
  with check (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id, centro_custo_id));
create policy "excluir abastecimentos" on abastecimentos for delete
  using (tem_permissao('combustivel_abastecimento','editar') and pode_acessar_frente_combustivel(talhao_area_id, centro_custo_id));

select 1::numeric as ordem, item, valor, situacao from (
  select 'fazendas com policy nova' as item, count(*)::text as valor, 'esperado: 1' as situacao
    from pg_policies where schemaname='public' and tablename='fazendas' and policyname='ler fazendas'
  union all
  select 'colunas de profiles com frentes', count(*)::text, 'esperado: 1'
    from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='frentes'
) x order by 1;

select 'Parte 2 ok. Agora va em Usuarios no AE Matriz e conceda combustivel_cadastros/estoque/abastecimento/alertas/auditoria pra quem for usar.' as proximo_passo;
