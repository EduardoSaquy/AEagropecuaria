-- ===================================================================
-- AE Cereais — schema (Operações: Plantio, Tratos culturais e Colheita)
-- ===================================================================
-- Este arquivo roda no MESMO projeto Supabase já usado pelo AE
-- Combustível (e pelo AE Cana) — rode combustivel_schema.sql primeiro,
-- se ainda não tiver rodado, e NÃO crie um projeto novo. Fazendas,
-- Culturas, Safras e Talhões/Áreas (a "matriz" de cadastros central)
-- já existem nesse schema e são reaproveitados sem alteração pelo AE
-- Cereais — ver a seção "AE Cereais" do README para o racional dessa
-- integração. A frente de negócio usada nos filtros é 'graos' (mesmo
-- código já usado em combustivel_schema.sql para Soja/Milho/Sorgo/
-- Feijão) — "Cereais" é só o nome comercial do app.
--
-- Diferente da cana (perene, um "estande" atravessa vários cortes),
-- grão é cultura anual: cada talhão passa por um Plantio -> uma
-- Colheita por safra, podendo repetir no mesmo ano (ex: soja no verão,
-- milho safrinha em seguida) — por isso Plantio e Colheita aqui também
-- guardam a Cultura do lançamento (não só a do talhão), para não
-- misturar as safras quando o talhão roda de cultura.
--
-- PASSO A PASSO:
-- 1. SQL Editor do MESMO projeto Supabase do AE Combustível > cole e
--    rode este arquivo inteiro.
-- 2. Nada muda em AECombustivel.html, AEpecuaria.html nem AECana.html
--    — as tabelas e funções que este arquivo reaproveita (profiles,
--    talhoes_areas, culturas, safras, tem_permissao(), trg_set_updated())
--    já foram criadas por combustivel_schema.sql.
-- 3. Em Administração > Usuários (em qualquer um dos apps, é a mesma
--    conta), libere os módulos "Operações de Cereais" e "Financeiro de
--    Cereais" para quem for lançar ou consultar esses dados.
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
