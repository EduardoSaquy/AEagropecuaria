-- ============================================================
-- AE MATRIZ — schema inicial
--
-- Rode este arquivo do começo ao fim, num projeto Supabase NOVO e
-- separado dos projetos da Pecuária e do Combustível (a matriz não
-- duplica os dados desses apps — ela só lê alguns indicadores deles
-- diretamente do navegador, e mantém seu próprio cadastro central
-- de fazendas, apps e usuários).
--
-- Depois de rodar este arquivo:
-- 1. No painel do Supabase: Authentication > Users > Add user. Crie
--    sua própria conta (email pode ser fake, ex:
--    eduardo@aeagropecuaria.local, marcando "Auto Confirm User").
--    Anote o UUID gerado.
-- 2. Rode o insert manual no final deste arquivo, trocando o UUID
--    e o nome, para virar o primeiro administrador da matriz.
-- 3. Publique a Edge Function `criar-usuario-matriz` (usada pela
--    tela de Usuários para criar novas contas).
-- ============================================================

-- ---------- FAZENDAS ----------
create table fazendas (
  id bigint generated always as identity primary key,
  nome text not null,
  area_ha numeric,
  localizacao text,
  observacao text,
  created_at timestamptz not null default now()
);

alter table fazendas enable row level security;

-- ---------- APPS (registro dos apps que compõem a matriz) ----------
create table apps (
  id bigint generated always as identity primary key,
  nome text not null,
  slug text not null unique,
  descricao text,
  url text,
  cor text not null default '#1D5DA8',
  ordem int not null default 0,
  status text not null default 'em_breve' check (status in ('ativo','em_breve')),
  created_at timestamptz not null default now()
);

alter table apps enable row level security;

-- Semente inicial: os dois apps que já existem, e os dois que estão
-- planejados (cana e cereais) — sem URL ainda, mostrados como
-- "em breve" até serem publicados. Dá pra editar tudo isso depois
-- pela tela de Apps, sem precisar mexer em código.
insert into apps (nome, slug, descricao, url, cor, ordem, status) values
  ('AE Pecuária', 'pecuaria', 'Gestão nutricional, estoque e financeiro do confinamento, cria e pasto.', 'https://eduardosaquy.github.io/AEagropecuaria/AEpecuaria.html', '#1D5DA8', 1, 'ativo'),
  ('AE Combustível', 'combustivel', 'Controle de estoque e abastecimento de diesel, Arla 32 e gasolina das frentes de cana, grãos e pecuária.', 'https://eduardosaquy.github.io/AEagropecuaria/AECombustivel.html', '#C98A2B', 2, 'em_breve'),
  ('AE Cana', 'cana', 'Gestão da operação de cana-de-açúcar.', null, '#0C7A43', 3, 'em_breve'),
  ('AE Cereais', 'cereais', 'Gestão da operação de grãos e cereais.', null, '#8A5A2B', 4, 'em_breve');

-- ---------- PROFILES (login central da matriz) ----------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  usuario text not null unique, -- nome de usuário do login (sem @dominio)
  papel text not null default 'gestor' check (papel in ('admin','gestor')),
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;

-- funções auxiliares (security definer + search_path fixo, para não
-- herdar permissão de quem chama nem sofrer sequestro de search_path)
create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from profiles where id = auth.uid() and papel = 'admin' and ativo = true
  );
$$;

create or replace function esta_logado() returns boolean
language sql security definer set search_path = public stable as $$
  select auth.uid() is not null;
$$;

-- profiles: cada um vê o próprio perfil; admin vê e gerencia todos
create policy "ver proprio perfil ou admin ve todos" on profiles for select
  using (auth.uid() = id or is_admin());
create policy "admin cria perfis" on profiles for insert with check (is_admin());
create policy "admin atualiza perfis" on profiles for update using (is_admin()) with check (is_admin());
create policy "admin exclui perfis" on profiles for delete using (is_admin());

-- fazendas e apps: qualquer pessoa logada na matriz pode ver;
-- só admin cria/edita/exclui
create policy "logados veem fazendas" on fazendas for select using (esta_logado());
create policy "admin cria fazendas" on fazendas for insert with check (is_admin());
create policy "admin edita fazendas" on fazendas for update using (is_admin()) with check (is_admin());
create policy "admin exclui fazendas" on fazendas for delete using (is_admin());

create policy "logados veem apps" on apps for select using (esta_logado());
create policy "admin cria apps" on apps for insert with check (is_admin());
create policy "admin edita apps" on apps for update using (is_admin()) with check (is_admin());
create policy "admin exclui apps" on apps for delete using (is_admin());

-- ---------- PRIMEIRO ADMINISTRADOR ----------
-- Troque o UUID (o mesmo criado em Authentication > Users) e o nome,
-- e rode este insert manualmente depois do resto do arquivo.
-- insert into profiles (id, nome, usuario, papel, ativo) values
--   ('COLE-O-UUID-AQUI', 'Seu Nome', 'seu.usuario', 'admin', true);
