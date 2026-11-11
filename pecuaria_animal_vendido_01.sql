-- pecuaria_animal_vendido_01.sql  (11/11/2026, pedido do Eduardo na revisao geral)
--
-- Animal vendido sai do cadastro ativo.
-- Antes: a venda baixava so a contagem do lote (lotes.numero_animais) e o
-- cadastro individual ficava "ativo" para sempre. Em 10/11/2026 havia 202
-- animais "ativos" nos Currais 1 e 2, lotes ja vendidos e encerrados.
--
-- O que este script faz (tudo ou nada):
--  1. animais.status passa a aceitar 'vendido'; coluna nova animais.data_saida.
--  2. Gatilho em lotes: quando a venda zera o lote e ele ganha data de
--     encerramento (lote com venda registrada em abates), os animais que
--     ainda estao nele viram 'vendido' com data_saida = data de encerramento.
--     Excluir ou editar a venda reabre o lote e desfaz (volta a 'ativo' so
--     quem saiu naquela data). Vale para todos os caminhos de venda: AE
--     Pecuaria (na hora e pela fila sem internet), edicao, exclusao e AE
--     Matriz (registrar_venda_animais). security definer: quem vende pode
--     nao ter permissao de mexer em animais, e sem isso a baixa sairia vazia
--     sem erro.
--  3. Acerta o que ja existe: lote ja encerrado pela venda com animal ativo.
--  4. Conferencia numa consulta so (item / valor / situacao).
-- Desfazer: no fim do arquivo, comentado.

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas')
     or not exists (select 1 from information_schema.tables where table_schema='public' and table_name='animais')
     or not exists (select 1 from information_schema.tables where table_schema='public' and table_name='abates') then
    raise exception 'PROJETO ERRADO: rode no projeto do AE (Matriz/Pecuaria).';
  end if;
  if exists (select 1 from public.animais where status not in ('ativo','morto','vendido')) then
    raise exception 'Existe animal com status fora de ativo/morto/vendido. Nada foi mudado.';
  end if;
end $$;

alter table public.animais add column if not exists data_saida date;

alter table public.animais drop constraint if exists animais_status_check;
alter table public.animais add constraint animais_status_check
  check (status in ('ativo','morto','vendido'));

alter table public.animais drop constraint if exists animais_vendido_tem_data;
alter table public.animais add constraint animais_vendido_tem_data
  check (status <> 'vendido' or data_saida is not null);

create or replace function public.trg_lote_baixa_animais()
returns trigger
language plpgsql
security definer
set search_path = public
as $f$
begin
  -- lote encerrado pela venda: zerou e tem data de encerramento
  if new.data_fim is not null
     and coalesce(new.numero_animais, 0) = 0
     and (old.data_fim is null or coalesce(old.numero_animais, 0) > 0)
     and exists (select 1 from public.abates ab where ab.lote_id = new.id) then
    update public.animais
       set status = 'vendido', data_saida = new.data_fim
     where lote_id = new.id and status = 'ativo';
  -- lote reaberto (venda excluida ou editada): volta quem saiu naquela data
  elsif old.data_fim is not null and new.data_fim is null then
    update public.animais
       set status = 'ativo', data_saida = null
     where lote_id = new.id and status = 'vendido' and data_saida = old.data_fim;
  -- data de encerramento mudou
  elsif old.data_fim is not null and new.data_fim is not null and new.data_fim <> old.data_fim then
    update public.animais
       set data_saida = new.data_fim
     where lote_id = new.id and status = 'vendido' and data_saida = old.data_fim;
  end if;
  return new;
end
$f$;

revoke all on function public.trg_lote_baixa_animais() from public, anon, authenticated;

drop trigger if exists trg_lote_baixa_animais on public.lotes;
create trigger trg_lote_baixa_animais
  after update of data_fim, numero_animais on public.lotes
  for each row execute function public.trg_lote_baixa_animais();

-- o que ja existe: lote encerrado pela venda com animal ainda ativo
update public.animais a
   set status = 'vendido', data_saida = l.data_fim
  from public.lotes l
 where a.lote_id = l.id
   and a.status = 'ativo'
   and l.data_fim is not null
   and coalesce(l.numero_animais, 0) = 0
   and exists (select 1 from public.abates ab where ab.lote_id = l.id);

-- conferencia
select 1 as ordem, 'coluna data_saida' as item,
       case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='animais' and column_name='data_saida') then 'existe' else 'NAO existe' end as valor,
       case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='animais' and column_name='data_saida') then 'OK' else 'ERRO' end as situacao
union all
select 2, 'status aceita vendido', pg_get_constraintdef(oid),
       case when pg_get_constraintdef(oid) like '%vendido%' then 'OK' else 'ERRO' end
  from pg_constraint where conname = 'animais_status_check'
union all
select 3, 'gatilho na tabela lotes',
       coalesce((select tgname::text from pg_trigger where tgname='trg_lote_baixa_animais' and not tgisinternal), 'nao existe'),
       case when exists (select 1 from pg_trigger where tgname='trg_lote_baixa_animais' and tgenabled <> 'D') then 'OK' else 'ERRO' end
union all
select 4, 'animais vendidos por lote',
       coalesce((select string_agg(l.nome || ': ' || n, ', ' order by l.nome)
                   from (select lote_id, count(*) n from public.animais where status='vendido' group by 1) v
                   join public.lotes l on l.id = v.lote_id), 'nenhum'),
       'OK'
union all
select 5, 'animal ativo em lote encerrado pela venda',
       count(*)::text,
       case when count(*) = 0 then 'OK' else 'ERRO' end
  from public.animais a join public.lotes l on l.id = a.lote_id
 where a.status = 'ativo' and l.data_fim is not null and coalesce(l.numero_animais,0) = 0
   and exists (select 1 from public.abates ab where ab.lote_id = l.id)
union all
select 6, 'lote com mais animais numerados que cabecas vendidas',
       coalesce((select string_agg(x.nome || ': ' || x.numerados || ' numerados x ' || x.vendidas || ' vendidas', ', ')
                   from (select l.nome,
                                (select count(*) from public.animais a where a.lote_id = l.id and a.status='vendido') numerados,
                                (select sum(quantidade) from public.abates ab where ab.lote_id = l.id) vendidas
                           from public.lotes l
                          where l.data_fim is not null and coalesce(l.numero_animais,0) = 0) x
                  where x.numerados > coalesce(x.vendidas,0)), 'nenhum'),
       case when exists (select 1 from public.lotes l
                          where l.data_fim is not null and coalesce(l.numero_animais,0) = 0
                            and (select count(*) from public.animais a where a.lote_id = l.id and a.status='vendido')
                                > coalesce((select sum(quantidade) from public.abates ab where ab.lote_id = l.id),0))
            then 'ATENCAO: se algum continua na fazenda, Nao foi vendido no lote dele no app' else 'OK' end
union all
select 7, 'vendido sem data de saida',
       count(*)::text, case when count(*) = 0 then 'OK' else 'ERRO' end
  from public.animais where status = 'vendido' and data_saida is null
union all
select 8, 'animais ativos no total', count(*)::text, 'OK'
  from public.animais where status = 'ativo'
order by 1;

-- DESFAZER (so se precisar; rode as linhas abaixo sem os dois tracos):
-- drop trigger if exists trg_lote_baixa_animais on public.lotes;
-- drop function if exists public.trg_lote_baixa_animais();
-- update public.animais set status = 'ativo', data_saida = null where status = 'vendido';
-- alter table public.animais drop constraint if exists animais_vendido_tem_data;
-- alter table public.animais drop constraint if exists animais_status_check;
-- alter table public.animais add constraint animais_status_check check (status in ('ativo','morto'));
-- alter table public.animais drop column if exists data_saida;
