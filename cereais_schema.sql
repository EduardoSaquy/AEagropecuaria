-- ===================================================================
-- AE Cereais — schema Fase 1 (Fundação + Cadastros base)
-- ===================================================================
-- Este schema roda num projeto Supabase PRÓPRIO e SEPARADO dos projetos
-- usados por AEpecuaria.html, AECombustivel.html e AECana.html — cada
-- app tem seu próprio banco, login e financeiro, sem depender uns dos
-- outros nem duplicar dado entre si (o hub AE Matriz é quem, opcionalmente,
-- lê indicadores de cada um pra montar uma visão consolidada — ver
-- matriz_schema.sql e a seção "AE Matriz" do README).
--
-- A frente de negócio usada nos filtros é 'graos' (mesmo código usado
-- pelos outros apps para Soja/Milho/Sorgo/Feijão) — "Cereais" é só o
-- nome comercial deste app.
--
-- Diferente da cana (perene, um "estande" atravessa vários cortes),
-- grão é cultura anual: cada talhão passa por um Plantio -> uma
-- Colheita por safra, podendo repetir no mesmo ano (ex: soja no verão,
-- milho safrinha em seguida) — por isso Plantio e Colheita aqui também
-- guardam a Cultura do lançamento (não só a do talhão), para não
-- misturar as safras quando o talhão roda de cultura.
--
-- PASSO A PASSO PARA COLOCAR NO AR:
-- 1. Crie um novo projeto em https://supabase.com (organização da empresa).
-- 2. SQL Editor > cole e rode este arquivo inteiro.
-- 3. Authentication > Users > Add user: crie sua conta (ex. email
--    eduardo@aeagropecuaria.local, "Auto Confirm User" marcado). Anote o UUID.
-- 4. Rode o INSERT no final da seção Fase 1 (troque o UUID e o nome) para
--    virar o primeiro administrador.
-- 5. Project Settings > API: copie a "Project URL" e a "anon public key"
--    e cole nas constantes no topo do AECereais.html.
-- 6. Deploy da Edge Function supabase/functions/criar-usuario-cereais
--    (necessária para o admin criar novos usuários pela tela de Administração).
-- ===================================================================

-- ---------- LOGIN E PERMISSÕES (mesmo padrão do AECombustivel.html) ----------

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  usuario text not null unique, -- login (sem @dominio)
  papel text not null default 'operador' check (papel in ('admin','gestor','encarregado','operador')),
  permissoes jsonb not null default '{}'::jsonb, -- {"cadastros":"editar",...}
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;

create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from profiles where id = auth.uid() and papel = 'admin' and ativo = true
  );
$$;

create or replace function tem_permissao(modulo text, nivel text) returns boolean
language sql security definer set search_path = public stable as $$
  select case
    when is_admin() then true
    when nivel = 'visualizar' then (
      select permissoes->>modulo in ('visualizar','editar')
      from profiles where id = auth.uid() and ativo = true
    )
    else (
      select permissoes->>modulo = 'editar'
      from profiles where id = auth.uid() and ativo = true
    )
  end;
$$;

create policy "ver proprio perfil ou admin ve todos" on profiles for select
  using (auth.uid() = id or is_admin());
create policy "admin cria perfis" on profiles for insert with check (is_admin());
create policy "admin atualiza perfis" on profiles for update using (is_admin()) with check (is_admin());
create policy "admin exclui perfis" on profiles for delete using (is_admin());

-- Trigger reutilizável: mantém updated_at/updated_by corretos em qualquer
-- update, sem depender do front-end lembrar de mandar esses campos.
create or replace function trg_set_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

-- ---------- FAZENDAS ----------
create table fazendas (
  id bigint generated always as identity primary key,
  nome text not null,
  estado text not null check (estado in ('TO','SP')),
  area_ha numeric(12,2),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on fazendas for each row execute function trg_set_updated();

-- ---------- CULTURAS ----------
create table culturas (
  id bigint generated always as identity primary key,
  nome text not null unique,
  frente text not null check (frente in ('cana','graos','pecuaria')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on culturas for each row execute function trg_set_updated();

-- ---------- SAFRAS ----------
create table safras (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  cultura_id bigint not null references culturas(id),
  nome text not null, -- ex: "2024/2025"
  data_inicio date,
  data_fim date,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id),
  unique (fazenda_id, cultura_id, nome)
);
create index idx_safras_fazenda on safras(fazenda_id);
create index idx_safras_cultura on safras(cultura_id);
create trigger set_updated before update on safras for each row execute function trg_set_updated();

-- ---------- TALHÕES / ÁREAS ----------
create table talhoes_areas (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  nome text not null,
  tipo text not null check (tipo in ('talhao','lote_curral')),
  area_ha numeric(12,2),
  cultura_id bigint references culturas(id),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id),
  unique (fazenda_id, nome)
);
create index idx_talhoes_fazenda on talhoes_areas(fazenda_id);
create index idx_talhoes_cultura on talhoes_areas(cultura_id);
create trigger set_updated before update on talhoes_areas for each row execute function trg_set_updated();

-- ---------- CENTROS DE CUSTO ----------
-- Usado pra despesa geral que não é de um talhão específico (ex: escritório,
-- estrutura fixa da lavoura).
create table centros_custo (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  nome text not null,
  frente text not null check (frente in ('cana','graos','pecuaria','geral')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id),
  unique (fazenda_id, nome)
);
create index idx_centros_custo_fazenda on centros_custo(fazenda_id);
create trigger set_updated before update on centros_custo for each row execute function trg_set_updated();

-- fazendas/culturas/safras/talhoes_areas/centros_custo: qualquer um com
-- 'cadastros' vê; só quem tem 'cadastros':'editar' cria/edita/exclui.
do $$
declare
  t text;
begin
  foreach t in array array['fazendas','culturas','safras','talhoes_areas','centros_custo']
  loop
    execute format('alter table %1$s enable row level security;', t);
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''cadastros'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''cadastros'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''cadastros'',''editar'')) with check (tem_permissao(''cadastros'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''cadastros'',''editar''));', t);
  end loop;
end $$;

-- ---------- PRIMEIRO ADMINISTRADOR ----------
-- Troque o UUID (o mesmo criado em Authentication > Users) e o nome,
-- e rode este insert manualmente depois do resto do arquivo.
-- insert into profiles (id, nome, usuario, papel, permissoes, ativo) values
--   ('COLE-O-UUID-AQUI', 'Seu Nome', 'seu.usuario', 'admin', '{}'::jsonb, true);

-- ===================================================================
-- AE Cereais — schema Fase 2 (Operações: Plantio, Tratos culturais e Colheita)
-- ===================================================================
-- Continuação deste mesmo arquivo — rode tudo de uma vez, na ordem em
-- que aparece (Fase 1 acima já criou fazendas/talhoes_areas/safras/
-- culturas/tem_permissao()/trg_set_updated(), usados abaixo).
-- ===================================================================

-- ---------- PLANTIO (cereais/grãos) ----------
-- Uma linha por safra plantada num talhão: cultura, cultivar e data de
-- plantio, com previsão de colheita. Diferente da cana, não há
-- "reforma" — o plantio é encerrado (ativo=false) quando a safra é
-- colhida, liberando o talhão para o próximo plantio.
create table plantios_graos (
  id bigint generated always as identity primary key,
  talhao_id bigint not null references talhoes_areas(id),
  safra_id bigint references safras(id),
  cultura_id bigint references culturas(id),
  cultivar text not null,
  data_plantio date not null,
  data_previsao_colheita date,
  observacao text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_plantios_graos_talhao on plantios_graos(talhao_id);
create index idx_plantios_graos_safra on plantios_graos(safra_id);
create index idx_plantios_graos_cultura on plantios_graos(cultura_id);
-- só um plantio ativo (safra em pé) por talhão de cada vez — a colheita
-- marca o plantio antigo como inativo antes de criar o próximo.
create unique index uq_plantios_graos_talhao_ativo on plantios_graos(talhao_id) where ativo;
create trigger set_updated before update on plantios_graos for each row execute function trg_set_updated();

alter table plantios_graos enable row level security;
create policy "select plantios_graos" on plantios_graos for select using (tem_permissao('operacoes_graos','visualizar'));
create policy "inserir plantios_graos" on plantios_graos for insert with check (tem_permissao('operacoes_graos','editar'));
create policy "atualizar plantios_graos" on plantios_graos for update using (tem_permissao('operacoes_graos','editar')) with check (tem_permissao('operacoes_graos','editar'));
create policy "excluir plantios_graos" on plantios_graos for delete using (tem_permissao('operacoes_graos','editar'));

-- ---------- INSUMOS ----------
-- Mesmas categorias da cana, mais 'semente' — em grãos a semente
-- (com tratamento/inoculante) é um insumo relançado a cada safra.
create table insumos_graos (
  id bigint generated always as identity primary key,
  nome text not null unique,
  categoria text not null check (categoria in ('semente','herbicida','inseticida','fungicida','adubo','corretivo','outro')),
  unidade text not null default 'L',
  estoque_minimo numeric(12,2),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on insumos_graos for each row execute function trg_set_updated();

-- ---------- ENTRADAS DE INSUMO ----------
create table entradas_insumo_graos (
  id bigint generated always as identity primary key,
  insumo_id bigint not null references insumos_graos(id),
  data date not null,
  quantidade numeric(12,2) not null check (quantidade > 0),
  preco_pago numeric(12,4),
  fornecedor text,
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_entradas_insumo_graos_insumo on entradas_insumo_graos(insumo_id);
create trigger set_updated before update on entradas_insumo_graos for each row execute function trg_set_updated();

-- ---------- APLICAÇÕES (trato cultural em campo) ----------
-- Além dos tipos de operação da cana, inclui 'dessecacao' (herbicida
-- de pré-plantio, muito comum em grãos) e 'semeadura' (a própria
-- semeadura, quando entra como lançamento de insumo/semente).
create table aplicacoes_graos (
  id bigint generated always as identity primary key,
  talhao_id bigint not null references talhoes_areas(id),
  insumo_id bigint not null references insumos_graos(id),
  data date not null,
  tipo_operacao text not null check (tipo_operacao in ('dessecacao','semeadura','adubacao','herbicida','inseticida','fungicida','cultivo_mecanico','outro')),
  quantidade numeric(12,2) not null check (quantidade > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_aplicacoes_graos_talhao on aplicacoes_graos(talhao_id);
create index idx_aplicacoes_graos_insumo on aplicacoes_graos(insumo_id);
create trigger set_updated before update on aplicacoes_graos for each row execute function trg_set_updated();

alter table insumos_graos enable row level security;
alter table entradas_insumo_graos enable row level security;
alter table aplicacoes_graos enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['insumos_graos','entradas_insumo_graos','aplicacoes_graos']
  loop
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''operacoes_graos'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''operacoes_graos'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''operacoes_graos'',''editar'')) with check (tem_permissao(''operacoes_graos'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''operacoes_graos'',''editar''));', t);
  end loop;
end $$;

-- ---------- COLHEITA/PRODUÇÃO ----------
-- Quantidade colhida em sacas de 60kg (padrão de mercado para
-- soja/milho/sorgo/feijão) — a produtividade (sc/ha) é calculada no
-- app a partir da área do talhão, o equivalente ao TCH da cana.
create table colheitas_graos (
  id bigint generated always as identity primary key,
  talhao_id bigint not null references talhoes_areas(id),
  safra_id bigint references safras(id),
  cultura_id bigint references culturas(id),
  data date not null,
  sacas numeric(12,2) not null check (sacas > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_colheitas_graos_talhao on colheitas_graos(talhao_id);
create index idx_colheitas_graos_safra on colheitas_graos(safra_id);
create index idx_colheitas_graos_cultura on colheitas_graos(cultura_id);
create trigger set_updated before update on colheitas_graos for each row execute function trg_set_updated();

alter table colheitas_graos enable row level security;
create policy "select colheitas_graos" on colheitas_graos for select using (tem_permissao('operacoes_graos','visualizar'));
create policy "inserir colheitas_graos" on colheitas_graos for insert with check (tem_permissao('operacoes_graos','editar'));
create policy "atualizar colheitas_graos" on colheitas_graos for update using (tem_permissao('operacoes_graos','editar')) with check (tem_permissao('operacoes_graos','editar'));
create policy "excluir colheitas_graos" on colheitas_graos for delete using (tem_permissao('operacoes_graos','editar'));

-- ===================================================================
-- AE Cereais — schema Fase 3 (Financeiro: Despesas)
-- ===================================================================
-- Continuação deste mesmo arquivo — rode as migrações em sequência
-- (Fases 1 e 2 acima, depois esta).
--
-- Despesas gerais da lavoura (mão de obra, colheita terceirizada,
-- transporte...) que não são insumo lançado em Aplicações. Uma despesa
-- pode marcar um talhão específico, um centro de custo, os dois ou
-- nenhum — Financeiro > Custo por Talhão (AECereais.html) usa isso pra
-- ratear despesa sem talhão marcado entre os talhões com plantio
-- ativo, proporcional à área de cada um.
-- ===================================================================

create table despesas_graos (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  talhao_id bigint references talhoes_areas(id),
  centro_custo_id bigint references centros_custo(id),
  data date not null,
  categoria text not null check (categoria in ('mao_obra','colheita_terceirizada','transporte','arrendamento','manutencao','outro')),
  descricao text not null,
  valor numeric(12,2) not null check (valor > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_despesas_graos_fazenda on despesas_graos(fazenda_id);
create index idx_despesas_graos_talhao on despesas_graos(talhao_id);
create trigger set_updated before update on despesas_graos for each row execute function trg_set_updated();

alter table despesas_graos enable row level security;
create policy "select despesas_graos" on despesas_graos for select using (tem_permissao('financeiro_graos','visualizar'));
create policy "inserir despesas_graos" on despesas_graos for insert with check (tem_permissao('financeiro_graos','editar'));
create policy "atualizar despesas_graos" on despesas_graos for update using (tem_permissao('financeiro_graos','editar')) with check (tem_permissao('financeiro_graos','editar'));
create policy "excluir despesas_graos" on despesas_graos for delete using (tem_permissao('financeiro_graos','editar'));
