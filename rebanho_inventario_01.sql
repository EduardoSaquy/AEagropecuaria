-- ============================================================
-- REBANHO 01 - FOTO MENSAL DO REBANHO (13/11/2026)
--
-- Decisao do Eduardo: resultado economico da Pecuaria = resultado de caixa
-- + (rebanho no fim do periodo - rebanho no comeco). O app so sabia o
-- rebanho de hoje; agora o banco guarda, todo dia 1o as 00:05 (Brasilia),
-- uma foto de cada lote ativo: cabecas, peso medio da ultima pesagem ate o
-- dia, arrobas e valor. Valor = mesma conta do "Rebanho estocado" do AE
-- Matriz: peso vivo x 50% de carcaca / 15 kg, vezes o ultimo preco da @
-- lancado ate o dia (femea para lote de femeas, macho nos demais; sem o do
-- sexo, usa o outro). Lote sem pesagem (vacas, novilhas) usa o PESO DE
-- REFERENCIA do lote (coluna nova lotes.peso_referencia_kg, informada no
-- AE Pecuaria; decisao do Eduardo, 13/11/2026); sem os dois, entra so com
-- as cabecas, sem valor. A pesagem real, quando existe, manda.
--
-- Quem le: so administrador e proprietario (e valor de rebanho). Ninguem
-- grava pela API: so a funcao, pela tarefa do banco (pg_cron).
-- A primeira foto sai em 01/12/2026; o resultado economico de um mes pede a
-- foto do dia 1o dele e a do mes seguinte.
--
-- Pode rodar de novo. Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
end $guarda$;

alter table public.lotes add column if not exists peso_referencia_kg numeric;
alter table public.lotes drop constraint if exists lotes_peso_referencia_ok;
alter table public.lotes add constraint lotes_peso_referencia_ok
  check (peso_referencia_kg is null or (peso_referencia_kg >= 20 and peso_referencia_kg <= 1000));

create table if not exists public.rebanho_inventario (
  id            bigserial primary key,
  data          date not null,
  lote_id       bigint not null,
  lote_nome     text,
  destino       text,
  sexo          text,
  cabecas       numeric not null,
  peso_medio    numeric,
  data_pesagem  date,
  origem_peso   text,
  arrobas       numeric,
  preco_arroba  numeric,
  valor         numeric,
  criado_em     timestamptz not null default now(),
  unique (data, lote_id)
);
alter table public.rebanho_inventario enable row level security;
revoke all on public.rebanho_inventario from anon, public, authenticated;
grant select on public.rebanho_inventario to authenticated;
drop policy if exists "ve foto do rebanho" on public.rebanho_inventario;
create policy "ve foto do rebanho" on public.rebanho_inventario
  for select to authenticated using ((select public.acesso_total()));
drop policy if exists exige_segundo_fator on public.rebanho_inventario;
create policy exige_segundo_fator on public.rebanho_inventario as restrictive
  for all to authenticated using ((select public.segundo_fator_ok())) with check ((select public.segundo_fator_ok()));

-- Tira (ou refaz) a foto de um dia. Refazer o mesmo dia troca a foto dele.
create or replace function public.fotografar_rebanho(p_data date)
returns integer language plpgsql security definer set search_path = public as $f$
declare v_n integer;
begin
  if p_data is null then raise exception 'Informe o dia da foto.'; end if;
  delete from rebanho_inventario where data = p_data;
  insert into rebanho_inventario (data, lote_id, lote_nome, destino, sexo, cabecas, peso_medio, data_pesagem, origem_peso, arrobas, preco_arroba, valor)
  select p_data, l.id, l.nome, l.destino, l.sexo, l.numero_animais,
         pm.peso, pes.data,
         case when pes.peso_medio_kg is not null then 'pesagem' when l.peso_referencia_kg is not null then 'referencia' end,
         round(l.numero_animais * pm.peso * 0.5 / 15, 4),
         pr.valor,
         round(l.numero_animais * pm.peso * 0.5 / 15 * pr.valor, 2)
    from lotes l
    left join lateral (
      select p.peso_medio_kg, p.data from pesagens p
       where p.lote_id = l.id and p.data <= p_data and p.peso_medio_kg > 0
       order by p.data desc, p.id desc limit 1) pes on true
    cross join lateral (select coalesce(pes.peso_medio_kg, l.peso_referencia_kg) as peso) pm
    left join lateral (
      select a.valor from precos_arroba a
       where a.data <= p_data and a.valor > 0
       order by (a.sexo = case when l.sexo = 'femea' then 'femea' else 'macho' end) desc, a.data desc, a.id desc
       limit 1) pr on pm.peso is not null
   where l.data_fim is null and coalesce(l.numero_animais, 0) > 0;
  get diagnostics v_n = row_count;
  return v_n;
end $f$;
revoke all on function public.fotografar_rebanho(date) from public, anon, authenticated;

-- Tarefa do banco: dia 1o as 03:05 UTC = 00:05 em Brasilia.
create extension if not exists pg_cron;
do $agenda$
begin
  if exists (select 1 from cron.job where jobname = 'ae-foto-do-rebanho') then
    perform cron.unschedule('ae-foto-do-rebanho');
  end if;
  perform cron.schedule('ae-foto-do-rebanho', '5 3 1 * *',
    $$select public.fotografar_rebanho((now() at time zone 'America/Sao_Paulo')::date)$$);
end $agenda$;

-- Conferencia (nao grava foto: so mostra como ficaria hoje)
select item, valor, situacao from (
  select 1 o, 'tabela das fotos' item, coalesce(to_regclass('public.rebanho_inventario')::text, 'falta') valor,
         case when to_regclass('public.rebanho_inventario') is not null then 'OK' else 'FALTA' end situacao
  union all
  select 2, 'leitura so admin e proprietario', count(*)::text || ' regra(s)',
         case when count(*) = 2 then 'OK' else 'CONFERIR' end
    from pg_policies where tablename = 'rebanho_inventario'
  union all
  select 3, 'tarefa do dia 1o', coalesce(max(schedule), 'falta'),
         case when count(*) = 1 then 'OK' else 'FALTA' end
    from cron.job where jobname = 'ae-foto-do-rebanho'
  union all
  select 4, 'peso de referencia nos lotes', case when exists (select 1 from information_schema.columns where table_schema='public'
           and table_name='lotes' and column_name='peso_referencia_kg') then 'coluna criada' else 'falta' end,
         case when exists (select 1 from information_schema.columns where table_schema='public'
           and table_name='lotes' and column_name='peso_referencia_kg') then 'OK' else 'FALTA' end
  union all
  select 5, 'lotes que entrariam numa foto hoje', count(*)::text || ' lotes, ' || coalesce(sum(numero_animais), 0)::text || ' cabecas', 'OK'
    from public.lotes where data_fim is null and coalesce(numero_animais, 0) > 0
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar; apaga as fotos guardadas):
-- select cron.unschedule('ae-foto-do-rebanho');
-- drop function if exists public.fotografar_rebanho(date);
-- drop table if exists public.rebanho_inventario;
-- alter table public.lotes drop constraint if exists lotes_peso_referencia_ok;
-- alter table public.lotes drop column if exists peso_referencia_kg;
-- ============================================================
