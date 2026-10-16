-- ============================================================
-- A VIEW lancamentos_rateados SO MOSTRA O QUE CADA UM TEM PERMISSAO DE VER
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz), depois do
-- seguranca_01_fecha_view_para_anonimo.sql. Cole inteiro e rode de uma vez.
-- Pode rodar mais de uma vez. Se der erro, NADA muda (o editor roda tudo numa
-- transacao so).
--
-- O QUE ESTAVA ERRADO
--
-- Depois do seguranca_01 so quem esta logado le a view, mas TODO mundo logado
-- lia o Financeiro inteiro por ela, mesmo sem permissao nenhuma (um usuario do
-- Combustivel, por exemplo): a view roda com os direitos de quem a criou e
-- passa por cima das regras (RLS) da tabela lancamentos_financeiros. A tela
-- escondia, o banco nao.
--
-- A REGRA NOVA (a mesma que as telas ja usam; ninguem que usa hoje perde nada)
--
--   ve TUDO ........ admin e proprietario (tem_permissao ja inclui os dois),
--                    quem tem Resultados (matriz_resultados) ou Financeiro
--                    (matriz_financeiro) do Matriz, e o proprio banco
--                    (postgres, service_role): os scripts de conferencia
--                    rodados no editor continuam enxergando tudo;
--   ve SO PECUARIA . quem tem qualquer um destes modulos da Pecuaria, e so as
--                    linhas de atividade 'pecuaria' (inclusive a fatia de um
--                    lancamento "geral" rateada para a pecuaria): pec_financeiro,
--                    pec_resultados, vendas e confinamento, pasto, cria,
--                    lotesGeral (as telas de Pesagem mostram o Custo/@, que
--                    soma o custo fixo vindo desta view);
--   ve NADA ........ todos os outros.
--
-- A tabela lancamentos_financeiros nao muda. Se uma tela nova passar a ler a
-- view para outro perfil, o perfil entra nas duas funcoes abaixo.
--
-- Como a regra e aplicada: a funcao aplicar_regra_na_view_lancamentos_rateados()
-- embrulha a definicao que a view TEM no banco (pg_get_viewdef) num filtro,
-- sem redigitar coluna nenhuma. Os scripts que recriam a view chamam essa
-- funcao no fim (se ela existir), entao recriar a view nao desfaz a regra.
--
-- No fim vem uma lista: o que cada pessoa ativa passa a ver na view. Confira
-- se tem alguem que deveria ver mais.
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.lancamentos_rateados') is null then
    raise exception 'A view lancamentos_rateados nao existe neste banco.';
  end if;
  if to_regprocedure('public.tem_permissao(text,text)') is null then
    raise exception 'A funcao tem_permissao(text, text) nao existe neste banco.';
  end if;
end
$trava$;

-- 1) As duas perguntas. coalesce: quem nao tem a chave nas permissoes recebe
--    NULL de tem_permissao, e NULL nao pode virar "talvez" no filtro.
create or replace function public.ve_todo_o_financeiro() returns boolean
language sql stable as $f$
  select current_user in ('postgres', 'supabase_admin', 'service_role')
      or coalesce(public.tem_permissao('matriz_resultados', 'visualizar'), false)
      or coalesce(public.tem_permissao('matriz_financeiro', 'visualizar'), false)
$f$;

create or replace function public.ve_financeiro_da_pecuaria() returns boolean
language sql stable as $f$
  select coalesce(public.tem_permissao('pec_financeiro', 'visualizar'), false)
      or coalesce(public.tem_permissao('pec_resultados', 'visualizar'), false)
      or coalesce(public.tem_permissao('vendas', 'visualizar'), false)
      or coalesce(public.tem_permissao('confinamento', 'visualizar'), false)
      or coalesce(public.tem_permissao('pasto', 'visualizar'), false)
      or coalesce(public.tem_permissao('cria', 'visualizar'), false)
      or coalesce(public.tem_permissao('lotesGeral', 'visualizar'), false)
$f$;

-- 2) Quem aplica a regra na view (idempotente)
create or replace function public.aplicar_regra_na_view_lancamentos_rateados() returns text
language plpgsql as $f$
declare
  def text;
begin
  if to_regclass('public.lancamentos_rateados') is null then
    return 'A view lancamentos_rateados nao existe.';
  end if;
  def := pg_get_viewdef('public.lancamentos_rateados'::regclass, true);
  if position('ve_todo_o_financeiro' in def) > 0 then
    return 'A view ja tem a regra de permissao.';
  end if;
  def := regexp_replace(def, ';\s*$', '');
  execute 'create or replace view public.lancamentos_rateados as select * from ('
       || def || ') x where (select public.ve_todo_o_financeiro()) '
       || 'or (x.atividade = ''pecuaria'' and (select public.ve_financeiro_da_pecuaria()))';
  return 'Regra de permissao aplicada na view lancamentos_rateados.';
end
$f$;

-- 3) Quem pode chamar o que. Quem le a view precisa poder chamar as duas
--    perguntas (o banco confere isso em nome de quem consulta, nao do dono da
--    view); quem nao esta logado nao precisa de nada; a aplicadora e so do dono.
revoke execute on function public.ve_todo_o_financeiro() from public, anon;
revoke execute on function public.ve_financeiro_da_pecuaria() from public, anon;
revoke execute on function public.aplicar_regra_na_view_lancamentos_rateados() from public, anon, authenticated;
grant execute on function public.ve_todo_o_financeiro() to authenticated, service_role;
grant execute on function public.ve_financeiro_da_pecuaria() to authenticated, service_role;

-- 4) Aplica, e reafirma o fechamento para quem nao esta logado
select public.aplicar_regra_na_view_lancamentos_rateados();

grant select on public.lancamentos_rateados to authenticated;
revoke all on public.lancamentos_rateados from anon;
revoke all on public.lancamentos_rateados from public;

-- 5) O que cada pessoa ativa passa a ver na view (mesma regra, lida das
--    permissoes de cada perfil). 'nada' em quem usa o Matriz ou a Pecuaria
--    para ver numero de dinheiro e um alerta: avise o Claude.
select p.nome, p.papel,
       case
         when not p.ativo then '(inativo)'
         when p.papel in ('admin', 'proprietario') then 'tudo'
         when p.permissoes->>'matriz_resultados' in ('visualizar', 'editar')
           or p.permissoes->>'matriz_financeiro' in ('visualizar', 'editar') then 'tudo'
         when exists (select 1
                        from unnest(array['pec_financeiro', 'pec_resultados', 'vendas',
                                          'confinamento', 'pasto', 'cria', 'lotesGeral']) k
                       where p.permissoes->>k in ('visualizar', 'editar')) then 'so pecuaria'
         else 'nada'
       end as ve_na_view
  from public.profiles p
 order by p.ativo desc, 3, p.nome;
