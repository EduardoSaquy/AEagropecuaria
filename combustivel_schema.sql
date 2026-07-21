-- ===================================================================
-- AE Combustível — schema Fase 1 (Fundação + Cadastros base)
-- ===================================================================
-- Este schema roda num projeto Supabase PRÓPRIO e SEPARADO do projeto
-- usado pelo AEpecuaria.html. Não altera nada do banco da pecuária.
--
-- PASSO A PASSO PARA COLOCAR NO AR:
-- 1. Crie um novo projeto em https://supabase.com (organização da empresa).
-- 2. SQL Editor > cole e rode este arquivo inteiro.
-- 3. Authentication > Users > Add user: crie sua conta (ex. email
--    eduardo@aeagropecuaria.local, "Auto Confirm User" marcado). Anote o UUID.
-- 4. Rode o INSERT no final deste arquivo (troque o UUID e o nome) para
--    virar o primeiro administrador.
-- 5. Project Settings > API: copie a "Project URL" e a "anon public key"
--    e cole nas constantes no topo do AECombustivel.html.
-- 6. Deploy da Edge Function supabase/functions/criar-usuario-combustivel
--    (necessária para o admin criar novos usuários pela tela de Administração).
-- ===================================================================

-- ---------- LOGIN E PERMISSÕES (mesmo padrão do AEpecuaria.html) ----------

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
-- Unidade produtiva. estado limitado a TO/SP porque é onde a empresa
-- opera hoje; ampliar o check quando (se) abrir fazenda em outro estado.
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

-- ---------- CATÁLOGOS GLOBAIS ----------
-- Produtos, culturas e operações são taxonomia compartilhada por todas as
-- fazendas e frentes (não fazem sentido duplicados por fazenda_id), por
-- isso não levam fazenda_id — igual a como "ingredientes"/"dietas" já
-- funcionam no app da pecuária hoje.

create table produtos (
  id bigint generated always as identity primary key,
  nome text not null unique,
  tipo text not null check (tipo in ('diesel_s10','diesel_s500','arla32','gasolina','outro')),
  unidade text not null default 'L',
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on produtos for each row execute function trg_set_updated();

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

create table operacoes (
  id bigint generated always as identity primary key,
  nome text not null unique,
  frente text not null check (frente in ('cana','graos','pecuaria','geral')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on operacoes for each row execute function trg_set_updated();

-- ---------- FORNECEDORES ----------
create table fornecedores (
  id bigint generated always as identity primary key,
  nome text not null,
  cnpj text,
  telefone text,
  obs text,
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on fornecedores for each row execute function trg_set_updated();

-- ---------- SAFRAS ----------
-- Ano-safra de uma cultura numa fazenda (ex: Soja 2024/2025 na Fazenda X).
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
-- Usado para ratear combustível quando não há um talhão/lote específico
-- (ex: gerador da sede, veículo de apoio, administrativo).
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
-- Representa tanto talhão de lavoura (cana/grãos, com hectares) quanto
-- lote/curral de pecuária (referência só por nome, sem duplicar o
-- cadastro que já existe no app da pecuária — o vínculo aqui é só para
-- ratear combustível, não para controlar o lote em si).
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

-- ---------- EQUIPAMENTOS ----------
create table equipamentos (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  nome text not null,
  tipo text not null check (tipo in (
    'colhedora_cana','transbordo','caminhao_canavieiro',
    'colhedora_graos','plantadeira','pulverizador','secador',
    'trator','gerador','veiculo_apoio','moto','outro'
  )),
  tipo_medidor text not null check (tipo_medidor in ('horimetro','hodometro','nenhum')),
  consumo_referencia numeric(10,2), -- L/h se horímetro, L/km se hodômetro
  frente_principal text not null check (frente_principal in ('cana','graos','pecuaria','geral')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id),
  unique (fazenda_id, nome)
);
create index idx_equipamentos_fazenda on equipamentos(fazenda_id);
create trigger set_updated before update on equipamentos for each row execute function trg_set_updated();

-- ---------- OPERADORES ----------
-- profile_id é opcional: nem todo operador de máquina/abastecedor
-- precisa ter login no sistema.
create table operadores (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  nome text not null,
  cpf text,
  profile_id uuid references profiles(id),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_operadores_fazenda on operadores(fazenda_id);
create index idx_operadores_profile on operadores(profile_id);
create trigger set_updated before update on operadores for each row execute function trg_set_updated();

-- ---------- TANQUES ----------
create table tanques (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  nome text not null,
  produto_id bigint not null references produtos(id),
  capacidade_litros numeric(12,2) not null check (capacidade_litros > 0),
  tipo text not null check (tipo in ('fixo','comboio')),
  fornecedor_id bigint references fornecedores(id), -- comodato, quando houver
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id),
  unique (fazenda_id, nome)
);
create index idx_tanques_fazenda on tanques(fazenda_id);
create index idx_tanques_produto on tanques(produto_id);
create trigger set_updated before update on tanques for each row execute function trg_set_updated();

-- ===================================================================
-- RLS — todas as tabelas de cadastro ficam sob o módulo único
-- 'cadastros' (visualizar/editar). O módulo 'estoque' é adicionado mais
-- abaixo, na migração da Fase 2. Quando a Fase 4 (abastecimento)
-- chegar, o módulo 'abastecimento' entra do mesmo jeito, sem mexer no
-- que já está aqui.
-- ===================================================================

alter table fazendas enable row level security;
alter table produtos enable row level security;
alter table culturas enable row level security;
alter table operacoes enable row level security;
alter table fornecedores enable row level security;
alter table safras enable row level security;
alter table centros_custo enable row level security;
alter table talhoes_areas enable row level security;
alter table equipamentos enable row level security;
alter table operadores enable row level security;
alter table tanques enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'fazendas','produtos','culturas','operacoes','fornecedores',
    'safras','centros_custo','talhoes_areas','equipamentos','operadores','tanques'
  ]
  loop
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''cadastros'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''cadastros'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''cadastros'',''editar'')) with check (tem_permissao(''cadastros'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''cadastros'',''editar''));', t);
  end loop;
end $$;

-- ===================================================================
-- SEED — catálogos globais já conhecidos (produto, cultura, operação),
-- citados no escopo do projeto. Fazendas/tanques/equipamentos ficam
-- para cadastro manual, pois são específicos da empresa.
-- ===================================================================

insert into produtos (nome, tipo) values
  ('Diesel S10', 'diesel_s10'),
  ('Diesel S500', 'diesel_s500'),
  ('Arla 32', 'arla32'),
  ('Gasolina', 'gasolina');

insert into culturas (nome, frente) values
  ('Cana-de-açúcar', 'cana'),
  ('Soja', 'graos'),
  ('Milho', 'graos'),
  ('Sorgo', 'graos'),
  ('Feijão', 'graos'),
  ('Bovinocultura de Corte', 'pecuaria');

insert into operacoes (nome, frente) values
  ('Colheita', 'geral'),
  ('Plantio', 'geral'),
  ('Pulverização', 'geral'),
  ('Preparo de Solo', 'geral'),
  ('Transporte', 'geral'),
  ('Irrigação', 'geral'),
  ('Trato/Manejo Animal', 'pecuaria'),
  ('Manutenção', 'geral'),
  ('Administrativo', 'geral');

-- ===================================================================
-- ÚLTIMO PASSO MANUAL — descomente e ajuste antes de rodar:
--
-- insert into profiles (id, nome, usuario, papel, ativo) values
--   ('COLE-AQUI-O-UUID-DO-AUTH-USERS', 'Eduardo Saquy', 'eduardo', 'admin', true);
-- ===================================================================

-- ===================================================================
-- MIGRAÇÃO FASE 2 — Estoque de combustível
--
-- Rode este bloco depois que a Fase 1 já estiver no ar. Adiciona:
--   - estoque mínimo por tanque (para o alerta visual de estoque baixo)
--   - entradas por nota fiscal (crédito no tanque de destino)
--   - medições físicas (régua/sensor), para conciliar com o saldo teórico
--   - ajustes manuais de estoque, sempre com justificativa
-- O saldo de cada tanque (Fase 2) é: entradas - saídas + ajustes. As
-- saídas por abastecimento entram na Fase 4 — até lá, saídas = 0 e o
-- saldo reflete só entradas e ajustes.
-- ===================================================================

alter table tanques add column estoque_min_litros numeric(12,2);

create table entradas_estoque (
  id bigint generated always as identity primary key,
  tanque_id bigint not null references tanques(id),
  fornecedor_id bigint not null references fornecedores(id),
  numero_nf text,
  data date not null,
  volume_litros numeric(12,2) not null check (volume_litros > 0),
  valor_total numeric(12,2) not null check (valor_total >= 0),
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_entradas_estoque_tanque on entradas_estoque(tanque_id);
create index idx_entradas_estoque_fornecedor on entradas_estoque(fornecedor_id);
create trigger set_updated before update on entradas_estoque for each row execute function trg_set_updated();

create table medicoes_fisicas (
  id bigint generated always as identity primary key,
  tanque_id bigint not null references tanques(id),
  data date not null,
  volume_medido_litros numeric(12,2) not null check (volume_medido_litros >= 0),
  metodo text not null check (metodo in ('regua','sensor','outro')),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_medicoes_fisicas_tanque on medicoes_fisicas(tanque_id);
create trigger set_updated before update on medicoes_fisicas for each row execute function trg_set_updated();

-- volume_ajuste_litros aceita valores negativos (reduz o saldo) ou
-- positivos (aumenta) — motivo é obrigatório e não pode ser vazio.
create table ajustes_estoque (
  id bigint generated always as identity primary key,
  tanque_id bigint not null references tanques(id),
  data date not null,
  volume_ajuste_litros numeric(12,2) not null check (volume_ajuste_litros <> 0),
  motivo text not null check (length(trim(motivo)) > 0),
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_ajustes_estoque_tanque on ajustes_estoque(tanque_id);
create trigger set_updated before update on ajustes_estoque for each row execute function trg_set_updated();

alter table entradas_estoque enable row level security;
alter table medicoes_fisicas enable row level security;
alter table ajustes_estoque enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['entradas_estoque','medicoes_fisicas','ajustes_estoque']
  loop
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''estoque'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''estoque'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''estoque'',''editar'')) with check (tem_permissao(''estoque'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''estoque'',''editar''));', t);
  end loop;
end $$;

-- ===================================================================
-- MIGRAÇÃO FASE 3 — Abastecimentos (núcleo do sistema)
--
-- Rode este bloco depois que as Fases 1 e 2 já estiverem no ar.
--
-- client_uuid é a chave para o app funcionar offline: o app de campo
-- gera esse UUID no aparelho no momento do abastecimento (mesmo sem
-- internet) e guarda o registro numa fila local (IndexedDB). Quando a
-- conexão volta, o app reenvia via upsert(on_conflict=client_uuid) —
-- se o mesmo registro já tiver sido sincronizado antes (ex: resposta
-- perdida numa conexão instável), o upsert não duplica a linha.
--
-- talhao_area_id/centro_custo_id: pelo menos um dos dois é obrigatório
-- (é o destino do rateio). Cultura e safra do abastecimento, quando
-- aplicável, são inferidas na Fase 5 a partir do talhão (que já carrega
-- cultura_id) — não duplicamos esses campos aqui.
--
-- Antifraude: a leitura do medidor não pode retroceder por equipamento
-- (checado no banco, não só no app, para valer mesmo em sincronizações
-- concorrentes de dispositivos diferentes).
-- ===================================================================

alter table equipamentos add column capacidade_tanque_litros numeric(10,2);

create table abastecimentos (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  client_uuid uuid not null unique,
  tanque_id bigint not null references tanques(id),
  equipamento_id bigint not null references equipamentos(id),
  operador_id bigint not null references operadores(id),
  data_hora timestamptz not null,
  volume_litros numeric(12,2) not null check (volume_litros > 0),
  leitura_medidor numeric(14,2),
  talhao_area_id bigint references talhoes_areas(id),
  centro_custo_id bigint references centros_custo(id),
  operacao_id bigint references operacoes(id),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id),
  constraint abastecimento_precisa_rateio check (talhao_area_id is not null or centro_custo_id is not null)
);
create index idx_abastecimentos_tanque on abastecimentos(tanque_id);
create index idx_abastecimentos_equipamento on abastecimentos(equipamento_id);
create index idx_abastecimentos_data on abastecimentos(data_hora);
create trigger set_updated before update on abastecimentos for each row execute function trg_set_updated();

-- leitura do medidor não pode retroceder em relação ao maior valor já
-- registrado para o mesmo equipamento (horímetro/hodômetro é cumulativo).
create or replace function trg_valida_leitura_medidor() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  maior_leitura numeric;
begin
  if new.leitura_medidor is not null then
    select max(leitura_medidor) into maior_leitura
    from abastecimentos
    where equipamento_id = new.equipamento_id
      and id is distinct from new.id;
    if maior_leitura is not null and new.leitura_medidor < maior_leitura then
      raise exception 'A leitura do medidor (%) não pode ser menor que a última leitura já registrada para este equipamento (%).', new.leitura_medidor, maior_leitura;
    end if;
  end if;
  return new;
end;
$$;
create trigger valida_leitura_medidor before insert or update on abastecimentos
  for each row execute function trg_valida_leitura_medidor();

alter table abastecimentos enable row level security;
create policy "select abastecimentos" on abastecimentos for select using (tem_permissao('abastecimento','visualizar'));
create policy "inserir abastecimentos" on abastecimentos for insert with check (tem_permissao('abastecimento','editar'));
create policy "atualizar abastecimentos" on abastecimentos for update using (tem_permissao('abastecimento','editar')) with check (tem_permissao('abastecimento','editar'));
create policy "excluir abastecimentos" on abastecimentos for delete using (tem_permissao('abastecimento','editar'));

-- ===================================================================
-- MIGRAÇÃO FASE 5 — Alertas e trilha de auditoria
--
-- Rode este bloco depois que as Fases 1 a 4 já estiverem no ar.
--
-- Alertas: em vez de um job periódico no servidor (o app não tem
-- backend próprio, só Supabase + páginas estáticas), a detecção roda
-- no navegador de quem tem acesso ao módulo, logo depois do login —
-- compara o estado atual dos dados (saldo x estoque mínimo, saldo x
-- última medição física, abastecimentos acima da capacidade do
-- equipamento, consumo fora do padrão de referência) e grava só o que
-- for novidade (dedupe por tipo+referência) ou resolve sozinho os
-- alertas cuja condição já deixou de ser verdadeira (estoque baixo e
-- divergência de medição, que são condições "vivas"; os outros dois
-- tipos são sobre um abastecimento específico que já aconteceu, então
-- só se resolvem manualmente).
--
-- Trilha de auditoria: log_auditoria grava, via trigger, quem criou,
-- editou ou excluiu cada linha das quatro tabelas onde uma divergência
-- pesa mais (estoque e abastecimento) — os cadastros (fazenda, tanque,
-- equipamento etc.) já guardam created_by/updated_by nas próprias
-- colunas, o que é suficiente pra esse risco menor.
-- ===================================================================

create table alertas (
  id bigint generated always as identity primary key,
  fazenda_id bigint references fazendas(id),
  tipo text not null check (tipo in ('estoque_baixo','divergencia_medicao','volume_excede_capacidade','consumo_anomalo')),
  severidade text not null check (severidade in ('info','atencao','critico')),
  titulo text not null,
  descricao text not null,
  tanque_id bigint references tanques(id),
  equipamento_id bigint references equipamentos(id),
  abastecimento_id bigint references abastecimentos(id),
  status text not null default 'aberto' check (status in ('aberto','resolvido')),
  data_hora timestamptz not null default now(),
  resolvido_em timestamptz,
  resolvido_por uuid references profiles(id),
  observacao_resolucao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_alertas_status on alertas(status);
create index idx_alertas_tanque on alertas(tanque_id);
create index idx_alertas_equipamento on alertas(equipamento_id);
create trigger set_updated before update on alertas for each row execute function trg_set_updated();

alter table alertas enable row level security;
create policy "select alertas" on alertas for select using (tem_permissao('alertas','visualizar'));
-- inserir exige só "visualizar": a detecção é um efeito colateral de
-- abrir a tela, não uma edição deliberada — qualquer um que pode ver
-- alertas pode fazer o sistema registrar um novo. Resolver (update),
-- manual ou automático, exige "editar".
create policy "inserir alertas" on alertas for insert with check (tem_permissao('alertas','visualizar'));
create policy "atualizar alertas" on alertas for update using (tem_permissao('alertas','editar')) with check (tem_permissao('alertas','editar'));

create table log_auditoria (
  id bigint generated always as identity primary key,
  tabela text not null,
  registro_id bigint not null,
  acao text not null check (acao in ('insert','update','delete')),
  dados_antigos jsonb,
  dados_novos jsonb,
  usuario_id uuid references profiles(id),
  criado_em timestamptz not null default now()
);
create index idx_log_auditoria_tabela_registro on log_auditoria(tabela, registro_id);
create index idx_log_auditoria_criado_em on log_auditoria(criado_em desc);

alter table log_auditoria enable row level security;
create policy "select log_auditoria" on log_auditoria for select using (tem_permissao('auditoria','visualizar'));
-- sem policy de insert/update/delete: só o trigger abaixo escreve aqui
-- (roda como security definer, então não precisa de permissão própria).

create or replace function trg_log_auditoria() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    insert into log_auditoria(tabela, registro_id, acao, dados_novos, usuario_id)
    values (TG_TABLE_NAME, new.id, 'insert', to_jsonb(new), auth.uid());
    return new;
  elsif TG_OP = 'UPDATE' then
    insert into log_auditoria(tabela, registro_id, acao, dados_antigos, dados_novos, usuario_id)
    values (TG_TABLE_NAME, new.id, 'update', to_jsonb(old), to_jsonb(new), auth.uid());
    return new;
  elsif TG_OP = 'DELETE' then
    insert into log_auditoria(tabela, registro_id, acao, dados_antigos, usuario_id)
    values (TG_TABLE_NAME, old.id, 'delete', to_jsonb(old), auth.uid());
    return old;
  end if;
  return null;
end;
$$;

create trigger log_abastecimentos after insert or update or delete on abastecimentos for each row execute function trg_log_auditoria();
create trigger log_entradas_estoque after insert or update or delete on entradas_estoque for each row execute function trg_log_auditoria();
create trigger log_medicoes_fisicas after insert or update or delete on medicoes_fisicas for each row execute function trg_log_auditoria();
create trigger log_ajustes_estoque after insert or update or delete on ajustes_estoque for each row execute function trg_log_auditoria();
