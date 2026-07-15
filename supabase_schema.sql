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
