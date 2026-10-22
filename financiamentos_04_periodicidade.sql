-- ============================================================
-- Financiamentos - parcelas anuais/semestrais/trimestrais e data do
-- 1o vencimento (pedido do Eduardo em 22/10/2026: o cadastro so gerava
-- parcela mensal e nao tinha a data do 1o vencimento).
--
-- RODAR ANTES do AEMatriz.html novo: o app novo grava estas colunas e,
-- sem elas, salvar financiamento da erro.
--
-- periodicidade_meses: intervalo entre as parcelas (1, 3, 6 ou 12).
--   Contrato que ja existe fica com 1 (mensal), que e o que ele e.
-- primeiro_vencimento: data da 1a parcela (nulo nos contratos antigos;
--   o app usa a data da 1a parcela gravada).
--
-- Tambem deixa o dono (proprietario) excluir contrato e parcela, como ja
-- faz o admin: o botao Excluir aparece para os dois.
-- Repetivel.
-- ============================================================
do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

alter table financiamentos add column if not exists periodicidade_meses int not null default 1;
alter table financiamentos add column if not exists primeiro_vencimento date;

alter table financiamentos drop constraint if exists financiamentos_periodicidade_valida;
alter table financiamentos add constraint financiamentos_periodicidade_valida
  check (periodicidade_meses in (1, 3, 6, 12));

drop policy if exists "exclui financiamento" on financiamentos;
create policy "exclui financiamento" on financiamentos
  for delete using (is_dono() or is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "exclui parcela" on parcelas_financiamento;
create policy "exclui parcela" on parcelas_financiamento
  for delete using (is_dono() or is_admin() or tem_permissao('matriz_financiamentos','editar'));

-- ============================================================
-- CONFERENCIA
-- ============================================================
select 1 as ordem, 'coluna periodicidade_meses' as item,
       coalesce(max(data_type), '-') as valor,
       case when count(*) = 1 then 'OK' else 'ERRO - nao criada' end as situacao
  from information_schema.columns
 where table_schema = 'public' and table_name = 'financiamentos' and column_name = 'periodicidade_meses'
union all
select 2, 'coluna primeiro_vencimento',
       coalesce(max(data_type), '-'),
       case when count(*) = 1 then 'OK' else 'ERRO - nao criada' end
  from information_schema.columns
 where table_schema = 'public' and table_name = 'financiamentos' and column_name = 'primeiro_vencimento'
union all
select 3, 'contratos por periodicidade (meses: qtd)',
       coalesce(string_agg(periodicidade_meses || ': ' || n, ', '), 'nenhum contrato'),
       'OK'
  from (select periodicidade_meses, count(*) as n from financiamentos group by 1 order by 1) x
union all
select 4, 'regras de exclusao (contrato / parcela)',
       count(*)::text,
       case when count(*) = 2 then 'OK' else 'ERRO - confira' end
  from pg_policies
 where schemaname = 'public' and policyname in ('exclui financiamento', 'exclui parcela')
   and qual like '%is_dono()%'
order by 1;
