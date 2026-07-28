-- ===================================================================
-- AE Cana — schema Fase 2 (Operações: Plantio)
-- ===================================================================
-- Este arquivo roda no MESMO projeto Supabase já usado pelo AE
-- Combustível — rode combustivel_schema.sql primeiro, se ainda não
-- tiver rodado, e NÃO crie um projeto novo. Fazendas, Culturas,
-- Safras e Talhões/Áreas (a "matriz" de cadastros central) já existem
-- nesse schema e são reaproveitados sem alteração pelo AE Cana — ver
-- a seção "AE Cana" do README para o racional dessa integração.
--
-- Esta migração cria só a tabela nova necessária para a Fase 2 do AE
-- Cana: o registro de Plantio por talhão. As Fases 3 (Tratos
-- culturais) e 4 (Colheita/Produção) estão logo abaixo, neste mesmo
-- arquivo — rode o arquivo inteiro de uma vez.
--
-- PASSO A PASSO:
-- 1. SQL Editor do MESMO projeto Supabase do AE Combustível > cole e
--    rode este arquivo inteiro.
-- 2. Nada muda em AECombustivel.html nem em AEpecuaria.html — as
--    tabelas e funções que este arquivo reaproveita (profiles,
--    talhoes_areas, safras, tem_permissao(), trg_set_updated()) já
--    foram criadas por combustivel_schema.sql.
-- 3. Em Administração > Usuários (em qualquer um dos dois apps, é a
--    mesma conta), libere o módulo "Operações de Cana" para quem for
--    lançar plantio.
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
-- (Fase 2 acima, depois esta), no mesmo projeto Supabase do AE
-- Combustível.
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
-- (Fases 2 e 3 acima, depois esta), no mesmo projeto Supabase do AE
-- Combustível.
--
-- Cria o registro de Colheita por talhão: toneladas colhidas, com TCH
-- (toneladas por hectare) calculado no app a partir da área do talhão
-- — é o dado que faltava para o AE Combustível calcular custo por
-- tonelada (ver README, seção "AE Combustível" > "Fora do escopo").
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
-- (Fases 2 a 4 acima, depois esta), no mesmo projeto Supabase do AE
-- Combustível.
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
