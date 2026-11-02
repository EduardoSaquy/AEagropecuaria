-- ============================================================
-- Pecuaria - fila offline sem duplicar (Eduardo, 02/11/2026).
-- Com sinal fraco o banco podia gravar o lancamento e a resposta se
-- perder: o app reenviava e o lancamento (e a baixa de estoque) ficava
-- em dobro. Cada lancamento passa a levar uma chave gerada no aparelho
-- (client_uuid) e o banco recusa a mesma chave duas vezes; o app trata
-- a recusa como "ja recebido" e so completa o que faltou.
--
-- So acrescenta uma coluna opcional e um indice unico (que ignora
-- linhas sem chave) em 10 tabelas. Nao mexe em nenhum dado.
-- O app novo funciona antes e depois deste script.
-- Repetivel.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['saidas_racao','leituras_cocho','pasto','producoes_racao','abates',
                           'reproducao_custos','diagnosticos_gestacionais','partos','desmamas','pesagens'] loop
    if not exists (select 1 from information_schema.tables where table_schema='public' and table_name=t) then
      raise exception 'Tabela % nao encontrada - nada foi alterado', t;
    end if;
    execute format('alter table public.%I add column if not exists client_uuid uuid', t);
    execute format('create unique index if not exists %I on public.%I (client_uuid) where client_uuid is not null',
                   t || '_client_uuid_key', t);
  end loop;
end $$;

-- CONFERENCIA (uma consulta so)
select t.tabela as item,
       case when c.column_name is not null then 'coluna ok' else 'SEM COLUNA' end
         || ' | ' || case when i.indexname is not null then 'indice ok' else 'SEM INDICE' end as valor,
       case when c.column_name is not null and i.indexname is not null then 'OK' else 'DIFERENTE' end as situacao
  from unnest(array['saidas_racao','leituras_cocho','pasto','producoes_racao','abates',
                    'reproducao_custos','diagnosticos_gestacionais','partos','desmamas','pesagens']) as t(tabela)
  left join information_schema.columns c
         on c.table_schema='public' and c.table_name=t.tabela and c.column_name='client_uuid'
  left join pg_indexes i
         on i.schemaname='public' and i.tablename=t.tabela and i.indexname=t.tabela || '_client_uuid_key'
 order by t.tabela;
