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
-- Cana: o registro de Plantio por talhão. Fases seguintes (Tratos
-- culturais, Colheita/Produção) terão suas próprias migrações.
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
