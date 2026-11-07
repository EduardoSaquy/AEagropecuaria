-- ============================================================
-- SQL DE 06/11/2026, TUDO JUNTO (cole inteiro e rode uma vez)
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- O QUE FAZ, nesta ordem:
--   1. Passa as 8 compras de animais lancadas a mao do centro "INVESTIMENTO EM ANIMAIS" para matriz (7) ou
--      giro (1), como o Eduardo decidiu. So muda o centro de custo. Guarda o antigo em
--      zz_backup_classifica_animais_2026_11_06.
--   2. Cria a funcao registrar_venda_animais(): a venda de animais passa a gravar abate + receita + baixa
--      do lote numa transacao so, com o lote travado.
--   3. Cria a funcao salvar_titulos() e a trava que recusa mudar o valor de uma conta sem as partes do
--      rateio fecharem: conta a pagar/receber passa a gravar em uma transacao so.
--   4. Mostra, no fim, uma tabela unica: o que foi movido, se as funcoes e a trava existem, e os
--      lancamentos do vendedor com R$ 30.400 repetido (para conferir se sao parcelas).
--
-- TUDO OU NADA: o editor do Supabase roda o script como uma transacao. Se qualquer trava recusar (ela diz
-- qual e o que corrigir), NADA e aplicado, nem as outras partes. Rodar de novo depois de aplicado: a parte 1
-- recusa (ja rodou); as partes 2 e 3 sao seguras. Para rodar de novo as partes 2 e 3 sozinhas, use
-- venda_animais_atomica_01.sql e titulos_atomico_01.sql.
--
-- PARA DESFAZER (cada parte tem o seu):
--   1. update lancamentos_financeiros l set centro_custo_id = b.centro_custo_id
--        from zz_backup_classifica_animais_2026_11_06 b where b.id = l.id;
--   2. drop function public.registrar_venda_animais(jsonb, jsonb);
--   3. drop trigger if exists trg_titulo_valor_fecha on titulos;
--      drop function if exists public.titulo_valor_tem_que_fechar();
--      drop function if exists public.salvar_titulos(jsonb);
-- ============================================================

-- ===== PARTE 1: separa matriz de giro nas compras lancadas a mao =====
do $classifica$
declare
  c_matriz bigint;
  c_giro bigint;
  n int;
  a record;
  achados int;
  soma numeric;
  atualizadas int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_classifica_animais_2026_11_06') is not null then
    raise exception 'Este script ja rodou (a copia zz_backup_classifica_animais_2026_11_06 existe). Nao mexo em nada.';
  end if;

  select count(*), min(id) into n, c_matriz from centros_custo
   where translate(upper(nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') like 'COMPRA DE MATRIZES%';
  if n <> 1 then
    raise exception 'Achei % centro(s) COMPRA DE MATRIZES (esperava 1). Nao mexo em nada.', n;
  end if;
  select count(*), min(id) into n, c_giro from centros_custo
   where translate(upper(nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') like 'COMPRA DE ANIMAIS%';
  if n <> 1 then
    raise exception 'Achei % centro(s) COMPRA DE ANIMAIS (esperava 1). Nao mexo em nada.', n;
  end if;

  create temp table alvo (ids bigint[], soma numeric, destino text) on commit drop;
  insert into alvo values
    (array[490, 491], 460525.00, 'matriz'),
    (array[492],      144524.71, 'matriz'),
    (array[494],       72000.00, 'matriz'),
    (array[496, 497], 179600.00, 'matriz'),
    (array[508],       30400.00, 'matriz'),
    (array[502],        5800.00, 'giro');

  for a in select * from alvo loop
    select count(*), coalesce(sum(l.valor), 0) into achados, soma
      from lancamentos_financeiros l
      join centros_custo c on c.id = l.centro_custo_id
     where l.id = any (a.ids) and l.tipo = 'investimento'
       and translate(upper(c.nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') = 'INVESTIMENTO EM ANIMAIS';
    if achados <> array_length(a.ids, 1) or soma <> a.soma then
      raise exception 'Lancamento(s) % nao estao como esperado (achei % no centro INVESTIMENTO EM ANIMAIS, somando R$ %, esperava R$ %). Nao mexo em nada.',
        a.ids, achados, soma, a.soma;
    end if;
  end loop;

  create table zz_backup_classifica_animais_2026_11_06 as
    select id, centro_custo_id from lancamentos_financeiros
     where id in (select unnest(ids) from alvo);
  alter table zz_backup_classifica_animais_2026_11_06 enable row level security;
  revoke all on zz_backup_classifica_animais_2026_11_06 from anon, authenticated;

  update lancamentos_financeiros l
     set centro_custo_id = case when l.id in (select unnest(ids) from alvo where destino = 'matriz') then c_matriz else c_giro end
   where l.id in (select unnest(ids) from alvo);
  get diagnostics atualizadas = row_count;
  if atualizadas <> 8 then
    raise exception 'Atualizei % lancamento(s), esperava 8. Desfeito.', atualizadas;
  end if;
end
$classifica$;

-- ===== PARTE 2: venda de animais em uma operacao so =====
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

-- ===== PARTE 3: conta a pagar/receber em uma operacao so + trava do valor =====
do $trava$
declare
  n int;
  ids text;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  select count(*), left(string_agg(t.id::text, ', ' order by t.id), 100) into n, ids
    from titulos t
    join (select titulo_id, sum(valor) as soma from titulo_rateios group by titulo_id) p on p.titulo_id = t.id
   where abs(t.valor - p.soma) > 0.05;
  if n > 0 then
    raise exception 'Ha % conta(s) cujas partes nao fecham o valor (ids: %). Corrija antes; nao mexo em nada.', n, ids;
  end if;
end
$trava$;

create or replace function public.salvar_titulos(p_itens jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $f$
declare
  it     jsonb;
  v_doc  jsonb;
  v_id   bigint;
  v_ids  bigint[] := '{}';
  v_cols text;
  v_sets text;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Nenhuma conta para salvar.';
  end if;

  for it in select jsonb_array_elements(p_itens) loop
    v_doc := it->'titulo';
    if v_doc is null or jsonb_typeof(v_doc) <> 'object'
       or jsonb_typeof(it->'rateios') is distinct from 'array' or jsonb_array_length(it->'rateios') = 0 then
      raise exception 'Cada conta precisa dos dados e de pelo menos uma parte do rateio.';
    end if;
    v_id := nullif(it->>'id', '')::bigint;

    -- so colunas que existem e que o app pode mandar (saldo baixado, cancelamento, datas de controle: nunca)
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum),
           string_agg(quote_ident(a.attname) || ' = r.' || quote_ident(a.attname), ', ' order by a.attnum)
      into v_cols, v_sets
      from pg_attribute a
     where a.attrelid = 'public.titulos'::regclass
       and a.attnum > 0 and not a.attisdropped and a.attidentity = '' and a.attgenerated = ''
       and a.attname not in ('id', 'valor_baixado', 'cancelado', 'created_at', 'updated_at', 'updated_by')
       and v_doc ? a.attname;
    if v_cols is null then
      raise exception 'A conta nao tem nenhuma coluna conhecida.';
    end if;

    if v_id is null then
      execute format('insert into titulos (%1$s) select %1$s from jsonb_populate_record(null::titulos, $1) returning id', v_cols)
        into v_id using v_doc;
    else
      execute format('update titulos t set %s from jsonb_populate_record(null::titulos, $1) r where t.id = $2 returning t.id', v_sets)
        into v_id using v_doc, v_id;
      if v_id is null then
        raise exception 'Conta % nao encontrada (ou sem permissao).', nullif(it->>'id', '');
      end if;
      delete from titulo_rateios where titulo_id = v_id;
    end if;

    insert into titulo_rateios (titulo_id, fazenda_id, atividade, centro_custo_id, competencia, valor, talhao_id, observacao)
    select v_id, r.fazenda_id, r.atividade, r.centro_custo_id, r.competencia, r.valor, r.talhao_id, r.observacao
      from jsonb_populate_recordset(null::titulo_rateios, it->'rateios') r;

    v_ids := v_ids || v_id;
  end loop;

  return to_jsonb(v_ids);
end
$f$;

revoke all on function public.salvar_titulos(jsonb) from public, anon;
grant execute on function public.salvar_titulos(jsonb) to authenticated;

create or replace function public.titulo_valor_tem_que_fechar() returns trigger
language plpgsql security definer set search_path = public as $g$
declare
  soma numeric(12,2);
begin
  select coalesce(sum(valor), 0) into soma from titulo_rateios where titulo_id = new.id;
  if soma > 0 and abs(soma - new.valor) > 0.001 then
    raise exception 'O valor da conta % (R$ %) nao fecha com a soma das partes do rateio (R$ %).', new.id, new.valor, soma;
  end if;
  return null;
end
$g$;
revoke all on function public.titulo_valor_tem_que_fechar() from public, anon, authenticated;

drop trigger if exists trg_titulo_valor_fecha on titulos;
create constraint trigger trg_titulo_valor_fecha
  after update of valor on titulos
  deferrable initially deferred
  for each row execute function public.titulo_valor_tem_que_fechar();

-- ------------------------------------------------------------
-- CONFERENCIA FINAL (uma tabela so)
-- ------------------------------------------------------------
select item, valor, situacao from (
  select 1 as o1, 0::bigint as o2, 'COMPRA CLASSIFICADA | ' || c.nome as item,
         count(*)::text || ' lancamento(s)' as valor,
         'R$ ' || round(sum(l.valor), 2)::text || ' | ids ' || string_agg(l.id::text, ',' order by l.id) as situacao
    from lancamentos_financeiros l
    join centros_custo c on c.id = l.centro_custo_id
   where l.id in (select id from zz_backup_classifica_animais_2026_11_06)
   group by c.nome
  union all
  select 2, 0, 'FUNCAO registrar_venda_animais',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'registrar_venda_animais')::text,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = 'registrar_venda_animais' and not p.prosecdef)
              then 'OK' else 'FALTA' end
  union all
  select 3, 0, 'FUNCAO salvar_titulos',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'salvar_titulos')::text,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = 'salvar_titulos' and not p.prosecdef)
              then 'OK' else 'FALTA' end
  union all
  select 3, 1, 'TRAVA valor da conta fecha com as partes',
         (select count(*) from pg_trigger where tgname = 'trg_titulo_valor_fecha' and not tgisinternal)::text,
         case when exists (select 1 from pg_trigger where tgname = 'trg_titulo_valor_fecha' and not tgisinternal and tgdeferrable and tginitdeferred)
              then 'OK' else 'FALTA' end
  union all
  select 4, extract(epoch from coalesce(f.data, f.vencimento))::bigint * 100000 + f.id,
         'CONFERIR #' || f.id || ' ' || coalesce(to_char(f.data, 'DD/MM/YYYY'), 'sem data')
           || case when f.vencimento is not null then ' (venc. ' || to_char(f.vencimento, 'DD/MM/YYYY') || ')' else '' end,
         'R$ ' || round(f.valor, 2)::text || ' | ' || f.tipo || ' | ' || left(coalesce(c.nome, '(sem centro)'), 40),
         case when f.erp_id is not null then 'importacao' when f.criado_por like 'ERP (acerto%' then 'acerto' else 'a mao' end
           || ' | ' || left(coalesce(nullif(btrim(f.fornecedor), ''), '(sem fornecedor)'), 30)
           || ' | ' || left(coalesce(f.descricao, ''), 40) || ' | obs: ' || left(coalesce(f.observacao, ''), 70)
    from lancamentos_financeiros f
    left join centros_custo c on c.id = f.centro_custo_id
   where coalesce(f.data, f.vencimento) >= date '2025-01-01'
     and (f.fornecedor ilike '%ALEMAR%' or f.descricao ilike '%ALEMAR%' or f.id in (508, 22173, 22307))
) z order by o1, o2;
