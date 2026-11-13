-- ============================================================
-- ERP - TRAVA CONTRA REIMPORTAR O QUE JA FOI APAGADO (13/11/2026)
--
-- Os lancamentos do ERP que foram apagados de proposito (duplicatas, as
-- parcelas pessoais, os pares repetidos) continuam no ERP: uma carga nova
-- os traria de volta sem ninguem ver. Os apps nunca gravam erp_id, entao
-- todo lancamento com erp_id vem de importacao.
--
-- 1) erp_nao_reimportar: lista dos titulos do ERP apagados de proposito.
--    Comeca com os do registro de alteracoes e das copias zz_backup_* que
--    nao existem mais, e o banco acrescenta sozinho todo lancamento com
--    erp_id que for apagado daqui para a frente.
-- 2) Trava ao gravar lancamento com erp_id:
--    a) titulo da lista: recusado. Para filtrar na importacao:
--       ... where erp_id not in (select erp_id from erp_nao_reimportar)
--    b) Cana ou Pecuaria com competencia ou data de 2026-01 em diante:
--       recusado (essa despesa ja e lancada a mao no app desde janeiro; a
--       importacao de agosto duplicou tudo). Quem conferiu antes libera so
--       na propria transacao: select set_config('ae.importacao_conferida','sim',true);
--
-- Apagar uma linha da lista libera aquele titulo. Pode rodar de novo.
-- Desfazer: no fim do arquivo.
-- ============================================================

do $guarda$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
end $guarda$;

create table if not exists public.erp_nao_reimportar (
  erp_id      text primary key,
  valor       numeric,
  motivo      text,
  apagado_em  timestamptz not null default now()
);
alter table public.erp_nao_reimportar enable row level security;
revoke all on public.erp_nao_reimportar from anon, public, authenticated;
drop policy if exists exige_segundo_fator on public.erp_nao_reimportar;
create policy exige_segundo_fator on public.erp_nao_reimportar as restrictive
  for all to authenticated using ((select public.segundo_fator_ok())) with check ((select public.segundo_fator_ok()));

-- Ponto de partida: o que o registro de alteracoes viu apagar e o que esta nas copias de seguranca
insert into public.erp_nao_reimportar (erp_id, valor, motivo, apagado_em)
select a.antes->>'erp_id', (a.antes->>'valor')::numeric, 'apagado (registro de alteracoes)', min(a.quando)
  from public.log_alteracoes a
 where a.tabela = 'lancamentos_financeiros' and a.operacao = 'DELETE' and a.antes->>'erp_id' is not null
   and not exists (select 1 from public.lancamentos_financeiros l where l.erp_id = a.antes->>'erp_id')
 group by 1, 2
on conflict (erp_id) do nothing;

do $copias$
declare t text;
begin
  for t in select c.table_name from information_schema.columns c
            where c.table_schema = 'public' and c.table_name like 'zz\_backup\_%' and c.column_name = 'erp_id'
              and exists (select 1 from information_schema.columns v where v.table_schema = 'public'
                           and v.table_name = c.table_name and v.column_name = 'valor')
              and (c.table_name like 'zz\_backup\_dup%' or c.table_name like 'zz\_backup\_lanc\_pessoais%')
              and c.table_name not like '%rateios%' and c.table_name not like '%pares%'
  loop
    execute format(
      'insert into public.erp_nao_reimportar (erp_id, valor, motivo)
       select b.erp_id::text, b.valor, %L from public.%I b
        where b.erp_id is not null
          and not exists (select 1 from public.lancamentos_financeiros l where l.erp_id = b.erp_id::text)
       on conflict (erp_id) do nothing', 'apagado (copia ' || t || ')', t);
  end loop;
end $copias$;

-- Anota sozinho todo lancamento do ERP apagado daqui para a frente
create or replace function public.erp_anota_apagado()
returns trigger language plpgsql security definer set search_path = public as $f$
begin
  if old.erp_id is not null then
    insert into erp_nao_reimportar (erp_id, valor, motivo)
    values (old.erp_id::text, old.valor, 'apagado em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'))
    on conflict (erp_id) do nothing;
  end if;
  return old;
end $f$;
drop trigger if exists trg_erp_anota_apagado on public.lancamentos_financeiros;
create trigger trg_erp_anota_apagado after delete on public.lancamentos_financeiros
  for each row execute function public.erp_anota_apagado();

-- Trava ao gravar
create or replace function public.erp_trava_reimportacao()
returns trigger language plpgsql security definer set search_path = public as $f$
declare v_quando text;
begin
  if new.erp_id is null then return new; end if;
  if tg_op = 'UPDATE' and old.erp_id is not distinct from new.erp_id then return new; end if;
  select to_char(apagado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') into v_quando
    from erp_nao_reimportar where erp_id = new.erp_id::text;
  if found then
    raise exception 'O titulo % do ERP foi apagado de proposito em % e nao volta. Filtre a importacao com: where erp_id not in (select erp_id from erp_nao_reimportar)', new.erp_id, v_quando
      using errcode = 'P0001';
  end if;
  if new.atividade in ('cana', 'pecuaria')
     and coalesce(new.mes, to_char(new.data, 'YYYY-MM')) >= '2026-01'
     and coalesce(current_setting('ae.importacao_conferida', true), '') <> 'sim' then
    raise exception 'Titulo % do ERP (%, %): Cana e Pecuaria de 2026 em diante ja sao lancadas a mao no app. Confira contra o que ja esta lancado e, se for mesmo novo, rode antes na mesma transacao: select set_config(''ae.importacao_conferida'',''sim'',true);',
      new.erp_id, new.atividade, coalesce(new.mes, to_char(new.data, 'YYYY-MM'))
      using errcode = 'P0001';
  end if;
  return new;
end $f$;
drop trigger if exists trg_erp_trava_reimportacao on public.lancamentos_financeiros;
create trigger trg_erp_trava_reimportacao before insert or update of erp_id on public.lancamentos_financeiros
  for each row execute function public.erp_trava_reimportacao();

select item, valor, situacao from (
  select 1 o, 'titulos do ERP na lista de nao reimportar' item, count(*)::text || ' (R$ ' || coalesce(to_char(sum(valor), 'FM999G999G990D00'), '0') || ')' valor,
         case when count(*) > 0 then 'OK' else 'CONFERIR' end situacao
    from public.erp_nao_reimportar
  union all
  select 2, 'algum da lista ainda esta no Financeiro', count(*)::text,
         case when count(*) = 0 then 'OK' else 'CONFERIR' end
    from public.erp_nao_reimportar e where exists (select 1 from public.lancamentos_financeiros l where l.erp_id = e.erp_id)
  union all
  select 3, 'gatilhos instalados', count(*)::text,
         case when count(*) = 2 then 'OK' else 'FALTA' end
    from pg_trigger where not tgisinternal and tgname in ('trg_erp_anota_apagado', 'trg_erp_trava_reimportacao')
  union all
  select 4, 'lista fechada a quem esta logado e ao anonimo',
         case when has_table_privilege('authenticated', 'public.erp_nao_reimportar', 'select')
                or has_table_privilege('anon', 'public.erp_nao_reimportar', 'select') then 'aberta' else 'fechada' end,
         case when has_table_privilege('authenticated', 'public.erp_nao_reimportar', 'select')
                or has_table_privilege('anon', 'public.erp_nao_reimportar', 'select') then 'CONFERIR' else 'OK' end
) x order by o;

-- ============================================================
-- DESFAZER (so se precisar):
-- drop trigger if exists trg_erp_trava_reimportacao on public.lancamentos_financeiros;
-- drop trigger if exists trg_erp_anota_apagado on public.lancamentos_financeiros;
-- drop function if exists public.erp_trava_reimportacao();
-- drop function if exists public.erp_anota_apagado();
-- drop table if exists public.erp_nao_reimportar;
-- ============================================================
