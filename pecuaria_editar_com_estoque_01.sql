-- ============================================================
-- PECUARIA - EDITAR SAIDA DE RACAO, RECRIA E PRODUCAO COM A BAIXA
-- DE ESTOQUE NUMA TRANSACAO SO (13/11/2026)
--
-- Editar uma saida de racao, uma saida de recria (tabela pasto) ou uma
-- producao de racao troca a baixa de estoque dela (movimentos). O app fazia
-- isso em chamadas separadas: na recria e na producao apagava a baixa
-- antiga ANTES de gravar a nova, e se a gravacao nova falhasse (sinal
-- caindo) o consumo sumia do estoque sem aviso.
--
-- editar_consumo_com_estoque(tabela, id, campos, movimentos) faz tudo ou
-- nada: muda o lancamento, apaga a baixa antiga e grava a nova. Roda com os
-- direitos de quem chama (security invoker): as regras de acesso das
-- tabelas continuam valendo como hoje.
--
-- O app funciona antes deste SQL (cai no caminho antigo, agora com a ordem
-- segura). Pode rodar de novo. Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
end $guarda$;

create or replace function public.editar_consumo_com_estoque(p_tabela text, p_id bigint, p_campos jsonb, p_movimentos jsonb)
returns integer language plpgsql security invoker set search_path = public as $f$
declare
  v_fk text;
  v_n integer;
  v_movs integer := 0;
begin
  if p_tabela = 'saidas_racao' then
    v_fk := 'saida_racao_id';
    update saidas_racao set data = (p_campos->>'data')::date, dieta_id = (p_campos->>'dieta_id')::bigint,
           lote_id = (p_campos->>'lote_id')::bigint, quantidade_kg = (p_campos->>'quantidade_kg')::numeric
     where id = p_id;
  elsif p_tabela = 'pasto' then
    v_fk := 'pasto_id';
    update pasto set data = (p_campos->>'data')::date, dieta_id = (p_campos->>'dieta_id')::bigint,
           lote_id = (p_campos->>'lote_id')::bigint, quantidade = (p_campos->>'quantidade')::numeric
     where id = p_id;
  elsif p_tabela = 'producoes_racao' then
    v_fk := 'producao_racao_id';
    update producoes_racao set data = (p_campos->>'data')::date, dieta_id = (p_campos->>'dieta_id')::bigint,
           quantidade_kg = (p_campos->>'quantidade_kg')::numeric
     where id = p_id;
  else
    raise exception 'Tabela nao aceita: %', p_tabela;
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Lancamento % nao encontrado ou sem permissao para editar.', p_id using errcode = 'P0002';
  end if;

  execute format('delete from movimentos where %I = $1', v_fk) using p_id;

  if p_movimentos is not null and jsonb_array_length(p_movimentos) > 0 then
    execute format(
      'insert into movimentos (data, ingrediente_id, tipo, quantidade, %I)
       select (m->>''data'')::date, (m->>''ingrediente_id'')::bigint, ''saida'', (m->>''quantidade'')::numeric, $1
         from jsonb_array_elements($2) m', v_fk) using p_id, p_movimentos;
    get diagnostics v_movs = row_count;
  end if;
  return v_movs;
end $f$;
revoke all on function public.editar_consumo_com_estoque(text, bigint, jsonb, jsonb) from public, anon;
grant execute on function public.editar_consumo_com_estoque(text, bigint, jsonb, jsonb) to authenticated;

select item, valor, situacao from (
  select 1 o, 'funcao editar_consumo_com_estoque' item,
         case when to_regprocedure('public.editar_consumo_com_estoque(text,bigint,jsonb,jsonb)') is not null then 'criada' else 'falta' end valor,
         case when to_regprocedure('public.editar_consumo_com_estoque(text,bigint,jsonb,jsonb)') is not null then 'OK' else 'FALTA' end situacao
  union all
  select 2, 'roda com os direitos de quem chama',
         case when p.prosecdef then 'definer' else 'invoker' end,
         case when p.prosecdef then 'CONFERIR' else 'OK' end
    from pg_proc p where p.oid = to_regprocedure('public.editar_consumo_com_estoque(text,bigint,jsonb,jsonb)')
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar; o app volta ao caminho antigo sozinho):
-- drop function if exists public.editar_consumo_com_estoque(text, bigint, jsonb, jsonb);
-- ============================================================
