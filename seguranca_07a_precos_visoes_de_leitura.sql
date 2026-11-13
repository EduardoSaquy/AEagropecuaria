-- ============================================================
-- SEGURANCA 07a - PRECOS: VISOES DE LEITURA (12/11/2026)
--
-- Rodar ANTES de publicar os apps novos e ANTES do 07b.
-- Nao tira nada de ninguem: so cria, para cada tabela com preco,
-- uma visao <tabela>_leitura com as mesmas colunas, em que o preco
-- vem preenchido so para quem pode ver e vazio para os outros.
-- Os apps novos leem pelas visoes e gravam na tabela de sempre.
--
-- Quem ve o preco:
--   insumo  (ingredientes, movimentos): admin, proprietario e consultor
--   venda   (abates): admin, proprietario e quem tem Vendas
--   total   (inseminacao, nota de diesel, manutencao, entrada de
--            insumo da cana e dos graos): admin e proprietario
-- Quem ativou o codigo no celular precisa da sessao com o codigo.
--
-- Tambem passa para o banco a conta do preco medio do ingrediente
-- (antes o app fazia, com os precos que via; quem nao ve preco
-- gravaria um preco medio errado).
--
-- Pode rodar de novo (recria as visoes com as colunas de hoje).
-- Tabela ganhou coluna nova: rode este e o 07b de novo.
-- Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
end $guarda$;

-- Quem pode ver qual preco. Usa auth.uid() e o JWT (nao current_user),
-- porque roda dentro de funcao security definer. O editor do Supabase
-- (session_user postgres, sem JWT) ve tudo, para as conferencias; com um
-- JWT de alguem (conferencia "entrando como" a pessoa) vale a regra dela.
create or replace function public.pode_ver_preco(p_tipo text)
returns boolean language sql stable security definer set search_path = public as $f$
  select (session_user in ('postgres', 'supabase_admin') and auth.uid() is null)
      or (auth.uid() is not null
          and public.segundo_fator_ok()
          and (coalesce(public.acesso_total(), false)
               or (p_tipo = 'insumo' and exists (select 1 from profiles where id = auth.uid() and ativo and papel = 'consultor'))
               or (p_tipo = 'venda' and coalesce(public.tem_permissao('vendas', 'visualizar'), false))))
$f$;
revoke all on function public.pode_ver_preco(text) from public, anon;
grant execute on function public.pode_ver_preco(text) to authenticated;

create table if not exists public.zz_config_precos_trancados (
  tabela text primary key, colunas text[] not null, tipo text not null, com_visao boolean not null
);
alter table public.zz_config_precos_trancados enable row level security;
revoke all on public.zz_config_precos_trancados from anon, authenticated, public;
drop policy if exists exige_segundo_fator on public.zz_config_precos_trancados;
create policy exige_segundo_fator on public.zz_config_precos_trancados as restrictive for all to authenticated
  using ((select public.segundo_fator_ok())) with check ((select public.segundo_fator_ok()));
insert into public.zz_config_precos_trancados values
  ('ingredientes',          array['preco_kg'],                                  'insumo', true),
  ('movimentos',            array['preco_kg'],                                  'insumo', true),
  ('abates',                array['valor_arroba','valor_por_animal','valor_kg'],'venda',  true),
  ('reproducao_custos',     array['custo'],                                     'total',  true),
  ('entradas_estoque',      array['valor_total'],                               'total',  true),
  ('manutencoes',           array['custo'],                                     'total',  true),
  ('entradas_insumo_cana',  array['preco_pago'],                                'total',  true),
  ('entradas_insumo_graos', array['preco_pago'],                                'total',  true),
  ('receitas_cana',         array['valor_total'],                               'total',  false),
  ('receitas_graos',        array['valor_total'],                               'total',  false),
  ('despesas_cana',         array['valor'],                                     'total',  false),
  ('despesas_graos',        array['valor'],                                     'total',  false)
on conflict (tabela) do update set colunas = excluded.colunas, tipo = excluded.tipo, com_visao = excluded.com_visao;

-- Para cada tabela com visao: funcao precos_<tabela>() (definer, devolve id
-- e os precos so a quem pode) e visao <tabela>_leitura (security_invoker:
-- as linhas seguem a RLS da tabela de quem consulta).
do $visoes$
declare
  c record;
  v_ret text; v_sel text; v_lista text; v_tipo_id text;
begin
  for c in select * from public.zz_config_precos_trancados where com_visao loop
    if to_regclass('public.' || c.tabela) is null then
      raise notice 'tabela % nao existe, pulei', c.tabela; continue;
    end if;
    select format_type(a.atttypid, a.atttypmod) into v_tipo_id
      from pg_attribute a where a.attrelid = ('public.' || c.tabela)::regclass and a.attname = 'id';
    select string_agg(format('%I %s', a.attname, format_type(a.atttypid, a.atttypmod)), ', ' order by a.attnum),
           string_agg(format('t.%I', a.attname), ', ' order by a.attnum)
      into v_ret, v_sel
      from pg_attribute a
     where a.attrelid = ('public.' || c.tabela)::regclass and a.attnum > 0 and not a.attisdropped
       and a.attname = any (c.colunas);
    if v_ret is null then raise exception 'tabela % sem as colunas de preco %', c.tabela, c.colunas; end if;

    execute format('drop view if exists public.%I', c.tabela || '_leitura');
    execute format('drop function if exists public.%I()', 'precos_' || c.tabela);
    execute format($fn$create function public.%I() returns table (id %s, %s)
      language sql stable security definer set search_path = public as $b$
        select t.id, %s from public.%I t where public.pode_ver_preco(%L)
      $b$$fn$, 'precos_' || c.tabela, v_tipo_id, v_ret, v_sel, c.tabela, c.tipo);
    execute format('revoke all on function public.%I() from public, anon', 'precos_' || c.tabela);
    execute format('grant execute on function public.%I() to authenticated', 'precos_' || c.tabela);

    select string_agg(case when a.attname = any (c.colunas) then format('p.%I', a.attname) else format('t.%I', a.attname) end,
                      ', ' order by a.attnum)
      into v_lista
      from pg_attribute a
     where a.attrelid = ('public.' || c.tabela)::regclass and a.attnum > 0 and not a.attisdropped;
    execute format('create view public.%I with (security_invoker = true) as select %s from public.%I t left join public.%I() p on p.id = t.id',
                   c.tabela || '_leitura', v_lista, c.tabela, 'precos_' || c.tabela);
    execute format('revoke all on public.%I from anon, public', c.tabela || '_leitura');
    execute format('grant select on public.%I to authenticated', c.tabela || '_leitura');
  end loop;
end $visoes$;

-- Preco medio do ingrediente: a mesma conta do app (media ponderada em ordem
-- de data e id; saida baixa o estoque; ajuste sem preco nao mexe no preco;
-- unidade ton conta x1000), agora no banco, com todos os precos.
create or replace function public.recalcula_preco_ingrediente(p_ing bigint)
returns void language plpgsql security definer set search_path = public as $f$
declare
  v_unid text; v_est numeric := 0; v_preco numeric; r record; q numeric;
begin
  select unidade into v_unid from ingredientes where id = p_ing;
  if not found then return; end if;
  for r in select tipo, quantidade, preco_kg from movimentos where ingrediente_id = p_ing order by data, id loop
    q := coalesce(r.quantidade, 0) * case when v_unid = 'ton' then 1000 else 1 end;
    if r.tipo = 'entrada' then
      if coalesce(r.preco_kg, 0) <> 0 then
        v_preco := case when v_est > 0 and v_preco is not null
                        then (v_est * v_preco + q * r.preco_kg) / (v_est + q)
                        else r.preco_kg end;
      end if;
      v_est := v_est + q;
    else
      v_est := v_est - q;
    end if;
  end loop;
  if v_preco is not null then
    update ingredientes set preco_kg = v_preco where id = p_ing and preco_kg is distinct from v_preco;
  end if;
end $f$;
revoke all on function public.recalcula_preco_ingrediente(bigint) from public, anon, authenticated;

create or replace function public.movimento_recalcula_preco()
returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if tg_op = 'INSERT' then
    if new.tipo = 'entrada' and coalesce(new.preco_kg, 0) <> 0 then
      perform public.recalcula_preco_ingrediente(new.ingrediente_id);
    end if;
  else
    perform public.recalcula_preco_ingrediente(new.ingrediente_id);
    if old.ingrediente_id is distinct from new.ingrediente_id then
      perform public.recalcula_preco_ingrediente(old.ingrediente_id);
    end if;
  end if;
  return null;
end $f$;
revoke all on function public.movimento_recalcula_preco() from public, anon, authenticated;
drop trigger if exists trg_movimento_recalcula_preco on public.movimentos;
create trigger trg_movimento_recalcula_preco after insert or update on public.movimentos
  for each row execute function public.movimento_recalcula_preco();

-- Conferencia
select item, valor, situacao from (
  select 1 o, 'visoes de leitura' item, count(*)::text valor,
         case when count(*) = 8 then 'OK' else 'FALTA VISAO' end situacao
    from pg_views where schemaname = 'public' and viewname like '%\_leitura'
     and viewname in (select tabela || '_leitura' from public.zz_config_precos_trancados where com_visao)
  union all
  select 2, 'visao com as mesmas linhas da tabela (editor)', string_agg(z.tabela || ' ' || z.n_t || '/' || z.n_v, ', '),
         case when bool_and(z.n_t = z.n_v) then 'OK' else 'DIFERENTE' end
    from (select c.tabela,
                 (xpath('/row/n/text()', query_to_xml(format('select count(*) n from public.%I', c.tabela), false, true, '')))[1]::text n_t,
                 (xpath('/row/n/text()', query_to_xml(format('select count(*) n from public.%I', c.tabela || '_leitura'), false, true, '')))[1]::text n_v
            from public.zz_config_precos_trancados c where c.com_visao and to_regclass('public.' || c.tabela) is not null) z
  union all
  select 3, 'anon sem acesso as visoes', count(*)::text, case when count(*) = 0 then 'OK' else 'ABERTA AO ANON' end
    from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'public' and table_name like '%\_leitura'
  union all
  select 4, 'gatilho do preco medio', count(*)::text, case when count(*) = 1 then 'OK' else 'FALTA' end
    from pg_trigger where tgname = 'trg_movimento_recalcula_preco' and not tgisinternal
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar; depois de desfazer o 07b):
-- drop trigger if exists trg_movimento_recalcula_preco on public.movimentos;
-- drop function if exists public.movimento_recalcula_preco();
-- drop function if exists public.recalcula_preco_ingrediente(bigint);
-- do $d$ declare c record; begin for c in select tabela from public.zz_config_precos_trancados where com_visao loop
--   execute format('drop view if exists public.%I', c.tabela || '_leitura');
--   execute format('drop function if exists public.%I()', 'precos_' || c.tabela); end loop; end $d$;
-- drop function if exists public.pode_ver_preco(text);
-- drop table if exists public.zz_config_precos_trancados;
-- ============================================================
