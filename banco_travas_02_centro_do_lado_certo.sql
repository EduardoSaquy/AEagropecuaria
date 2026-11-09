-- ============================================================
-- TRAVA DO BANCO: O CENTRO DE CUSTO TEM QUE SER DO LADO CERTO
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao apaga nem altera nenhum lancamento: so poe uma regra que o banco passa a cobrar.
--
-- POR QUE: o app ja so oferece centro de ENTRADA para receita e centro de SAIDA para despesa e
-- investimento (tela de lancamento e de contas a pagar/receber). Mas SQL direto e a importacao do ERP
-- passam por cima. Foi assim que 22 receitas (R$ 339 mil) ficaram presas em centro de saida (a4_02,
-- corrigido em 09/11/2026). A regra:
--   1. receita so em centro de ENTRADA; despesa e investimento so em centro de SAIDA;
--   2. centro de custo ainda sem tipo (nao classificado) continua valendo para qualquer lado;
--   3. trocar o lado de um centro que ja tem lancamentos do outro lado tambem e recusado
--      (senao a regra 1 seria burlada por tras).
-- A regra 1 vale na hora de gravar um lancamento novo ou de mudar o tipo ou o centro de um lancamento;
-- editar so o valor ou a descricao de um lancamento antigo nao dispara nada.
--
-- ANTES DE INSTALAR confere se o banco ja esta em ordem. Se hoje houver lancamento do lado errado,
-- RECUSA e diz quantos (nao mexe em nada). Conferido em 09/11/2026: 0.
-- Tambem recusa se houver conta a pagar/receber EM ABERTO com rateio em centro do lado errado: a baixa dela criaria um
-- lancamento do lado errado e seria barrada na hora de pagar. Troque o centro dessas contas na tela de Contas e rode de novo.
--
-- Rodar de novo e seguro (recria igual). PARA DESFAZER: ver o fim deste arquivo.
-- ============================================================

do $trava$
declare
  v_n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  select count(*) into v_n
    from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
   where (l.tipo = 'receita' and c.tipo = 'saida')
      or (l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada');
  if v_n > 0 then
    raise exception 'Ha % lancamento(s) em centro de custo do lado errado. Rode a a4_01_onde_estao_os_22.sql e resolva antes; nao mexo em nada.', v_n;
  end if;
  select count(distinct t.id) into v_n
    from titulos t
    join titulo_rateios r on r.titulo_id = t.id
    join centros_custo c on c.id = r.centro_custo_id
   where coalesce(t.cancelado, false) = false and t.valor_baixado < t.valor
     and ((t.tipo = 'pagar' and c.tipo = 'entrada') or (t.tipo = 'receber' and c.tipo = 'saida'));
  if v_n > 0 then
    raise exception 'Ha % conta(s) a pagar/receber em aberto com rateio em centro do lado errado (a baixa delas seria barrada). Troque o centro na tela de Contas e rode de novo; nao mexo em nada.', v_n;
  end if;
end
$trava$;

-- security definer de proposito: quem grava o lancamento pode nao enxergar a tabela de centros, e a trava
-- precisa ler o lado do centro de qualquer jeito
create or replace function public.confere_lado_do_centro()
returns trigger language plpgsql security definer set search_path = public as $f$
declare
  v_tipo text; v_nome text;
begin
  select tipo, nome into v_tipo, v_nome from centros_custo where id = new.centro_custo_id;
  if v_tipo is null then
    return new;                                  -- centro ainda sem tipo: vale para qualquer lado
  end if;
  if new.tipo = 'receita' and v_tipo <> 'entrada' then
    raise exception 'Receita precisa de centro de custo de ENTRADA, e o centro "%" e de %.', v_nome, upper(v_tipo)
      using errcode = 'check_violation';
  end if;
  if new.tipo in ('despesa', 'investimento') and v_tipo <> 'saida' then
    raise exception '% precisa de centro de custo de SAIDA, e o centro "%" e de %.', initcap(new.tipo), v_nome, upper(v_tipo)
      using errcode = 'check_violation';
  end if;
  return new;
end
$f$;

revoke all on function public.confere_lado_do_centro() from public, anon, authenticated;

drop trigger if exists trg_confere_lado_do_centro on lancamentos_financeiros;
create trigger trg_confere_lado_do_centro
  before insert or update of tipo, centro_custo_id on lancamentos_financeiros
  for each row execute function public.confere_lado_do_centro();

-- trocar o lado de um centro que ja tem lancamentos do outro lado
create or replace function public.confere_troca_de_lado_do_centro()
returns trigger language plpgsql security definer set search_path = public as $f$
declare
  v_n int;
begin
  if new.tipo is not distinct from old.tipo or new.tipo is null then
    return new;
  end if;
  select count(*) into v_n from lancamentos_financeiros l
   where l.centro_custo_id = new.id
     and ((new.tipo = 'saida' and l.tipo = 'receita') or (new.tipo = 'entrada' and l.tipo in ('despesa', 'investimento')));
  if v_n > 0 then
    raise exception 'O centro "%" tem % lancamento(s) do outro lado: nao da para torna-lo de %. Mude os lancamentos de centro antes.', new.nome, v_n, upper(new.tipo)
      using errcode = 'check_violation';
  end if;
  return new;
end
$f$;

revoke all on function public.confere_troca_de_lado_do_centro() from public, anon, authenticated;

drop trigger if exists trg_confere_troca_de_lado on centros_custo;
create trigger trg_confere_troca_de_lado
  before update of tipo on centros_custo
  for each row execute function public.confere_troca_de_lado_do_centro();

-- CONFERENCIA: tudo tem que dizer OK
select item, valor, situacao from (
  select 1 as ord, 'gatilho nos lancamentos' as item,
         (select count(*) from pg_trigger where tgname = 'trg_confere_lado_do_centro' and not tgisinternal)::text as valor,
         case when exists (select 1 from pg_trigger where tgname = 'trg_confere_lado_do_centro' and not tgisinternal) then 'OK' else 'FALTA' end as situacao
  union all
  select 2, 'gatilho nos centros (troca de lado)',
         (select count(*) from pg_trigger where tgname = 'trg_confere_troca_de_lado' and not tgisinternal)::text,
         case when exists (select 1 from pg_trigger where tgname = 'trg_confere_troca_de_lado' and not tgisinternal) then 'OK' else 'FALTA' end
  union all
  select 3, 'funcoes com direitos do dono (security definer)',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('confere_lado_do_centro', 'confere_troca_de_lado_do_centro') and p.prosecdef)::text,
         case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname in ('confere_lado_do_centro', 'confere_troca_de_lado_do_centro') and p.prosecdef) = 2
              then 'OK' else 'FALTA' end
  union all
  select 4, 'contas em aberto com rateio em centro do lado errado (tem que ser 0)',
         (select count(distinct t.id) from titulos t join titulo_rateios r on r.titulo_id = t.id join centros_custo c on c.id = r.centro_custo_id
           where coalesce(t.cancelado, false) = false and t.valor_baixado < t.valor
             and ((t.tipo = 'pagar' and c.tipo = 'entrada') or (t.tipo = 'receber' and c.tipo = 'saida')))::text,
         case when (select count(distinct t.id) from titulos t join titulo_rateios r on r.titulo_id = t.id join centros_custo c on c.id = r.centro_custo_id
                     where coalesce(t.cancelado, false) = false and t.valor_baixado < t.valor
                       and ((t.tipo = 'pagar' and c.tipo = 'entrada') or (t.tipo = 'receber' and c.tipo = 'saida'))) = 0
              then 'OK' else 'ATENCAO' end
  union all
  select 5, 'lancamentos do lado errado hoje (tem que ser 0)',
         (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
           where (l.tipo = 'receita' and c.tipo = 'saida') or (l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada'))::text,
         case when (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
                     where (l.tipo = 'receita' and c.tipo = 'saida') or (l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada')) = 0
              then 'OK' else 'ATENCAO' end
) t
order by ord;

-- ============================================================
-- PARA DESFAZER (copie so este trecho e rode):
--
--   drop trigger if exists trg_confere_lado_do_centro on lancamentos_financeiros;
--   drop trigger if exists trg_confere_troca_de_lado on centros_custo;
--   drop function if exists public.confere_lado_do_centro();
--   drop function if exists public.confere_troca_de_lado_do_centro();
-- ============================================================
