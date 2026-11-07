-- ============================================================
-- Lancamentos financeiros ligados a um equipamento (07/11/2026)
--
-- Acrescenta lancamentos_financeiros.equipamento_id (opcional): quando uma despesa de peca, servico
-- ou reparo e de uma maquina especifica, o AE Matriz grava qual. O AE Combustivel soma essas
-- despesas ao combustivel e a manutencao para mostrar o CUSTO POR HORA de cada equipamento.
--
-- O que NAO muda: nenhum lancamento existente (a coluna comeca vazia), nenhum resultado, nenhum
-- rateio, nenhuma politica de acesso (quem le ou grava lancamento continua sendo quem ja era;
-- a coluna herda as politicas da tabela). O registro de alteracoes passa a guardar a coluna junto.
-- O equipamento so pode ser apagado se nenhum lancamento apontar para ele (a chave estrangeira
-- protege o financeiro). O app funciona antes e depois deste script.
--
-- Rode este arquivo inteiro de uma vez. Pode rodar de novo sem problema.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='lancamentos_financeiros') then
    raise exception 'PROJETO ERRADO: a tabela lancamentos_financeiros nao existe aqui.';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='equipamentos') then
    raise exception 'A tabela equipamentos nao existe: rode antes os scripts do AE Combustivel (combustivel_unificado_01_schema.sql).';
  end if;
end $$;

alter table lancamentos_financeiros add column if not exists equipamento_id bigint references equipamentos(id);

create index if not exists idx_lancamentos_equipamento on lancamentos_financeiros (equipamento_id) where equipamento_id is not null;

-- conferencia (uma consulta so, no fim)
select 'coluna lancamentos_financeiros.equipamento_id' as item,
       coalesce((select data_type from information_schema.columns
                 where table_schema='public' and table_name='lancamentos_financeiros' and column_name='equipamento_id'), 'NAO EXISTE') as valor,
       case when exists (select 1 from information_schema.columns
                         where table_schema='public' and table_name='lancamentos_financeiros' and column_name='equipamento_id')
            then 'OK' else 'FALTA' end as situacao
union all
select 'chave estrangeira para equipamentos', 'lancamentos_financeiros_equipamento_id_fkey',
       case when exists (select 1 from information_schema.table_constraints
                         where table_schema='public' and table_name='lancamentos_financeiros' and constraint_type='FOREIGN KEY'
                           and constraint_name='lancamentos_financeiros_equipamento_id_fkey') then 'OK' else 'FALTA' end
union all
select 'indice por equipamento', 'idx_lancamentos_equipamento',
       case when exists (select 1 from pg_indexes where schemaname='public' and indexname='idx_lancamentos_equipamento') then 'OK' else 'FALTA' end
union all
select 'lancamentos ja ligados a algum equipamento (comeca em 0)', (select count(*)::text from lancamentos_financeiros where equipamento_id is not null), 'OK';
