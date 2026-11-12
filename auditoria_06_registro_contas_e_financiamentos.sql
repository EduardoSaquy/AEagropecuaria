-- auditoria_06_registro_contas_e_financiamentos.sql (12/11/2026)
-- Liga o registro de alteracoes (log_alteracoes, funcao registrar_alteracao da auditoria_05) em mais 6 tabelas:
-- contas a pagar/receber (titulos, titulo_rateios, titulo_baixas), financiamentos (parcelas_financiamento,
-- movimentos_financiamento) e contas_bancarias. Antes so registrava lancamentos_financeiros, abates, profiles,
-- centros_custo e financiamentos.
-- Cada linha nova, alterada ou apagada nessas tabelas grava quem fez, quando, e o antes e o depois.
-- Nao muda nenhum dado. Pode rodar de novo (troca o gatilho pelo mesmo).
-- Desfazer: no fim do arquivo (comentado).

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO: este script e do banco unificado da AE Agropecuaria';
  end if;
  if not exists (select 1 from pg_proc where proname='registrar_alteracao' and pronamespace='public'::regnamespace) then
    raise exception 'Falta a funcao registrar_alteracao (auditoria_05). Nada foi feito.';
  end if;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array['titulos','titulo_rateios','titulo_baixas','parcelas_financiamento','movimentos_financiamento','contas_bancarias']
  loop
    if to_regclass('public.' || t) is null then
      raise notice 'tabela % nao existe, pulada', t;
      continue;
    end if;
    execute format('drop trigger if exists trg_registrar_alteracao on public.%I', t);
    execute format('create trigger trg_registrar_alteracao after insert or update or delete on public.%I '
                   'for each row execute function public.registrar_alteracao()', t);
  end loop;
end $$;

-- Conferencia: cada tabela com o gatilho diz OK
select t as tabela,
       case when exists (select 1 from pg_trigger g
                         where g.tgrelid = to_regclass('public.' || t)
                           and g.tgname = 'trg_registrar_alteracao' and not g.tgisinternal)
            then 'OK: registra alteracoes' else 'FALTA o gatilho' end as situacao
from unnest(array['lancamentos_financeiros','abates','profiles','centros_custo','financiamentos',
                  'titulos','titulo_rateios','titulo_baixas','parcelas_financiamento','movimentos_financiamento',
                  'contas_bancarias']) as t
order by 1;

-- DESFAZER (so se precisar; tira o gatilho das 6 tabelas desta rodada, o historico ja gravado fica):
-- do $$ declare t text; begin
--   foreach t in array array['titulos','titulo_rateios','titulo_baixas','parcelas_financiamento','movimentos_financiamento','contas_bancarias']
--   loop execute format('drop trigger if exists trg_registrar_alteracao on public.%I', t); end loop;
-- end $$;
