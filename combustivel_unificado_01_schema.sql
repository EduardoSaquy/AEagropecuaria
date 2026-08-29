-- ===================================================================
-- AE Combustível — schema unificado (roda no MESMO projeto Supabase
-- do AE Matriz/Pecuária/Cana/Cereais, não num projeto separado)
-- ===================================================================
-- Diferente do combustivel_schema.sql original (pensado pra projeto
-- próprio): este script SÓ CRIA o que é específico do Combustível.
-- Reaproveita direto, sem recriar, sem duplicar cadastro:
--   fazendas, talhoes_areas, centros_custo, culturas, safras,
--   funcionarios, funcionario_atividades, fazenda_atividades, profiles,
--   as funções is_admin()/tem_permissao()/trg_set_updated() (já
--   existem e batem exatamente com o que o Combustível precisa —
--   conferido linha a linha antes de escrever este arquivo).
--
-- O custo de combustível NÃO entra em lancamentos_financeiros — nenhuma
-- tabela deste script grava lá. Fica como controle próprio (litros,
-- rateio por talhão/centro de custo), à parte do financeiro, por ora.
--
-- PASSO A PASSO:
-- 1. Cole e rode este arquivo inteiro no SQL Editor do projeto unificado.
-- 2. Cole e rode combustivel_unificado_02_libera_geo_para_combustivel.sql
--    (libera fazendas/talhões/centros de custo/culturas/safras pra
--    quem só tem permissão de Combustível).
-- 3. Na tela de Usuários do AE Matriz, conceda as permissões
--    combustivel_cadastros / combustivel_estoque /
--    combustivel_abastecimento / combustivel_alertas /
--    combustivel_auditoria pra quem for usar o app.
-- 4. Project Settings > API: copie a Project URL e a anon public key
--    (as mesmas que o AEMatriz.html já usa) e cole no AECombustivel.html.
-- 5. Deploy da Edge Function supabase/functions/criar-usuario-combustivel.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='tanques') then
    raise exception 'JA RODOU - a tabela tanques ja existe. Confira antes de rodar de novo.';
  end if;
end $$;

-- Reafirma (create or replace, seguro mesmo se já existir igual) as
-- duas funções que o Combustível depende diretamente e não passam por
-- tem_permissao() — conferidas idênticas ao que já existe no projeto.
create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from profiles where id = auth.uid() and papel = 'admin' and ativo = true
  );
$$;

create or replace function trg_set_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

-- ---------- CATÁLOGOS PRÓPRIOS DO COMBUSTÍVEL ----------
-- produtos e operacoes são específicos daqui — culturas/safras já
-- existem e são reaproveitadas direto (FK aponta pra elas onde precisa).

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

create table operacoes_combustivel (
  id bigint generated always as identity primary key,
  nome text not null unique,
  frente text not null check (frente in ('cana','graos','pecuaria','geral')),
  ativo boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create trigger set_updated before update on operacoes_combustivel for each row execute function trg_set_updated();

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
  capacidade_tanque_litros numeric(10,2),
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
-- precisa ter login no sistema. cpf aqui é protegido — a policy de
-- select exige tem_permissao(...), que depende de auth.uid() e por
-- isso não é leitura anônima (mesma regra permanente do CLAUDE.md).
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
  estoque_min_litros numeric(12,2),
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

-- ---------- ESTOQUE ----------

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

-- ---------- ABASTECIMENTOS (núcleo do sistema) ----------
-- talhao_area_id/centro_custo_id apontam pras tabelas JÁ EXISTENTES do
-- projeto unificado (talhoes_areas/centros_custo) — não são tabelas
-- novas deste script.
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
  operacao_id bigint references operacoes_combustivel(id),
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

-- leitura do medidor não pode ficar fora de ordem em relação à leitura
-- anterior/posterior mais próxima no tempo do mesmo equipamento.
create or replace function trg_valida_leitura_medidor_combustivel() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  maior_anterior numeric;
  menor_posterior numeric;
begin
  if new.leitura_medidor is not null then
    select max(leitura_medidor) into maior_anterior
    from abastecimentos
    where equipamento_id = new.equipamento_id
      and id is distinct from new.id
      and leitura_medidor is not null
      and data_hora <= new.data_hora;
    select min(leitura_medidor) into menor_posterior
    from abastecimentos
    where equipamento_id = new.equipamento_id
      and id is distinct from new.id
      and leitura_medidor is not null
      and data_hora > new.data_hora;
    if maior_anterior is not null and new.leitura_medidor < maior_anterior then
      raise exception 'A leitura do medidor (%) não pode ser menor que a leitura de um abastecimento anterior deste equipamento (%).', new.leitura_medidor, maior_anterior;
    end if;
    if menor_posterior is not null and new.leitura_medidor > menor_posterior then
      raise exception 'A leitura do medidor (%) não pode ser maior que a leitura de um abastecimento posterior deste equipamento (%).', new.leitura_medidor, menor_posterior;
    end if;
  end if;
  return new;
end;
$$;
create trigger valida_leitura_medidor before insert or update on abastecimentos
  for each row execute function trg_valida_leitura_medidor_combustivel();

-- ---------- ALERTAS E AUDITORIA ----------

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
create unique index idx_alertas_chave_aberto on alertas (
  tipo, coalesce(tanque_id,-1), coalesce(equipamento_id,-1), coalesce(abastecimento_id,-1)
) where status = 'aberto';

-- log_auditoria_combustivel: nome diferente de log_alteracoes (que já
-- existe e cobre lancamentos_financeiros/abates/profiles/centros_custo)
-- — não colide, é uma trilha própria só das tabelas do Combustível.
create table log_auditoria_combustivel (
  id bigint generated always as identity primary key,
  tabela text not null,
  registro_id bigint not null,
  acao text not null check (acao in ('insert','update','delete')),
  dados_antigos jsonb,
  dados_novos jsonb,
  usuario_id uuid references profiles(id),
  criado_em timestamptz not null default now()
);
create index idx_log_auditoria_combustivel_tabela_registro on log_auditoria_combustivel(tabela, registro_id);
create index idx_log_auditoria_combustivel_criado_em on log_auditoria_combustivel(criado_em desc);

create or replace function trg_log_auditoria_combustivel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    insert into log_auditoria_combustivel(tabela, registro_id, acao, dados_novos, usuario_id)
    values (TG_TABLE_NAME, new.id, 'insert', to_jsonb(new), auth.uid());
    return new;
  elsif TG_OP = 'UPDATE' then
    insert into log_auditoria_combustivel(tabela, registro_id, acao, dados_antigos, dados_novos, usuario_id)
    values (TG_TABLE_NAME, new.id, 'update', to_jsonb(old), to_jsonb(new), auth.uid());
    return new;
  elsif TG_OP = 'DELETE' then
    insert into log_auditoria_combustivel(tabela, registro_id, acao, dados_antigos, usuario_id)
    values (TG_TABLE_NAME, old.id, 'delete', to_jsonb(old), auth.uid());
    return old;
  end if;
  return null;
end;
$$;
create trigger log_abastecimentos after insert or update or delete on abastecimentos for each row execute function trg_log_auditoria_combustivel();
create trigger log_entradas_estoque after insert or update or delete on entradas_estoque for each row execute function trg_log_auditoria_combustivel();
create trigger log_medicoes_fisicas after insert or update or delete on medicoes_fisicas for each row execute function trg_log_auditoria_combustivel();
create trigger log_ajustes_estoque after insert or update or delete on ajustes_estoque for each row execute function trg_log_auditoria_combustivel();

-- ===================================================================
-- RLS — módulos combustivel_cadastros / combustivel_estoque /
-- combustivel_abastecimento / combustivel_alertas /
-- combustivel_auditoria (nomes prefixados de propósito, pra não colidir
-- com 'cadastros'/'estoque' que outros apps já usam com outro sentido).
-- ===================================================================

alter table produtos enable row level security;
alter table operacoes_combustivel enable row level security;
alter table fornecedores enable row level security;
alter table equipamentos enable row level security;
alter table operadores enable row level security;
alter table tanques enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'produtos','operacoes_combustivel','fornecedores','equipamentos','operadores','tanques'
  ]
  loop
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''combustivel_cadastros'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''combustivel_cadastros'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''combustivel_cadastros'',''editar'')) with check (tem_permissao(''combustivel_cadastros'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''combustivel_cadastros'',''editar''));', t);
  end loop;
end $$;

alter table entradas_estoque enable row level security;
alter table medicoes_fisicas enable row level security;
alter table ajustes_estoque enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['entradas_estoque','medicoes_fisicas','ajustes_estoque']
  loop
    execute format('create policy "select %1$s" on %1$s for select using (tem_permissao(''combustivel_estoque'',''visualizar''));', t);
    execute format('create policy "inserir %1$s" on %1$s for insert with check (tem_permissao(''combustivel_estoque'',''editar''));', t);
    execute format('create policy "atualizar %1$s" on %1$s for update using (tem_permissao(''combustivel_estoque'',''editar'')) with check (tem_permissao(''combustivel_estoque'',''editar''));', t);
    execute format('create policy "excluir %1$s" on %1$s for delete using (tem_permissao(''combustivel_estoque'',''editar''));', t);
  end loop;
end $$;

alter table abastecimentos enable row level security;
create policy "select abastecimentos" on abastecimentos for select using (tem_permissao('combustivel_abastecimento','visualizar'));
create policy "inserir abastecimentos" on abastecimentos for insert with check (tem_permissao('combustivel_abastecimento','editar'));
create policy "atualizar abastecimentos" on abastecimentos for update using (tem_permissao('combustivel_abastecimento','editar')) with check (tem_permissao('combustivel_abastecimento','editar'));
create policy "excluir abastecimentos" on abastecimentos for delete using (tem_permissao('combustivel_abastecimento','editar'));

alter table alertas enable row level security;
create policy "select alertas" on alertas for select using (tem_permissao('combustivel_alertas','visualizar'));
create policy "inserir alertas" on alertas for insert with check (tem_permissao('combustivel_alertas','editar'));
create policy "atualizar alertas" on alertas for update using (tem_permissao('combustivel_alertas','editar')) with check (tem_permissao('combustivel_alertas','editar'));

alter table log_auditoria_combustivel enable row level security;
create policy "select log_auditoria_combustivel" on log_auditoria_combustivel for select using (tem_permissao('combustivel_auditoria','visualizar'));
-- sem policy de insert/update/delete: só o trigger grava aqui (security definer).

-- ===================================================================
-- SEED — catálogos próprios do combustível
-- ===================================================================

insert into produtos (nome, tipo) values
  ('Diesel S10', 'diesel_s10'),
  ('Diesel S500', 'diesel_s500'),
  ('Arla 32', 'arla32'),
  ('Gasolina', 'gasolina');

insert into operacoes_combustivel (nome, frente) values
  ('Colheita', 'geral'),
  ('Plantio', 'geral'),
  ('Pulverização', 'geral'),
  ('Preparo de Solo', 'geral'),
  ('Transporte', 'geral'),
  ('Irrigação', 'geral'),
  ('Trato/Manejo Animal', 'pecuaria'),
  ('Manutenção', 'geral'),
  ('Administrativo', 'geral');

select 'Parte 1 ok. Agora cole o combustivel_unificado_02_libera_geo_para_combustivel.sql' as proximo_passo;
