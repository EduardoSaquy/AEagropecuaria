-- ============================================================
-- CONTA A PAGAR/RECEBER GRAVADA EM UMA OPERACAO SO + O VALOR DO TITULO TEM QUE FECHAR COM AS PARTES
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode. Pode rodar de novo.
-- Nao altera nenhum titulo: cria a funcao salvar_titulos() e uma trava.
--
-- O PROBLEMA (revisao geral de 05/11/2026; foi assim que a conta #107 ficou com as partes em dobro):
--   . lancar uma conta em N parcelas fazia 2 chamadas por parcela; se a 3a falhasse, ficavam 2 parcelas
--     soltas e a pessoa nao sabia;
--   . editar apagava as partes e regravava em chamadas separadas: uma queda de sinal no meio deixava a
--     conta sem rateio;
--   . o banco conferia "partes = valor" quando as PARTES mudavam, mas nao quando o VALOR da conta mudava.
--
-- A FUNCAO salvar_titulos(p_itens): recebe uma lista de contas (cada uma com os dados e as partes do
-- rateio; com "id" e uma edicao, sem "id" e uma conta nova) e grava tudo numa transacao so: ou entram
-- todas as parcelas com as partes, ou nenhuma. Roda com as permissoes de quem chama.
--
-- A TRAVA: mudar o valor de uma conta que ja tem partes so passa se as partes continuarem fechando (a
-- conferencia e feita no fim da gravacao, entao trocar valor e partes juntos, como a funcao faz, passa).
--
-- RECUSA INSTALAR se hoje houver conta cujas partes nao fecham o valor (diz quais).
-- O app novo usa a funcao; se ela nao existir (este script nao rodou), o app usa o caminho antigo.
--
-- PARA DESFAZER:
--   drop trigger if exists trg_titulo_valor_fecha on titulos;
--   drop function if exists public.titulo_valor_tem_que_fechar();
--   drop function if exists public.salvar_titulos(jsonb);
-- ============================================================
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

select item, valor, situacao from (
  select 1 as ord, 'funcao salvar_titulos' as item,
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'salvar_titulos')::text as valor,
         case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname = 'public' and p.proname = 'salvar_titulos' and not p.prosecdef)
              then 'OK' else 'FALTA' end as situacao
  union all
  select 2, 'trava do valor da conta',
         (select count(*) from pg_trigger where tgname = 'trg_titulo_valor_fecha' and not tgisinternal)::text,
         case when exists (select 1 from pg_trigger where tgname = 'trg_titulo_valor_fecha' and not tgisinternal and tgdeferrable and tginitdeferred)
              then 'OK' else 'FALTA' end
  union all
  select 3, 'contas com partes que nao fecham hoje',
         (select count(*) from titulos t join (select titulo_id, sum(valor) as soma from titulo_rateios group by titulo_id) p on p.titulo_id = t.id
           where abs(t.valor - p.soma) > 0.05)::text,
         case when not exists (select 1 from titulos t join (select titulo_id, sum(valor) as soma from titulo_rateios group by titulo_id) p on p.titulo_id = t.id
                                where abs(t.valor - p.soma) > 0.05) then 'OK' else 'ERRO' end
) z order by ord;
