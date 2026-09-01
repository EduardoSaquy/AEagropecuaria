-- ===================================================================
-- AE Matriz — libera Centros de Custo pra quem só tem Contas (ou só
-- Financiamentos), sem precisar de Financeiro
-- ===================================================================
-- Decisão do Eduardo em 01/09/2026: não é legal todo mundo que mexe em
-- Contas a Pagar/Receber enxergar todos os lançamentos e recebimentos
-- (Financeiro mostra tudo). Mas todo título exige um centro de custo no
-- rateio pra salvar — sem enxergar o plano de contas, quem só tem Contas
-- fica travado com o select vazio.
--
-- De quebra, achado no mesmo lugar: o código já tentava fazer o mesmo
-- pra quem só tem Financiamentos ("marcar parcela como paga" busca o
-- centro "Juros e Encargos de Financiamento") — só que a policy de
-- centros_custo nunca incluiu matriz_financiamentos na lista. Sempre
-- retornou vazio pra esse perfil, silenciosamente. Corrige os dois
-- juntos, é a mesma policy.
--
-- SÓ COLE DEPOIS de já ter rodado combustivel_unificado_02_libera_geo_
-- para_combustivel.sql (é o script que criou a policy "ler centros_custo"
-- que este arquivo substitui).
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from pg_policies
                 where schemaname='public' and tablename='centros_custo' and policyname='ler centros_custo') then
    raise exception 'policy "ler centros_custo" nao existe - rode combustivel_unificado_02_libera_geo_para_combustivel.sql primeiro.';
  end if;
end $$;

drop policy if exists "ler centros_custo" on centros_custo;
create policy "ler centros_custo" on centros_custo for select using (
  is_admin() OR tem_permissao('cana_cadastros', 'visualizar') OR tem_permissao('cereais_cadastros', 'visualizar')
  OR tem_permissao('cadastros', 'visualizar') OR tem_permissao('operacoes', 'visualizar') OR tem_permissao('operacoes_graos', 'visualizar')
  OR tem_permissao('matriz_painel', 'visualizar') OR tem_permissao('matriz_resultados', 'visualizar') OR tem_permissao('matriz_financeiro', 'visualizar')
  OR tem_permissao('matriz_fazendas', 'visualizar') OR tem_permissao('pec_financeiro', 'visualizar') OR tem_permissao('pec_resultados', 'visualizar')
  OR tem_permissao('combustivel_cadastros', 'visualizar') OR tem_permissao('combustivel_estoque', 'visualizar')
  OR tem_permissao('combustivel_abastecimento', 'visualizar') OR tem_permissao('combustivel_alertas', 'visualizar')
  OR tem_permissao('matriz_financiamentos', 'visualizar') OR tem_permissao('contas', 'visualizar')
);

select 1::numeric as ordem, item, valor, situacao from (
  select 'policy "ler centros_custo" existe (esperado: 1)' as item,
         count(*)::text as valor,
         case when count(*)=1 then 'OK' else 'ERRO' end as situacao
    from pg_policies where schemaname='public' and tablename='centros_custo' and policyname='ler centros_custo'
  union all
  select 'policy inclui matriz_financiamentos', count(*)::text,
         case when count(*)=1 then 'OK' else 'ERRO' end
    from pg_policies where schemaname='public' and tablename='centros_custo' and policyname='ler centros_custo'
     and qual ilike '%matriz_financiamentos%'
  union all
  select 'policy inclui contas', count(*)::text,
         case when count(*)=1 then 'OK' else 'ERRO' end
    from pg_policies where schemaname='public' and tablename='centros_custo' and policyname='ler centros_custo'
     and qual ilike '%''contas''%'
) x order by 1;
