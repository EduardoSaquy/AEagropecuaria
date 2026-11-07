-- ============================================================
-- VENDA DE ANIMAIS EM UMA OPERACAO SO (tudo ou nada, com o lote travado)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode. Pode rodar de novo.
-- Nao mexe em nenhum dado: so cria a funcao registrar_venda_animais().
--
-- O PROBLEMA (revisao geral de 05/11/2026): a venda gravava o abate, depois a receita e depois a baixa
-- no lote, em tres chamadas separadas do navegador, desfazendo na mao se uma falhasse. E o saldo do lote
-- vinha da memoria da tela: duas pessoas vendendo do mesmo lote ao mesmo tempo perdiam uma venda.
--
-- A FUNCAO: grava abate + lancamento da receita + baixa do lote numa transacao so. Se qualquer passo
-- falhar, nada fica gravado. Trava a linha do lote (for update) e confere o saldo DENTRO do banco: se
-- outra venda passou na frente e nao sobrou animal, recusa dizendo quantos tem.
-- Roda com as permissoes de quem chama (security invoker): quem nao pode vender hoje, continua nao podendo.
--
-- O app novo chama esta funcao; se ela ainda nao existir (este script nao rodou), o app usa o caminho
-- antigo, entao nada quebra enquanto isso.
--
-- PARA DESFAZER: drop function public.registrar_venda_animais(jsonb, jsonb);
-- ============================================================
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

create or replace function public.registrar_venda_animais(p_abate jsonb, p_lancamento jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $f$
declare
  v_lote_id  bigint  := nullif(p_abate->>'lote_id', '')::bigint;
  v_qtd      numeric := nullif(p_abate->>'quantidade', '')::numeric;
  v_data     date    := nullif(p_abate->>'data', '')::date;
  v_lote     record;
  v_abate_id bigint;
  v_lanc_id  bigint;
  v_restante numeric;
  v_cols     text;
begin
  if v_lote_id is null or v_qtd is null or v_qtd <= 0 or v_data is null then
    raise exception 'Venda incompleta: precisa de lote, data e quantidade maior que zero.';
  end if;
  if p_lancamento is null or p_lancamento = '{}'::jsonb then
    raise exception 'Venda sem o lancamento da receita.';
  end if;

  select id, nome, numero_animais, data_fim into v_lote from lotes where id = v_lote_id for update;
  if not found then
    raise exception 'Lote % nao encontrado (ou sem permissao).', v_lote_id;
  end if;
  if coalesce(v_lote.numero_animais, 0) < v_qtd then
    raise exception 'O lote "%" tem % animal(is); nao da para vender %. Outra venda pode ter passado na frente.',
      v_lote.nome, coalesce(v_lote.numero_animais, 0), v_qtd;
  end if;

  insert into abates (data, lote_id, quantidade, tipo_venda, peso_medio_kg, valor_arroba, valor_por_animal,
                      valor_kg, categoria, sexo, observacao, criado_por)
  values (v_data, v_lote_id, v_qtd, p_abate->>'tipo_venda',
          nullif(p_abate->>'peso_medio_kg', '')::numeric, nullif(p_abate->>'valor_arroba', '')::numeric,
          nullif(p_abate->>'valor_por_animal', '')::numeric, nullif(p_abate->>'valor_kg', '')::numeric,
          p_abate->>'categoria', p_abate->>'sexo', p_abate->>'observacao', p_abate->>'criado_por')
  returning id into v_abate_id;

  -- so as colunas que vieram no documento (as outras ficam com o valor padrao); id e abate_id nunca vem de fora
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.lancamentos_financeiros'::regclass
     and a.attnum > 0 and not a.attisdropped and a.attidentity = '' and a.attgenerated = ''
     and a.attname not in ('id', 'abate_id')
     and p_lancamento ? a.attname;
  if v_cols is null then
    raise exception 'O lancamento da venda nao tem nenhuma coluna conhecida.';
  end if;
  execute format(
    'insert into lancamentos_financeiros (%1$s, abate_id) select %1$s, $2 from jsonb_populate_record(null::lancamentos_financeiros, $1) returning id',
    v_cols)
    into v_lanc_id using p_lancamento, v_abate_id;

  v_restante := coalesce(v_lote.numero_animais, 0) - v_qtd;
  update lotes
     set numero_animais = v_restante,
         data_fim = case when v_restante = 0 and data_fim is null then v_data else data_fim end
   where id = v_lote_id;

  return jsonb_build_object('abate_id', v_abate_id, 'lancamento_id', v_lanc_id, 'restante', v_restante);
end
$f$;

revoke all on function public.registrar_venda_animais(jsonb, jsonb) from public, anon;
grant execute on function public.registrar_venda_animais(jsonb, jsonb) to authenticated;

select 'funcao registrar_venda_animais' as item,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'registrar_venda_animais')::text as valor,
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname = 'registrar_venda_animais' and not p.prosecdef)
            then 'OK (roda com as permissoes de quem chama)' else 'FALTA' end as situacao;
