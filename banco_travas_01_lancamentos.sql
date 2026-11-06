-- ============================================================
-- TRAVAS DO BANCO nos lancamentos (o app so barrava na tela)
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao apaga nem altera nenhum lancamento: so poe regras que o banco passa a cobrar.
--
-- POR QUE: a tela do app ja nao deixa lancar sem atividade, mas SQL direto, a
-- importacao do ERP e um erro de programa passam por cima. Foi assim que entraram
-- R$ 704 mil repetidos e R$ 979 mil fora das tres atividades. Tres regras:
--   1. o codigo do ERP (erp_id) nao se repete: reimportar o mesmo titulo da erro em
--      vez de duplicar em silencio;
--   2. lancamento em atividade GERAL precisa ter as partes do rateio (so os de menos
--      de R$ 1,00, os centavos de arredondamento do ERP, ficam de fora);
--   3. se tem partes, elas somam o valor do lancamento (diferenca maxima de 5 centavos).
-- As regras 2 e 3 sao conferidas no FIM de cada gravacao (deferidas): a importacao
-- ou o script que grava o lancamento e as partes juntos, na mesma transacao, passa;
-- gravar so o lancamento 'geral', ou mudar o valor sem mudar as partes, e recusado.
--
-- A funcao roda com os direitos do dono do banco (security definer) de proposito: a
-- tabela das partes (lancamento_rateios) e fechada a quem esta logado, e sem isso a
-- trava "nao enxergaria" as partes e barraria ate a edicao normal de um lancamento do
-- ERP. O app continua sem gravar nessa tabela.
--
-- ANTES DE INSTALAR confere se o banco ja esta em ordem. Se houver erro hoje, RECUSA e
-- diz quantos e quais (nao mexe em nada). Conferido em 06/11/2026 pela
-- saude_do_banco_01: erp_id repetido 0, 'geral' sem partes 0, partes que nao fecham 0.
-- Tambem recusa se houver conta a pagar/receber EM ABERTO com parte em atividade Geral:
-- a baixa dela geraria um lancamento 'geral' sem partes e seria barrada na hora de pagar.
-- Troque a atividade dessas partes na tela de Contas e rode de novo.
--
-- Rodar de novo e seguro (recria igual). PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $travas$
declare
  v_n int; v_ids text;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  select count(*), left(string_agg(erp_id, ', ' order by erp_id), 120) into v_n, v_ids
    from (select erp_id from lancamentos_financeiros where erp_id is not null
           group by erp_id having count(*) > 1) x;
  if v_n > 0 then
    raise exception 'Ha % codigo(s) de ERP repetido(s) em lancamentos (%). Resolva antes; nao mexo em nada.', v_n, v_ids;
  end if;

  select count(*), left(string_agg(l.id::text, ', ' order by l.id), 120) into v_n, v_ids
    from lancamentos_financeiros l
   where l.atividade = 'geral' and abs(l.valor) >= 1
     and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id);
  if v_n > 0 then
    raise exception 'Ha % lancamento(s) em atividade Geral sem as partes do rateio (ids: %). Rode a rateio_18/19 e resolva antes; nao mexo em nada.', v_n, v_ids;
  end if;

  select count(*), left(string_agg(l.id::text, ', ' order by l.id), 120) into v_n, v_ids
    from lancamentos_financeiros l
    join (select lancamento_id, sum(valor) as soma from lancamento_rateios group by lancamento_id) p
      on p.lancamento_id = l.id
   where abs(l.valor - p.soma) > 0.05;
  if v_n > 0 then
    raise exception 'Ha % lancamento(s) cujas partes nao somam o valor (ids: %). Rode a rateio_02 e resolva antes; nao mexo em nada.', v_n, v_ids;
  end if;

  select count(*), left(string_agg(distinct t.id::text, ', '), 120) into v_n, v_ids
    from titulo_rateios r join titulos t on t.id = r.titulo_id
   where r.atividade = 'geral' and not t.cancelado and t.valor_baixado < t.valor;
  if v_n > 0 then
    raise exception 'Ha % parte(s) de conta em aberto em atividade Geral (contas: %). Troque a atividade na tela de Contas antes; nao mexo em nada.', v_n, v_ids;
  end if;
end
$travas$;

-- 1. codigo do ERP unico
create unique index if not exists uq_lanc_erp_id
  on lancamentos_financeiros (erp_id) where erp_id is not null;

-- 2 e 3. geral precisa de partes; partes somam o valor (conferido no fim da gravacao)
create or replace function public.confere_partes_do_lancamento() returns trigger
language plpgsql security definer set search_path = public as $f$
declare
  ids bigint[];
  v bigint;
  l record;
  soma numeric;
  n int;
begin
  if tg_table_name = 'lancamentos_financeiros' then
    -- editar outro campo (descricao, fornecedor...) nao muda o valor nem a atividade: nada a conferir
    if tg_op = 'UPDATE' and old.valor = new.valor and old.atividade = new.atividade then
      return null;
    end if;
    ids := array[new.id];
  elsif tg_op = 'INSERT' then
    ids := array[new.lancamento_id];
  elsif tg_op = 'DELETE' then
    ids := array[old.lancamento_id];
  else
    ids := array[new.lancamento_id, old.lancamento_id];
  end if;

  foreach v in array ids loop
    select atividade, valor into l from lancamentos_financeiros where id = v;
    if not found then
      continue;   -- o lancamento foi apagado (as partes saem junto)
    end if;
    select coalesce(sum(valor), 0), count(*) into soma, n from lancamento_rateios where lancamento_id = v;
    if n = 0 and l.atividade = 'geral' and abs(l.valor) >= 1 then
      raise exception 'Lancamento %: esta em atividade Geral e nao tem as partes do rateio. Escolha a atividade ou divida entre as atividades.', v
        using errcode = 'check_violation';
    end if;
    if n > 0 and abs(l.valor - soma) > 0.05 then
      raise exception 'Lancamento %: o valor (R$ %) e as partes do rateio (R$ %) nao fecham.', v, l.valor, soma
        using errcode = 'check_violation';
    end if;
  end loop;
  return null;
end
$f$;

revoke all on function public.confere_partes_do_lancamento() from public, anon, authenticated;

drop trigger if exists trg_confere_partes_lanc on lancamentos_financeiros;
create constraint trigger trg_confere_partes_lanc
  after insert or update of valor, atividade on lancamentos_financeiros
  deferrable initially deferred
  for each row execute function public.confere_partes_do_lancamento();

drop trigger if exists trg_confere_partes_rateio on lancamento_rateios;
create constraint trigger trg_confere_partes_rateio
  after insert or update or delete on lancamento_rateios
  deferrable initially deferred
  for each row execute function public.confere_partes_do_lancamento();

-- conferencia: tudo instalado e nada fora das regras
select item, valor, situacao from (
  select 1 as ord, 'indice unico do codigo do ERP' as item,
         (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'uq_lanc_erp_id')::text as valor,
         case when exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'uq_lanc_erp_id')
              then 'OK' else 'FALTA' end as situacao
  union all
  select 2, 'funcao da trava (security definer)',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'confere_partes_do_lancamento')::text,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = 'confere_partes_do_lancamento' and p.prosecdef)
              then 'OK' else 'FALTA' end
  union all
  select 3, 'gatilho em lancamentos_financeiros',
         (select count(*) from pg_trigger where tgname = 'trg_confere_partes_lanc' and not tgisinternal)::text,
         case when exists (select 1 from pg_trigger where tgname = 'trg_confere_partes_lanc' and not tgisinternal and tgdeferrable and tginitdeferred)
              then 'OK' else 'FALTA' end
  union all
  select 4, 'gatilho em lancamento_rateios',
         (select count(*) from pg_trigger where tgname = 'trg_confere_partes_rateio' and not tgisinternal)::text,
         case when exists (select 1 from pg_trigger where tgname = 'trg_confere_partes_rateio' and not tgisinternal and tgdeferrable and tginitdeferred)
              then 'OK' else 'FALTA' end
  union all
  select 5, 'erp_id repetido hoje',
         (select count(*) from (select erp_id from lancamentos_financeiros where erp_id is not null group by erp_id having count(*) > 1) x)::text,
         case when not exists (select erp_id from lancamentos_financeiros where erp_id is not null group by erp_id having count(*) > 1)
              then 'OK' else 'ERRO' end
  union all
  select 6, 'geral sem partes hoje',
         (select count(*) from lancamentos_financeiros l where l.atividade = 'geral' and abs(l.valor) >= 1
             and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id))::text,
         case when not exists (select 1 from lancamentos_financeiros l where l.atividade = 'geral' and abs(l.valor) >= 1
                                  and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id))
              then 'OK' else 'ERRO' end
  union all
  select 7, 'partes que nao fecham o valor hoje',
         (select count(*) from lancamentos_financeiros l
            join (select lancamento_id, sum(valor) as s from lancamento_rateios group by lancamento_id) p on p.lancamento_id = l.id
           where abs(l.valor - p.s) > 0.05)::text,
         case when not exists (select 1 from lancamentos_financeiros l
                                 join (select lancamento_id, sum(valor) as s from lancamento_rateios group by lancamento_id) p on p.lancamento_id = l.id
                                where abs(l.valor - p.s) > 0.05)
              then 'OK' else 'ERRO' end
) z order by ord;

-- ============================================================
-- PARA DESFAZER (cole e rode so este bloco; nenhum lancamento e tocado):
--
--   drop trigger if exists trg_confere_partes_lanc on lancamentos_financeiros;
--   drop trigger if exists trg_confere_partes_rateio on lancamento_rateios;
--   drop function if exists public.confere_partes_do_lancamento();
--   drop index if exists public.uq_lanc_erp_id;
-- ============================================================
