-- ============================================================
-- MODULO DE FINANCIAMENTOS (emprestimos, custeio bancario)
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Pode rodar mais de uma vez sem problema (tudo usa
-- IF NOT EXISTS / ON CONFLICT / DROP POLICY IF EXISTS).
--
-- ------------------------------------------------------------
-- POR QUE DUAS TABELAS SEPARADAS, EM VEZ DE USAR lancamentos_financeiros
--
-- Emprestimo mexe com dinheiro em dois sentidos que NAO podem virar
-- despesa/receita direto no modelo unico:
--
--   - Receber o emprestimo nao e receita/lucro, e divida entrando. Lancar
--     como receita infla o resultado do mes artificialmente.
--   - Pagar uma parcela so e despesa NA PARTE DO JUROS. A amortizacao (a
--     parte que reduz o principal) e so o dinheiro voltando pro banco -
--     lancar a parcela inteira como despesa faz o resultado parecer pior
--     do que e.
--
-- E a mesma classe de erro do bug do custo de insumo contado duas vezes
-- (ver CLAUDE.md). Por isso: o modulo fica em tabelas proprias, e SO O
-- JUROS de cada parcela paga vira um lancamento_financeiro comum, no
-- centro de custo "Juros e Encargos de Financiamento" criado abaixo -
-- reaproveita 100% do relatorio que ja existe, sem escrever nenhum rateio
-- novo em nenhuma tela de Resultados.
--
-- Capital de giro nao tem uma atividade so: o juros de cada parcela paga e
-- dividido em 3 lancamentos iguais (Pecuaria/Cana/Graos) na hora de pagar
-- - decisao do Eduardo, mais simples que ratear por hectare.
-- ============================================================

-- ------------------------------------------------------------
-- 0) TRAVA DE PROJETO
-- ------------------------------------------------------------
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

-- ------------------------------------------------------------
-- 1) TABELAS
-- ------------------------------------------------------------
create table if not exists financiamentos (
  id                       bigint generated always as identity primary key,
  banco                    text not null,
  finalidade               text not null check (finalidade in ('investimento','custeio','capital_giro')),
  valor_principal          numeric(14,2) not null check (valor_principal > 0),
  valor_iof                numeric(14,2) not null default 0,
  valor_seguro             numeric(14,2) not null default 0,
  data_contratacao         date not null,
  taxa_juros_aa            numeric(8,4) not null check (taxa_juros_aa >= 0),
  sistema_amortizacao      text not null check (sistema_amortizacao in ('parcela_unica','sac','price')),
  numero_parcelas          int not null default 1 check (numero_parcelas > 0),
  carencia_meses           int not null default 0 check (carencia_meses >= 0),
  -- Capital de giro nao tem atividade unica (rateia 1/3 na hora de pagar);
  -- investimento e custeio precisam de uma. Validado tambem no app.
  atividade                text check (atividade in ('pecuaria','cana','graos') or atividade is null),
  fazenda_id               bigint references fazendas(id),
  garantia                 text,
  status                   text not null default 'ativo' check (status in ('ativo','quitado','renegociado','cancelado')),
  -- Se este financiamento nasceu de uma renegociacao, aponta pro antigo.
  -- Nunca apaga historico: o antigo fica com status='renegociado'.
  financiamento_origem_id  bigint references financiamentos(id),
  observacao               text,
  created_at timestamptz not null default now(), created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(), updated_by uuid
);

create table if not exists parcelas_financiamento (
  id                       bigint generated always as identity primary key,
  financiamento_id         bigint not null references financiamentos(id),
  numero                   int not null,
  data_vencimento          date not null,
  valor_parcela            numeric(14,2) not null,
  valor_amortizacao        numeric(14,2) not null,
  valor_juros              numeric(14,2) not null,
  saldo_devedor_apos       numeric(14,2) not null,
  status                   text not null default 'pendente' check (status in ('pendente','paga','atrasada','cancelada')),
  data_pagamento           date,
  valor_pago               numeric(14,2),
  -- 1 lancamento (investimento/custeio) ou 3 (capital de giro, 1 por
  -- atividade) - por isso array, nao uma FK unica.
  lancamentos_financeiro_ids bigint[] not null default '{}'::bigint[],
  created_at timestamptz not null default now(),
  unique(financiamento_id, numero)
);

create index if not exists idx_financiamentos_status on financiamentos (status);
create index if not exists idx_parcelas_fin_financiamento on parcelas_financiamento (financiamento_id, numero);
create index if not exists idx_parcelas_fin_status on parcelas_financiamento (status);

-- ------------------------------------------------------------
-- 2) RLS — mesmo padrao de lancamentos_financeiros (financeiro_01)
-- ------------------------------------------------------------
alter table financiamentos enable row level security;
alter table parcelas_financiamento enable row level security;

drop policy if exists "ve financiamentos" on financiamentos;
create policy "ve financiamentos" on financiamentos
  for select using (is_admin() or tem_permissao('matriz_financiamentos','visualizar'));
drop policy if exists "lanca financiamento" on financiamentos;
create policy "lanca financiamento" on financiamentos
  for insert with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "edita financiamento" on financiamentos;
create policy "edita financiamento" on financiamentos
  for update using (is_admin() or tem_permissao('matriz_financiamentos','editar'))
          with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "exclui financiamento" on financiamentos;
create policy "exclui financiamento" on financiamentos
  for delete using (is_admin() or tem_permissao('matriz_financiamentos','editar'));

drop policy if exists "ve parcelas" on parcelas_financiamento;
create policy "ve parcelas" on parcelas_financiamento
  for select using (is_admin() or tem_permissao('matriz_financiamentos','visualizar'));
drop policy if exists "lanca parcela" on parcelas_financiamento;
create policy "lanca parcela" on parcelas_financiamento
  for insert with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "edita parcela" on parcelas_financiamento;
create policy "edita parcela" on parcelas_financiamento
  for update using (is_admin() or tem_permissao('matriz_financiamentos','editar'))
          with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "exclui parcela" on parcelas_financiamento;
create policy "exclui parcela" on parcelas_financiamento
  for delete using (is_admin() or tem_permissao('matriz_financiamentos','editar'));

-- ------------------------------------------------------------
-- 3) CENTRO DE CUSTO DEDICADO
--
-- Um centro so pra isso, no mesmo grupo "FINANCIAMENTOS" que ja existe no
-- plano de contas do Conag (onde mora "Custas Contratuais", classificado
-- em centros_02_classifica_os_seis.sql) — assim o relatorio "despesa por
-- grupo" que ja existe no Resultados soma os dois juntos, sem codigo novo.
-- ------------------------------------------------------------
insert into centros_custo (nome, tipo, subcategoria, ativo)
select 'Juros e Encargos de Financiamento', 'saida', 'FINANCIAMENTOS | DESPESAS FINANCEIRAS', true
where not exists (
  select 1 from centros_custo where lower(btrim(nome)) = lower(btrim('Juros e Encargos de Financiamento'))
);

-- ------------------------------------------------------------
-- 4) AUDITORIA — financiamentos entra no mesmo registro de alteracoes que
-- lancamentos_financeiros/abates/profiles/centros_custo ja tem
-- (auditoria_05_registro_de_alteracoes.sql). parcelas_financiamento fica
-- de fora, mesmo criterio das tabelas de operacao diaria.
-- ------------------------------------------------------------
do $auditoria$
begin
  if to_regprocedure('public.registrar_alteracao()') is null then
    raise notice 'Funcao registrar_alteracao() nao existe ainda — rode auditoria_05_registro_de_alteracoes.sql antes. Pulando o gatilho de financiamentos.';
  else
    drop trigger if exists trg_registrar_alteracao on public.financiamentos;
    create trigger trg_registrar_alteracao after insert or update or delete on public.financiamentos
      for each row execute function registrar_alteracao();
    raise notice 'Registro de alteracoes ligado em financiamentos.';
  end if;
end
$auditoria$;

-- ============================================================
-- CONFERENCIA — tem que aparecer as duas tabelas e o centro novo
-- ============================================================
select 'tabela' as tipo, table_name as nome from information_schema.tables
  where table_schema='public' and table_name in ('financiamentos','parcelas_financiamento')
union all
select 'centro de custo', nome from centros_custo where lower(btrim(nome)) = lower(btrim('Juros e Encargos de Financiamento'));
