-- ============================================================
-- ESTOQUE 01 - A COMPRA DE INSUMO DA PECUARIA ENTRA NO ESTOQUE JUNTO (13/11/2026)
--
-- Decisao do Eduardo: a compra de racao lancada no AE Matriz (lancamento
-- do Financeiro ou conta a pagar) ja da a entrada no estoque da Pecuaria,
-- com ingrediente, quantidade e valor. Antes eram dois lancamentos e,
-- quando o segundo era esquecido, o estoque ficava negativo (milho com
-- -15,9 t em 11/11/2026). Insumo produzido pela propria empresa (milho da
-- lavoura, silagem) continua entrando pela tela de Entrada da Pecuaria.
--
--  1. movimentos.lancamento_id e movimentos.titulo_id: a entrada sabe de
--     qual compra veio. Apagar o lancamento ou a conta apaga a entrada.
--  2. ingredientes_para_compra(): a lista de ingredientes para quem lanca
--     a compra (a secretaria nao tem a permissao de Insumos).
--  3. entradas_da_compra(lancamento, conta): o que ja entrou por aquela
--     compra (para editar).
--  4. gravar_entradas_da_compra(lancamento, conta, data, itens): troca as
--     entradas da compra pelas novas, numa transacao so; o preco por kg sai
--     de valor / quantidade e o preco medio do ingrediente se refaz.
--  5. Trava: entrada que veio de uma compra so muda pela compra (o app da
--     Pecuaria mostra de onde veio e nao deixa editar nem apagar ali).
--
-- Quem pode: no lancamento, administrador e proprietario, ou quem tem o
-- Financeiro (editar) e lancou aquele lancamento (a mesma regra do
-- lancamento); na conta, quem pode editar contas. Sempre com o codigo do
-- celular se a pessoa tiver.
--
-- Pode rodar de novo. Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.movimentos_leitura') is null or to_regclass('public.zz_config_precos_trancados') is null then
    raise exception 'FORA DE ORDEM. Rode o seguranca_07a e o 07b antes.';
  end if;
end $guarda$;

-- 1. De onde veio a entrada
alter table public.movimentos add column if not exists lancamento_id bigint
  references public.lancamentos_financeiros(id) on delete cascade;
alter table public.movimentos add column if not exists titulo_id bigint
  references public.titulos(id) on delete cascade;
create index if not exists movimentos_lancamento_id_idx on public.movimentos (lancamento_id) where lancamento_id is not null;
create index if not exists movimentos_titulo_id_idx on public.movimentos (titulo_id) where titulo_id is not null;
alter table public.movimentos drop constraint if exists movimentos_uma_compra_so;
alter table public.movimentos add constraint movimentos_uma_compra_so
  check (lancamento_id is null or titulo_id is null);

-- As colunas novas: leitura liberada (nao sao preco) e entram na visao de
-- leitura, que e por onde o app le os movimentos (mesma montagem do 07a).
grant select (lancamento_id, titulo_id) on public.movimentos to authenticated;
do $visao$
declare
  v_lista text; v_tipo_id text;
begin
  select string_agg(case when a.attname = 'preco_kg' then 'p.preco_kg' else format('t.%I', a.attname) end, ', ' order by a.attnum)
    into v_lista
    from pg_attribute a
   where a.attrelid = 'public.movimentos'::regclass and a.attnum > 0 and not a.attisdropped;
  drop view if exists public.movimentos_leitura;
  execute format('create view public.movimentos_leitura with (security_invoker = true) as select %s from public.movimentos t left join public.precos_movimentos() p on p.id = t.id', v_lista);
  revoke all on public.movimentos_leitura from anon, public;
  grant select on public.movimentos_leitura to authenticated;
end $visao$;

-- Regras de quem mexe em qual compra (as mesmas das tabelas)
create or replace function public.pode_mexer_na_compra(p_lancamento bigint, p_titulo bigint, p_editar boolean)
returns boolean language sql stable security definer set search_path = public as $f$
  select public.segundo_fator_ok() and (
    case
      when p_lancamento is not null then exists (
        select 1 from lancamentos_financeiros l
         where l.id = p_lancamento
           and (coalesce(public.acesso_total(), false)
                or (l.criado_por_id = auth.uid()
                    and coalesce(public.tem_permissao('matriz_financeiro', case when p_editar then 'editar' else 'visualizar' end), false))))
      when p_titulo is not null then exists (
        select 1 from titulos t
         where t.id = p_titulo
           and (coalesce(public.is_dono(), false)
                or coalesce(public.tem_permissao('contas', case when p_editar then 'editar' else 'visualizar' end), false)))
      else false
    end)
$f$;
revoke all on function public.pode_mexer_na_compra(bigint, bigint, boolean) from public, anon, authenticated;

-- 2. Ingredientes para o formulario da compra (sem preco)
create or replace function public.ingredientes_para_compra()
returns table (id bigint, nome text, unidade text)
language sql stable security definer set search_path = public as $f$
  select i.id, i.nome, i.unidade from ingredientes i
   where public.segundo_fator_ok()
     and (coalesce(public.acesso_total(), false)
          or coalesce(public.tem_permissao('matriz_financeiro', 'editar'), false)
          or coalesce(public.tem_permissao('contas', 'editar'), false)
          or coalesce(public.tem_permissao('insumos', 'visualizar'), false))
   order by i.nome
$f$;
revoke all on function public.ingredientes_para_compra() from public, anon;
grant execute on function public.ingredientes_para_compra() to authenticated;

-- 3. O que ja entrou por uma compra. O valor so vai a quem ve a compra (que
-- ja ve o valor dela).
create or replace function public.entradas_da_compra(p_lancamento bigint, p_titulo bigint)
returns table (ingrediente_id bigint, quantidade numeric, valor numeric, data date)
language sql stable security definer set search_path = public as $f$
  select m.ingrediente_id, m.quantidade,
         round(m.quantidade * case when i.unidade = 'ton' then 1000 else 1 end * coalesce(m.preco_kg, 0), 2),
         m.data
    from movimentos m join ingredientes i on i.id = m.ingrediente_id
   where ((p_lancamento is not null and m.lancamento_id = p_lancamento)
       or (p_titulo is not null and m.titulo_id = p_titulo))
     and public.pode_mexer_na_compra(p_lancamento, p_titulo, false)
   order by m.id
$f$;
revoke all on function public.entradas_da_compra(bigint, bigint) from public, anon;
grant execute on function public.entradas_da_compra(bigint, bigint) to authenticated;

-- 4. Grava (troca) as entradas de uma compra
create or replace function public.gravar_entradas_da_compra(p_lancamento bigint, p_titulo bigint, p_data date, p_itens jsonb)
returns integer language plpgsql security definer set search_path = public as $f$
declare
  v_total numeric; v_soma numeric := 0; v_n integer := 0; v_tipo text;
  it jsonb; v_ing record; v_qtd numeric; v_val numeric;
  v_afetados bigint[] := '{}';
begin
  if (p_lancamento is null) = (p_titulo is null) then
    raise exception 'Informe o lancamento ou a conta (um dos dois).';
  end if;
  if not public.pode_mexer_na_compra(p_lancamento, p_titulo, true) then
    raise exception 'Sem permissao para mexer nesta compra.' using errcode = '42501';
  end if;
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'Itens invalidos.';
  end if;

  if p_lancamento is not null then
    select l.valor, l.tipo into v_total, v_tipo from lancamentos_financeiros l where l.id = p_lancamento;
    if v_tipo <> 'despesa' and jsonb_array_length(p_itens) > 0 then
      raise exception 'Entrada no estoque so em despesa (compra).';
    end if;
  else
    -- conta parcelada: vale o total da compra (todas as parcelas do grupo)
    select coalesce(sum(t2.valor), max(t.valor)), max(t.tipo) into v_total, v_tipo
      from titulos t left join titulos t2 on t2.grupo = t.grupo and t.grupo is not null and not coalesce(t2.cancelado, false)
     where t.id = p_titulo;
    if v_tipo <> 'pagar' and jsonb_array_length(p_itens) > 0 then
      raise exception 'Entrada no estoque so em conta a pagar (compra).';
    end if;
  end if;

  if jsonb_array_length(p_itens) > 0 and p_data is null then
    raise exception 'Informe a data da entrada no estoque.';
  end if;

  perform set_config('ae.compra_estoque', '1', true);

  select coalesce(array_agg(distinct m.ingrediente_id), '{}') into v_afetados from movimentos m
   where (p_lancamento is not null and m.lancamento_id = p_lancamento)
      or (p_titulo is not null and m.titulo_id = p_titulo);
  delete from movimentos m
   where (p_lancamento is not null and m.lancamento_id = p_lancamento)
      or (p_titulo is not null and m.titulo_id = p_titulo);

  for it in select * from jsonb_array_elements(p_itens) loop
    select i.id, i.unidade into v_ing from ingredientes i where i.id = (it->>'ingrediente_id')::bigint;
    if not found then raise exception 'Ingrediente % nao existe.', it->>'ingrediente_id'; end if;
    v_qtd := (it->>'quantidade')::numeric;
    v_val := (it->>'valor')::numeric;
    if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade tem que ser maior que zero.'; end if;
    if v_val is null or v_val < 0 then raise exception 'Valor do item tem que ser zero ou mais.'; end if;
    v_soma := v_soma + v_val;
    insert into movimentos (data, ingrediente_id, tipo, quantidade, preco_kg, ajuste, lancamento_id, titulo_id)
    values (p_data, v_ing.id, 'entrada', v_qtd,
            case when v_val > 0 then v_val / (v_qtd * case when v_ing.unidade = 'ton' then 1000 else 1 end) else null end,
            false, p_lancamento, p_titulo);
    v_afetados := array_append(v_afetados, v_ing.id);
    v_n := v_n + 1;
  end loop;

  if v_soma > coalesce(v_total, 0) + 0.01 then
    raise exception 'Os itens somam R$ %, mais que o valor da compra (R$ %).', round(v_soma, 2), round(v_total, 2);
  end if;

  -- preco medio de cada ingrediente mexido (inclusive o que saiu)
  perform public.recalcula_preco_ingrediente(x) from (select distinct unnest(v_afetados) x) s;
  perform set_config('ae.compra_estoque', '', true);
  return v_n;
end $f$;
revoke all on function public.gravar_entradas_da_compra(bigint, bigint, date, jsonb) from public, anon;
grant execute on function public.gravar_entradas_da_compra(bigint, bigint, date, jsonb) to authenticated;

-- 5. Trava: entrada de compra so muda pela compra
create or replace function public.movimento_da_compra_so_pela_compra()
returns trigger language plpgsql as $f$
begin
  if coalesce(current_setting('ae.compra_estoque', true), '') = '1' or pg_trigger_depth() > 1 then
    return coalesce(new, old);
  end if;
  if tg_op = 'INSERT' then
    if new.lancamento_id is not null or new.titulo_id is not null then
      raise exception 'Entrada de compra se grava pela compra no AE Matriz.' using errcode = '42501';
    end if;
    return new;
  end if;
  if old.lancamento_id is not null or old.titulo_id is not null
     or (tg_op = 'UPDATE' and (new.lancamento_id is not null or new.titulo_id is not null)) then
    raise exception 'Esta entrada veio de uma compra do AE Matriz: edite ou apague pela compra.' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $f$;
drop trigger if exists trg_movimento_da_compra on public.movimentos;
create trigger trg_movimento_da_compra before insert or update or delete on public.movimentos
  for each row execute function public.movimento_da_compra_so_pela_compra();

-- Conferencia
select item, valor, situacao from (
  select 1 o, 'colunas lancamento_id e titulo_id' item,
         count(*)::text valor, case when count(*) = 2 then 'OK' else 'FALTA' end situacao
    from information_schema.columns where table_schema = 'public' and table_name = 'movimentos'
     and column_name in ('lancamento_id', 'titulo_id')
  union all
  select 2, 'visao de leitura com as colunas novas', count(*)::text, case when count(*) = 2 then 'OK' else 'FALTA' end
    from information_schema.columns where table_schema = 'public' and table_name = 'movimentos_leitura'
     and column_name in ('lancamento_id', 'titulo_id')
  union all
  select 3, 'preco continua trancado na tabela', case when has_column_privilege('authenticated', 'public.movimentos', 'preco_kg', 'SELECT') then 'aberto' else 'trancado' end,
         case when has_column_privilege('authenticated', 'public.movimentos', 'preco_kg', 'SELECT') then 'ABERTO' else 'OK' end
  union all
  select 4, 'funcoes', count(*)::text, case when count(*) = 4 then 'OK' else 'FALTA' end
    from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('pode_mexer_na_compra', 'ingredientes_para_compra', 'entradas_da_compra', 'gravar_entradas_da_compra')
  union all
  select 5, 'trava das entradas de compra', count(*)::text, case when count(*) = 1 then 'OK' else 'FALTA' end
    from pg_trigger where tgname = 'trg_movimento_da_compra' and not tgisinternal
  union all
  select 6, 'movimentos que ja existiam (nenhum mexido)', count(*)::text || ' sem compra ligada', 'OK'
    from public.movimentos where lancamento_id is null and titulo_id is null
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar; apaga as entradas que vieram de compras):
-- drop trigger if exists trg_movimento_da_compra on public.movimentos;
-- drop function if exists public.movimento_da_compra_so_pela_compra();
-- drop function if exists public.gravar_entradas_da_compra(bigint, bigint, date, jsonb);
-- drop function if exists public.entradas_da_compra(bigint, bigint);
-- drop function if exists public.ingredientes_para_compra();
-- drop function if exists public.pode_mexer_na_compra(bigint, bigint, boolean);
-- delete from public.movimentos where lancamento_id is not null or titulo_id is not null;
-- drop view if exists public.movimentos_leitura;
-- alter table public.movimentos drop constraint if exists movimentos_uma_compra_so;
-- alter table public.movimentos drop column if exists titulo_id;
-- alter table public.movimentos drop column if exists lancamento_id;
-- (depois rode o seguranca_07a de novo para recriar a visao movimentos_leitura)
-- ============================================================
