-- ============================================================
-- PASSO 4 - JUNTAR USUARIOS E PERMISSOES
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole o arquivo inteiro e aperte Run. Sao dois comandos.
--
-- ------------------------------------------------------------
-- ESTE SCRIPT PODE (E DEVE) SER RODADO DUAS VEZES
--
-- Na primeira vez ele mostra quais pessoas da Pecuaria ainda nao tem
-- conta aqui. Voce cria essas contas na tela de Usuarios do AE Matriz e
-- roda de novo. Rodar repetido nao causa problema: ele so reescreve as
-- mesmas chaves com os mesmos valores.
--
-- IMPORTANTE ao criar as contas: use EXATAMENTE o mesmo nome de usuario
-- que a pessoa tem na Pecuaria. A autoria dos lancamentos de la
-- (criado_por) e texto com o nome de usuario, nao um identificador
-- interno. Mantendo o mesmo login, todo o historico de quem lancou o que
-- continua valido sozinho.
--
-- ------------------------------------------------------------
-- O QUE ELE FAZ
--
-- 1. Libera o papel "consultor" na tabela profiles (o Lavoura nao tinha
--    esse papel; a Pecuaria tem, e o Irlei usa).
--
-- 2. Le as permissoes direto do banco da Pecuaria, pela ponte que o passo
--    3 deixou montada. Nada e digitado a mao aqui.
--
-- 3. Renomeia duas chaves: financeiro vira pec_financeiro e resultados
--    vira pec_resultados. Essas duas existem nos dois sistemas com
--    significados diferentes - e o unico conflito real da unificacao. As
--    outras nove chaves da Pecuaria nao colidem e entram como estao.
--
-- 4. Mescla com as permissoes que a pessoa ja tem no Lavoura, sem apagar
--    nenhuma. Como as chaves agora sao distintas, uma nao sobrescreve a
--    outra.
--
-- SEGURANCA: exige que o backup do passo 0 exista, porque este e o unico
-- script da unificacao que altera dado de producao que ja existia.
-- ============================================================

do $permissoes$
declare
  faltando int;
begin
  -- ---------- TRAVAS ----------
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'profiles_backup_unificacao') then
    raise exception 'SEM BACKUP. Rode antes o script do passo 0. Este e o unico script que altera dado ja existente.';
  end if;

  if not exists (select 1 from information_schema.schemata
                 where schema_name = 'pec_origem_dados') then
    raise exception 'A ponte com a Pecuaria nao esta montada. Rode antes o script do passo 3.';
  end if;

  -- ---------- LIBERAR O PAPEL CONSULTOR ----------
  alter table profiles drop constraint if exists profiles_papel_check;
  alter table profiles add constraint profiles_papel_check
    check (papel in ('admin','proprietario','gestor','encarregado','colaborador','operador','consultor'));

  -- ---------- RELATORIO ----------
  execute 'drop table if exists zz_relatorio_permissoes';
  execute 'create table zz_relatorio_permissoes (
             usuario text, nome text, situacao text, papel_pecuaria text,
             chaves_lavoura_antes int, chaves_pecuaria int)';

  execute '
    insert into zz_relatorio_permissoes
    select
      pec.usuario,
      pec.nome,
      case when lav.id is null then ''FALTA CRIAR CONTA'' else ''vinculado'' end,
      pec.papel,
      coalesce((select count(*)::int from jsonb_object_keys(lav.permissoes)), 0),
      coalesce((select count(*)::int from jsonb_object_keys(pec.permissoes)), 0)
    from pec_origem_dados.profiles pec
    left join profiles lav on lav.usuario = pec.usuario
    where coalesce(pec.ativo, true) = true';

  -- ---------- MESCLAR AS PERMISSOES ----------
  -- Somente para quem ja tem conta aqui. Quem falta aparece no relatorio.
  update profiles p
  set permissoes = coalesce(p.permissoes, '{}'::jsonb) || origem.permissoes_convertidas,
      papel      = origem.papel
  from (
    select
      pec.usuario,
      pec.papel,
      coalesce(
        (select jsonb_object_agg(
           case par.chave
             when 'financeiro' then 'pec_financeiro'
             when 'resultados' then 'pec_resultados'
             else par.chave
           end,
           par.valor)
         from jsonb_each(coalesce(pec.permissoes, '{}'::jsonb)) as par(chave, valor)),
        '{}'::jsonb
      ) as permissoes_convertidas
    from pec_origem_dados.profiles pec
    where coalesce(pec.ativo, true) = true
  ) origem
  where p.usuario = origem.usuario;

  select count(*) into faltando
  from zz_relatorio_permissoes where situacao = 'FALTA CRIAR CONTA';

  if faltando > 0 then
    raise notice 'ATENCAO: % pessoa(s) da Pecuaria ainda sem conta aqui. Crie na tela de Usuarios do AE Matriz, com o mesmo nome de usuario, e rode este script de novo.', faltando;
  else
    raise notice 'Todas as pessoas da Pecuaria estao vinculadas.';
  end if;
end
$permissoes$;

-- Resultado: quem ja esta vinculado e quem falta criar conta.
select
  r.usuario,
  r.nome,
  r.situacao,
  r.papel_pecuaria,
  p.papel as papel_aqui,
  (select count(*) from jsonb_object_keys(p.permissoes)) as chaves_agora,
  p.permissoes ? 'financeiro'     as tem_financeiro_lavoura,
  p.permissoes ? 'pec_financeiro' as tem_financeiro_pecuaria
from zz_relatorio_permissoes r
left join profiles p on p.usuario = r.usuario
order by r.situacao, r.usuario;
