-- Schema do AEpecuária (rodar no SQL Editor do Supabase)

create table ingredientes (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria text,
  fornecedor text,
  unidade text default 'kg',
  ms numeric default 0,
  pb numeric default 0,
  ndt numeric default 0,
  preco_kg numeric default 0,
  estoque_min numeric default 0,
  obs text default ''
);

create table movimentos (
  id bigint generated always as identity primary key,
  data date not null,
  ingrediente_id bigint references ingredientes(id) on delete cascade,
  tipo text not null, -- 'entrada' ou 'saida'
  quantidade numeric default 0
);

create table dietas (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria_animal text,
  kg_animal_dia numeric default 0,
  itens jsonb default '[]' -- [{ingredienteId, pct}]
);

-- dados de exemplo (os mesmos que já existem no app hoje)
insert into ingredientes (nome, categoria, fornecedor, unidade, ms, pb, ndt, preco_kg, estoque_min, obs) values
  ('Milho moído', 'Energético', 'Cooperativa Vale Verde', 'kg', 88, 9.0, 88, 0.98, 5000, ''),
  ('Farelo de soja', 'Proteico', 'Agroindustrial Sul', 'kg', 89, 45.0, 82, 2.35, 2000, ''),
  ('Bagaço de cana', 'Volumoso', 'Usina Santa Fé', 'kg', 50, 2.0, 48, 0.22, 8000, ''),
  ('Núcleo mineral', 'Mineral', 'NutriMax', 'kg', 98, 0, 0, 6.80, 300, '');

insert into movimentos (data, ingrediente_id, tipo, quantidade) values
  ('2026-06-15', 1, 'entrada', 12000),
  ('2026-06-15', 2, 'entrada', 5000),
  ('2026-06-15', 3, 'entrada', 20000),
  ('2026-06-15', 4, 'entrada', 600),
  ('2026-06-28', 1, 'saida', 5200),
  ('2026-06-28', 2, 'saida', 2100),
  ('2026-06-28', 3, 'saida', 9600),
  ('2026-06-28', 4, 'saida', 180);

insert into dietas (nome, categoria_animal, kg_animal_dia, itens) values
  ('Dieta Terminação Alto Grão', 'Boi terminação', 9.5,
   '[{"ingredienteId":1,"pct":68},{"ingredienteId":2,"pct":12},{"ingredienteId":3,"pct":18},{"ingredienteId":4,"pct":2}]');

-- Row Level Security: como é um app interno de teste sem login,
-- liberamos leitura/escrita pública (protegido só por quem tem a URL).
alter table ingredientes enable row level security;
alter table movimentos enable row level security;
alter table dietas enable row level security;

create policy "public full access" on ingredientes for all using (true) with check (true);
create policy "public full access" on movimentos for all using (true) with check (true);
create policy "public full access" on dietas for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Lotes e Saída de Ração
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- acima (ingredientes, movimentos, dietas) já existirem no seu projeto.
-- ===================================================================

create table lotes (
  id bigint generated always as identity primary key,
  nome text not null,
  numero_animais numeric default 0,
  data_inicio date,
  data_fim date
);

create table saidas_racao (
  id bigint generated always as identity primary key,
  data date not null,
  dieta_id bigint references dietas(id) on delete set null,
  lote_id bigint references lotes(id) on delete set null,
  quantidade_kg numeric default 0
);

-- vincula as movimentações de estoque geradas por uma saída de ração,
-- para que excluir a saída também desfaça o desconto no estoque
alter table movimentos add column saida_racao_id bigint references saidas_racao(id) on delete cascade;

alter table lotes enable row level security;
alter table saidas_racao enable row level security;

create policy "public full access" on lotes for all using (true) with check (true);
create policy "public full access" on saidas_racao for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Leitura de Cocho
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- lotes e saidas_racao (migração acima) já existirem no seu projeto.
-- ===================================================================

create table leituras_cocho (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete cascade,
  nota smallint not null check (nota between 1 and 4), -- 1 limpo · 2 bom · 3 pouco excesso · 4 muito excesso
  observacao text default ''
);

alter table leituras_cocho enable row level security;

create policy "public full access" on leituras_cocho for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Pasto e Financeiro
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
-- ===================================================================

create table pasto (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete set null,
  ingrediente_id bigint references ingredientes(id) on delete set null,
  quantidade numeric default 0
);

-- vincula as movimentações de estoque geradas por uma reposição de pasto,
-- para que excluir o registro também desfaça o desconto no estoque
alter table movimentos add column pasto_id bigint references pasto(id) on delete cascade;

create table custos_fixos (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria text,
  valor_mensal numeric default 0
);

alter table pasto enable row level security;
alter table custos_fixos enable row level security;

create policy "public full access" on pasto for all using (true) with check (true);
create policy "public full access" on custos_fixos for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Dietas de Confinamento x Pasto
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- O Pasto passa a usar uma dieta formulada (do tipo "pasto") em vez de
-- um ingrediente único, igual já funciona em Saída de Ração. A coluna
-- pasto.ingrediente_id não é mais usada pelo app, mas fica no banco
-- (não é apagada) para não perder o histórico de lançamentos antigos.
-- ===================================================================

alter table dietas add column tipo text default 'confinamento' check (tipo in ('confinamento','pasto'));
alter table pasto add column dieta_id bigint references dietas(id) on delete set null;

-- ===================================================================
-- MIGRAÇÃO: Investimentos
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- Registro de compras de animais, máquinas e outros bens — separado
-- dos Custos Fixos porque não é uma despesa operacional recorrente,
-- e não entra nos cálculos de custo diário/mensal do Financeiro.
-- ===================================================================

create table investimentos (
  id bigint generated always as identity primary key,
  nome text not null,
  categoria text,
  valor numeric default 0,
  data date
);

alter table investimentos enable row level security;

create policy "public full access" on investimentos for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Reprodução (lançamentos de sêmen e outros insumos)
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- Registro por data/lote do custo com sêmen e outros insumos usados na
-- inseminação — só aparece vinculado a lotes com "reprodução" no nome
-- (aba Reprodução). Entra no Financeiro como custo variável, igual
-- Saída de Ração e Pasto.
-- ===================================================================

create table reproducao_custos (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete cascade,
  item text not null,
  custo numeric default 0
);

alter table reproducao_custos enable row level security;

create policy "public full access" on reproducao_custos for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Receitas
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- Registro de venda de animais e outras receitas da operação, por
-- data e (opcionalmente) lote. Usado no Financeiro para o
-- demonstrativo de Despesa vs Receita do mês.
-- ===================================================================

create table receitas (
  id bigint generated always as identity primary key,
  data date not null,
  lote_id bigint references lotes(id) on delete set null,
  descricao text not null,
  arrobas numeric,
  valor numeric default 0
);

alter table receitas enable row level security;

create policy "public full access" on receitas for all using (true) with check (true);

-- ===================================================================
-- MIGRAÇÃO: Preço da arroba e meta de margem
-- Rode só este bloco abaixo no SQL Editor do Supabase se as tabelas
-- das migrações acima já existirem no seu projeto.
--
-- precos_arroba: histórico do valor médio da arroba (atualizado
-- manualmente, ex: consultando o app Indicador do Boi Datagro), usado
-- no banner do topo do Resumo do Financeiro.
-- config_financeiro: linha única (id=1) com a meta de margem (%),
-- usada para comparar com a margem real do mês.
-- ===================================================================

create table precos_arroba (
  id bigint generated always as identity primary key,
  data date not null,
  valor numeric default 0
);

alter table precos_arroba enable row level security;

create policy "public full access" on precos_arroba for all using (true) with check (true);

create table config_financeiro (
  id bigint primary key,
  meta_margem_pct numeric
);

alter table config_financeiro enable row level security;

create policy "public full access" on config_financeiro for all using (true) with check (true);
