-- ===================================================================
-- AE Cana — schema Fase 1 (Fundação + Cadastros base)
-- ===================================================================
-- Este schema roda num projeto Supabase PRÓPRIO e SEPARADO dos projetos
-- usados por AEpecuaria.html, AECombustivel.html e AECereais.html — cada
-- app tem seu próprio banco, login e financeiro, sem depender uns dos
-- outros nem duplicar dado entre si (o hub AE Matriz é quem, opcionalmente,
-- lê indicadores de cada um pra montar uma visão consolidada — ver
-- matriz_schema.sql e a seção "AE Matriz" do README).
--
-- PASSO A PASSO PARA COLOCAR NO AR:
-- 1. Crie um novo projeto em https://supabase.com (organização da empresa).
-- 2. SQL Editor > cole e rode este arquivo inteiro.
-- 3. Authentication > Users > Add user: crie sua conta (ex. email
--    eduardo@aeagropecuaria.local, "Auto Confirm User" marcado). Anote o UUID.
-- 4. Rode o INSERT no final deste arquivo (troque o UUID e o nome) para
--    virar o primeiro administrador.
-- 5. Project Settings > API: copie a "Project URL" e a "anon public key"
--    e cole nas constantes no topo do AECana.html.
-- 6. Deploy da Edge Function supabase/functions/criar-usuario-cana
--    (necessária para o admin criar novos usuários pela tela de Administração).
-- ===================================================================

-- ---------- LOGIN E PERMISSÕES (mesmo padrão do AECombustivel.html) ----------

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  usuario text not null unique, -- login (sem @dominio)
  papel text not null default 'operador' check (papel in ('admin','proprietario','gestor','encarregado','colaborador','operador')),
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
-- "frente" segue o mesmo enum usado nos outros apps (cana/graos/pecuaria)
-- por consistência de código — neste banco só cultura de frente 'cana'
-- é usada de fato, mas o enum não precisa ser mais estreito que isso.
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
-- Ano-safra de uma cultura numa fazenda (ex: Cana 2024/2025 na Fazenda X).
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

-- fazendas/culturas/safras/talhoes_areas/centros_custo: qualquer um com
-- 'cadastros' vê; só quem tem 'cadastros':'editar' cria/edita/exclui —
-- mesmo padrão de módulo único pros cadastros de base que o AE
-- Combustível usa.
do $$
declare
  t text;
begin
  foreach t in array array['fazendas','culturas','safras','centros_custo','talhoes_areas']
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
-- AE Cana — schema Fase 2 (Operações: Plantio)
-- ===================================================================
-- Continuação deste mesmo arquivo — rode tudo de uma vez, na ordem em
-- que aparece (Fase 1 acima já criou fazendas/talhoes_areas/safras/
-- tem_permissao()/trg_set_updated(), usados abaixo).
-- ===================================================================

-- ---------- PLANTIO (cana) ----------
-- Uma linha por estande de cana num talhão: da data de plantio até a
-- reforma. Não modela cada corte/soca individualmente — isso entra no
-- módulo de Colheita (fase seguinte), que vai referenciar este plantio.
create table plantios_cana (
  id bigint generated always as identity primary key,
  talhao_id bigint not null references talhoes_areas(id),
  safra_id bigint references safras(id),
  variedade text not null,
  data_plantio date not null,
  data_reforma_prevista date,
  observacao text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_plantios_cana_talhao on plantios_cana(talhao_id);
create index idx_plantios_cana_safra on plantios_cana(safra_id);
-- só um plantio ativo (estande em produção) por talhão de cada vez —
-- uma reforma marca o plantio antigo como inativo antes de criar o novo.
create unique index uq_plantios_cana_talhao_ativo on plantios_cana(talhao_id) where ativo;
create trigger set_updated before update on plantios_cana for each row execute function trg_set_updated();

alter table plantios_cana enable row level security;
create policy "select plantios_cana" on plantios_cana for select using (tem_permissao('operacoes','visualizar'));
create policy "inserir plantios_cana" on plantios_cana for insert with check (tem_permissao('operacoes','editar'));
create policy "atualizar plantios_cana" on plantios_cana for update using (tem_permissao('operacoes','editar')) with check (tem_permissao('operacoes','editar'));
create policy "excluir plantios_cana" on plantios_cana for delete using (tem_permissao('operacoes','editar'));

-- ===================================================================
-- AE Cana — schema Fase 3 (Operações: Tratos culturais)
-- ===================================================================
-- Continuação deste mesmo arquivo — rode as migrações em sequência
-- (Fase 2 acima, depois esta).
--
-- Cria o cadastro de Insumos (defensivos/fertilizantes), as Entradas
-- de estoque (compra) e as Aplicações (o lançamento de trato cultural
-- em campo, que desconta o insumo do estoque na quantidade aplicada).
-- O saldo e o preço médio ponderado de cada insumo são calculados no
-- app a partir de Entradas e Aplicações — não ficam guardados numa
-- coluna própria — mesmo padrão que o AE Combustível já usa para o
-- saldo de tanque (saldoTanque/custoMedioPonderado).
-- ===================================================================

-- ---------- INSUMOS ----------
create table insumos_cana (
  id bigint generated always as identity primary key,
  nome text not null unique,
  categoria text not null check (categoria in ('herbicida','inseticida','fungicida','adubo','corretivo','outro')),
  unidade text not null default 'L',
  estoque_minimo numeric(12,2),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on insumos_cana for each row execute function trg_set_updated();

-- ---------- ENTRADAS DE INSUMO ----------
create table entradas_insumo_cana (
  id bigint generated always as identity primary key,
  insumo_id bigint not null references insumos_cana(id),
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
create index idx_entradas_insumo_cana_insumo on entradas_insumo_cana(insumo_id);
create trigger set_updated before update on entradas_insumo_cana for each row execute function trg_set_updated();

-- ---------- APLICAÇÕES (trato cultural em campo) ----------
create table aplicacoes_cana (
  id bigint generated always as identity primary key,
  talhao_id bigint not null references talhoes_areas(id),
  insumo_id bigint not null references insumos_cana(id),
  data date not null,
  tipo_operacao text not null check (tipo_operacao in ('adubacao','herbicida','inseticida','fungicida','cultivo_mecanico','outro')),
  quantidade numeric(12,2) not null check (quantidade > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_aplicacoes_cana_talhao on aplicacoes_cana(talhao_id);
create index idx_aplicacoes_cana_insumo on aplicacoes_cana(insumo_id);
create trigger set_updated before update on aplicacoes_cana for each row execute function trg_set_updated();

alter table insumos_cana enable row level security;
alter table entradas_insumo_cana enable row level security;
alter table aplicacoes_cana enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['insumos_cana','entradas_insumo_cana','aplicacoes_cana']
  loop
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''operacoes'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''operacoes'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''operacoes'',''editar'')) with check (tem_permissao(''operacoes'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''operacoes'',''editar''));', t);
  end loop;
end $$;

-- ===================================================================
-- AE Cana — schema Fase 4 (Operações: Colheita/Produção)
-- ===================================================================
-- Continuação deste mesmo arquivo — rode as migrações em sequência
-- (Fases 2 e 3 acima, depois esta).
--
-- Cria o registro de Colheita por talhão: toneladas colhidas, com TCH
-- (toneladas por hectare) calculado no app a partir da área do talhão.
-- ===================================================================

create table colheitas_cana (
  id bigint generated always as identity primary key,
  talhao_id bigint not null references talhoes_areas(id),
  safra_id bigint references safras(id),
  data date not null,
  corte integer check (corte >= 1), -- 1 = cana-planta, 2 = 1ª soca, 3 = 2ª soca...
  toneladas numeric(12,2) not null check (toneladas > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_colheitas_cana_talhao on colheitas_cana(talhao_id);
create index idx_colheitas_cana_safra on colheitas_cana(safra_id);
create trigger set_updated before update on colheitas_cana for each row execute function trg_set_updated();

alter table colheitas_cana enable row level security;
create policy "select colheitas_cana" on colheitas_cana for select using (tem_permissao('operacoes','visualizar'));
create policy "inserir colheitas_cana" on colheitas_cana for insert with check (tem_permissao('operacoes','editar'));
create policy "atualizar colheitas_cana" on colheitas_cana for update using (tem_permissao('operacoes','editar')) with check (tem_permissao('operacoes','editar'));
create policy "excluir colheitas_cana" on colheitas_cana for delete using (tem_permissao('operacoes','editar'));

-- ===================================================================
-- AE Cana — schema Fase 5 (Financeiro/Resultados: Despesas e Receita)
-- ===================================================================
-- Continuação deste mesmo arquivo — rode as migrações em sequência
-- (Fases 2 a 4 acima, depois esta).
--
-- Cria Despesas gerais da lavoura (mão de obra, colheita terceirizada,
-- transporte...) e Receita (venda/entrega de cana à usina). O custo de
-- insumo (Aplicações, Fase 3) já existia; Despesas cobre o que não é
-- insumo lançado lá. Receita usa um módulo de permissão PRÓPRIO
-- ('resultados'), separado de 'financeiro' — mesmo racional do
-- AEpecuária: nem todo mundo que vê custo de insumo deve ver receita
-- ou resultado (margem) da operação.
-- ===================================================================

create table despesas_cana (
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
create index idx_despesas_cana_fazenda on despesas_cana(fazenda_id);
create index idx_despesas_cana_talhao on despesas_cana(talhao_id);
create trigger set_updated before update on despesas_cana for each row execute function trg_set_updated();

alter table despesas_cana enable row level security;
create policy "select despesas_cana" on despesas_cana for select using (tem_permissao('financeiro','visualizar'));
create policy "inserir despesas_cana" on despesas_cana for insert with check (tem_permissao('financeiro','editar'));
create policy "atualizar despesas_cana" on despesas_cana for update using (tem_permissao('financeiro','editar')) with check (tem_permissao('financeiro','editar'));
create policy "excluir despesas_cana" on despesas_cana for delete using (tem_permissao('financeiro','editar'));

create table receitas_cana (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  talhao_id bigint references talhoes_areas(id),
  safra_id bigint references safras(id),
  data date not null,
  toneladas numeric(12,2),
  valor_total numeric(12,2) not null check (valor_total > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_receitas_cana_fazenda on receitas_cana(fazenda_id);
create index idx_receitas_cana_talhao on receitas_cana(talhao_id);
create trigger set_updated before update on receitas_cana for each row execute function trg_set_updated();

alter table receitas_cana enable row level security;
-- Leitura só para quem tem 'resultados' (receita/lucratividade fica
-- restrita — só Administrador por padrão, mais quem o admin liberar
-- explicitamente, ex: o(a) proprietário(a)). Quem só tem 'financeiro'
-- consegue INSERIR uma receita (lançamento "cego": lança, mas não
-- lê a lista nem os valores já lançados) — não consegue editar nem
-- excluir um lançamento já existente, porque nem consegue vê-lo.
create policy "select receitas_cana" on receitas_cana for select using (tem_permissao('resultados','visualizar'));
create policy "inserir receitas_cana" on receitas_cana for insert with check (tem_permissao('resultados','editar') or tem_permissao('financeiro','editar'));
create policy "atualizar receitas_cana" on receitas_cana for update using (tem_permissao('resultados','editar')) with check (tem_permissao('resultados','editar'));
create policy "excluir receitas_cana" on receitas_cana for delete using (tem_permissao('resultados','editar'));

-- ===================================================================
-- MIGRAÇÃO: novos perfis (Proprietário, Colaborador)
-- Se você já rodou este arquivo antes desta atualização, a tabela
-- profiles ainda só aceita papel in ('admin','gestor','encarregado',
-- 'operador'). Este comando troca a regra pra também aceitar
-- 'proprietario' e 'colaborador' — cada um continua funcionando com
-- as mesmas permissões por módulo configuradas na tela de Usuários
-- (papel aqui é só rótulo/organização, quem manda é a permissão).
-- Pode rodar a qualquer momento.
-- ===================================================================
alter table profiles drop constraint if exists profiles_papel_check;
alter table profiles add constraint profiles_papel_check
  check (papel in ('admin','proprietario','gestor','encarregado','colaborador','operador'));
