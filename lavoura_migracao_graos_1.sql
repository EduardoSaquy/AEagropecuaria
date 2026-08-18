-- ===================================================================
-- AE Lavoura — Migração aditiva: traz as tabelas de Grãos para dentro
-- do projeto Supabase que HOJE já é o do AE Cana (cana_schema.sql).
-- ===================================================================
-- Por quê rodar isso no projeto do AE Cana (e não criar um projeto novo):
-- o AE Cana já tem dados reais de produção (fazendas, talhões, safras,
-- plantios, aplicações, colheitas, despesas de 2026 já carregadas).
-- O AE Cereais, até a data desta migração, não tem dado real lançado.
-- Reaproveitar o banco do Cana como base do "AE Lavoura" evita ter que
-- migrar/exportar/importar nenhum dado real — Fazendas, Culturas,
-- Safras, Talhões/Áreas e Centros de Custo já existem e já são
-- genéricos o bastante (a coluna `frente` de culturas/centros_custo já
-- aceita 'cana' e 'graos' desde o desenho original) para servir aos
-- dois. Este script SÓ ACRESCENTA tabelas novas (as de Grãos) — não
-- altera, não apaga e não bloqueia nada que já existe.
--
-- Pré-requisito: cana_schema.sql já rodado neste projeto (fases 1 a 5).
-- Este arquivo assume que as funções is_admin(), tem_permissao() e
-- trg_set_updated() já existem (criadas por cana_schema.sql) — não são
-- recriadas aqui.
--
-- Diferença de domínio Grãos x Cana (mesma nota do cereais_schema.sql
-- original): grão é cultura anual — cada talhão passa por um Plantio e
-- uma Colheita por safra, podendo repetir no mesmo ano (ex: soja no
-- verão, milho safrinha em seguida). Por isso plantios_graos e
-- colheitas_graos guardam também a Cultura do lançamento (não só a do
-- talhão) — cana não precisa disso (plantios_cana é sempre da cultura
-- "cana", sem rotação).
--
-- COMO RODAR:
-- 1. Abra o SQL Editor do projeto Supabase do AE Cana (o mesmo já
--    usado em produção — confira a URL no topo do AECana.html atual).
-- 2. Cole e rode este arquivo inteiro, de uma vez.
-- 3. Confirme com "select count(*) from plantios_graos;" (deve dar 0,
--    sem erro) que as tabelas novas foram criadas.
-- 4. Publique a Edge Function supabase/functions/criar-usuario-lavoura
--    (cópia da criar-usuario-cana, só o nome muda) OU simplesmente
--    reaproveite a criar-usuario-cana já publicada — o app novo
--    (AELavoura.html) pode chamar ela mesma, já que cria linha em
--    auth.users + profiles do MESMO projeto.
-- ===================================================================

-- ---------- PLANTIO (grãos) ----------
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
create unique index uq_plantios_graos_talhao_ativo on plantios_graos(talhao_id) where ativo;
create trigger set_updated before update on plantios_graos for each row execute function trg_set_updated();

alter table plantios_graos enable row level security;
create policy "select plantios_graos" on plantios_graos for select using (tem_permissao('operacoes_graos','visualizar'));
create policy "inserir plantios_graos" on plantios_graos for insert with check (tem_permissao('operacoes_graos','editar'));
create policy "atualizar plantios_graos" on plantios_graos for update using (tem_permissao('operacoes_graos','editar')) with check (tem_permissao('operacoes_graos','editar'));
create policy "excluir plantios_graos" on plantios_graos for delete using (tem_permissao('operacoes_graos','editar'));

-- ---------- INSUMOS (grãos) ----------
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

-- ---------- ENTRADAS DE INSUMO (grãos) ----------
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

-- ---------- APLICAÇÕES (trato cultural em campo, grãos) ----------
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

-- ---------- COLHEITA/PRODUÇÃO (grãos) ----------
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

-- ---------- DESPESAS (grãos) ----------
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

-- ===================================================================
-- NOVO em relação ao AE Cereais original: Receita de Grãos.
-- O AE Cereais nunca teve módulo de receita própria (README: "ainda
-- sem módulo de receita"). Para o AE Lavoura mostrar lucro por
-- hectare de Grãos (não só despesa), criamos aqui receitas_graos,
-- espelhando receitas_cana — mesmo racional de permissão separada
-- (módulo 'resultados_graos', só liberado por padrão ao Administrador).
-- ===================================================================
create table receitas_graos (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  talhao_id bigint references talhoes_areas(id),
  safra_id bigint references safras(id),
  cultura_id bigint references culturas(id),
  data date not null,
  sacas numeric(12,2),
  valor_total numeric(12,2) not null check (valor_total > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_receitas_graos_fazenda on receitas_graos(fazenda_id);
create index idx_receitas_graos_talhao on receitas_graos(talhao_id);
create trigger set_updated before update on receitas_graos for each row execute function trg_set_updated();

alter table receitas_graos enable row level security;
create policy "select receitas_graos" on receitas_graos for select using (tem_permissao('resultados_graos','visualizar'));
create policy "inserir receitas_graos" on receitas_graos for insert with check (tem_permissao('resultados_graos','editar') or tem_permissao('financeiro_graos','editar'));
create policy "atualizar receitas_graos" on receitas_graos for update using (tem_permissao('resultados_graos','editar')) with check (tem_permissao('resultados_graos','editar'));
create policy "excluir receitas_graos" on receitas_graos for delete using (tem_permissao('resultados_graos','editar'));

-- ===================================================================
-- Fim da migração. Nada em fazendas, culturas, safras, talhoes_areas,
-- centros_custo, profiles, plantios_cana, insumos_cana,
-- entradas_insumo_cana, aplicacoes_cana, colheitas_cana, despesas_cana
-- ou receitas_cana foi alterado — o AE Cana continua funcionando
-- exatamente como antes, inclusive se alguém ainda abrir o
-- AECana.html antigo (ele só enxerga as tabelas *_cana, que não
-- mudaram).
-- ===================================================================
