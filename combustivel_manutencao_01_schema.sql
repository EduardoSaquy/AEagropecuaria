-- ============================================================
-- AE Combustível — módulo de Manutenção (troca de óleo/filtro)
--
-- Nova tabela manutencoes: uma linha por troca de óleo ou filtro num
-- equipamento, com a leitura do horímetro/hodômetro naquele momento e
-- o intervalo até a próxima (em horas, se horímetro, ou km, se
-- hodômetro). O app calcula a previsão da próxima troca a partir daí
-- (leitura da última manutenção + intervalo) e compara com a leitura
-- mais recente do equipamento vinda de Abastecimentos — não existe
-- campo de "leitura atual" separado, o app usa o último abastecimento
-- com leitura registrada.
--
-- Também amplia o check de alertas.tipo pra aceitar os dois novos
-- tipos de alerta gerados por esse módulo (um por tipo de manutenção,
-- porque a chave de dedupe de alerta não tem um campo extra pra
-- isso — ver detectarAlertas() no app).
--
-- Rode este arquivo inteiro de uma vez.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='equipamentos') then
    raise exception 'PROJETO ERRADO — esta tabela nao existe aqui.';
  end if;
end $$;

create table manutencoes (
  id bigint generated always as identity primary key,
  fazenda_id bigint not null references fazendas(id),
  equipamento_id bigint not null references equipamentos(id),
  tipo text not null check (tipo in ('troca_oleo','troca_filtro')),
  data date not null,
  leitura numeric(12,2) not null check (leitura >= 0),
  intervalo numeric(12,2) not null check (intervalo > 0),
  observacao text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles(id)
);
create index idx_manutencoes_equipamento on manutencoes(equipamento_id);
create trigger set_updated before update on manutencoes for each row execute function trg_set_updated();

alter table manutencoes enable row level security;
create policy "select manutencoes" on manutencoes for select using (tem_permissao('combustivel_manutencao','visualizar'));
create policy "inserir manutencoes" on manutencoes for insert with check (tem_permissao('combustivel_manutencao','editar'));
create policy "atualizar manutencoes" on manutencoes for update using (tem_permissao('combustivel_manutencao','editar')) with check (tem_permissao('combustivel_manutencao','editar'));
create policy "excluir manutencoes" on manutencoes for delete using (tem_permissao('combustivel_manutencao','editar'));

alter table alertas drop constraint if exists alertas_tipo_check;
alter table alertas add constraint alertas_tipo_check
  check (tipo in (
    'estoque_baixo','divergencia_medicao','volume_excede_capacidade','consumo_anomalo',
    'manutencao_pendente_troca_oleo','manutencao_pendente_troca_filtro'
  ));
