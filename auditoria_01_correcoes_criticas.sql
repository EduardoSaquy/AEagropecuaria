-- ============================================================
-- CORRECOES CRITICAS ENCONTRADAS NA AUDITORIA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O QUE ELE CONSERTA
--
-- 1. Tabelas de backup abertas para qualquer um
--
--    profiles_backup_unificacao e funcionarios_backup_limpeza foram criadas
--    com "create table as select" e nunca receberam RLS. No Supabase, tabela
--    sem RLS no schema public e lida E gravada por qualquer requisicao com a
--    chave publica - que esta a vista no codigo-fonte das paginas.
--
--    A primeira delas e copia integral de profiles: nome, login, papel e a
--    matriz de permissoes de todo mundo. Erro meu: criei o backup pensando
--    em recuperacao e nao em quem consegue le-lo.
--
-- 2. Quem tem permissao da pecuaria nao consegue registrar venda
--
--    As politicas de lancamentos_financeiros so aceitam matriz_financeiro.
--    A Pecuaria usa pec_financeiro. Efeito: o Financeiro da Pecuaria mostra
--    R$ 0,00 (RLS devolve lista vazia, sem erro) e, ao registrar uma venda,
--    o abate grava, a receita e recusada e o app desfaz o abate. A venda
--    inteira nao acontece.
--
-- 3. Mes aceita texto invalido
--
--    Quando data e nula o CHECK nao olha o mes. Um '2025-7' ou '2025-13'
--    entra e o lancamento some de TODOS os relatorios - nao some da tabela,
--    some do total, que e pior. Mesma familia do erro que levou o custo de
--    R$ 43.928,73 para mais de um milhao, na direcao oposta.
--
-- 4. Indices que faltam
--
--    Os apps filtram por atividade, e o indice existente e (tipo,atividade),
--    que nao serve para predicado so na segunda coluna. E nenhuma chave
--    estrangeira tem indice: excluir centro de custo varre a tabela inteira.
-- ============================================================

do $audit$
declare
  t text;
  n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- ---------- 1) FECHAR AS TABELAS DE BACKUP ----------
  -- Sem politica nenhuma depois de ligar a RLS, elas ficam acessiveis so
  -- pela service_role (o painel do Supabase e as Edge Functions). E o que
  -- se quer de um backup: ninguem le pelo app, e voce continua lendo pelo
  -- SQL Editor.
  foreach t in array array[
    'profiles_backup_unificacao',
    'funcionarios_backup_limpeza',
    'zz_limpeza_relatorio'
  ] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t) then
      execute format('alter table public.%I enable row level security', t);
      -- Ligar a RLS ja basta (sem politica, ninguem passa). O revoke e
      -- cinto e suspensorio, e so roda se o papel existir - fora do
      -- Supabase esses papeis nao existem e o comando quebraria o script.
      if exists (select 1 from pg_roles where rolname = 'anon') then
        execute format('revoke all on public.%I from anon', t);
      end if;
      if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute format('revoke all on public.%I from authenticated', t);
      end if;
      raise notice 'Fechada: %', t;
    end if;
  end loop;

  -- ---------- 2) PECUARIA VOLTA A ENXERGAR E LANCAR ----------
  -- Acrescenta pec_financeiro ao lado de matriz_financeiro. Nao e o mesmo
  -- que dar matriz_financeiro a todo mundo: isso abriria tambem o
  -- financeiro da lavoura para a equipe da pecuaria.
  drop policy if exists "ve lancamentos"     on lancamentos_financeiros;
  drop policy if exists "lanca"              on lancamentos_financeiros;
  drop policy if exists "edita lancamentos"  on lancamentos_financeiros;
  drop policy if exists "exclui lancamentos" on lancamentos_financeiros;

  create policy "ve lancamentos" on lancamentos_financeiros for select
    using (is_admin()
        or tem_permissao('matriz_financeiro','visualizar')
        or tem_permissao('pec_financeiro','visualizar')
        or tem_permissao('pec_resultados','visualizar'));

  create policy "lanca" on lancamentos_financeiros for insert
    with check (is_admin()
        or tem_permissao('matriz_financeiro','editar')
        -- a venda no AE Pecuaria cria a receita junto com o abate
        or tem_permissao('pec_resultados','editar'));

  create policy "edita lancamentos" on lancamentos_financeiros for update
    using      (is_admin() or tem_permissao('matriz_financeiro','editar')
                           or tem_permissao('pec_resultados','editar'))
    with check (is_admin() or tem_permissao('matriz_financeiro','editar')
                           or tem_permissao('pec_resultados','editar'));

  create policy "exclui lancamentos" on lancamentos_financeiros for delete
    using (is_admin() or tem_permissao('matriz_financeiro','editar')
                      or tem_permissao('pec_resultados','editar'));
  raise notice 'Politicas de lancamentos_financeiros passam a aceitar a pecuaria.';

  -- ---------- 3) MES SO ACEITA AAAA-MM ----------
  select count(*) into n from lancamentos_financeiros
   where mes is not null and mes !~ '^\d{4}-(0[1-9]|1[0-2])$';
  if n > 0 then
    raise exception
      'Existem % lancamentos com mes fora do formato AAAA-MM. Eles estao invisiveis nos relatorios. Rode a consulta de diagnostico no fim deste arquivo antes de continuar.', n;
  end if;

  alter table lancamentos_financeiros drop constraint if exists mes_formato_valido;
  alter table lancamentos_financeiros add constraint mes_formato_valido
    check (mes is null or mes ~ '^\d{4}-(0[1-9]|1[0-2])$');
  raise notice 'Formato do mes travado em AAAA-MM.';
end
$audit$;


-- ------------------------------------------------------------
-- 4) INDICES
--
-- Os apps filtram por atividade sozinha; (tipo, atividade) nao serve.
-- As chaves estrangeiras sem indice fazem varredura completa da tabela ao
-- excluir o registro pai - e e justamente pela FK que o app impede excluir
-- centro de custo em uso.
-- ------------------------------------------------------------
create index if not exists idx_lanc_fin_atividade      on lancamentos_financeiros (atividade, tipo);
create index if not exists idx_lanc_fin_centro         on lancamentos_financeiros (centro_custo_id);
create index if not exists idx_lanc_fin_data           on lancamentos_financeiros (data);
create index if not exists idx_lanc_fin_talhao         on lancamentos_financeiros (talhao_id);
create index if not exists idx_lanc_fin_lote           on lancamentos_financeiros (lote_id);

analyze lancamentos_financeiros;


-- ============================================================
-- CONFERENCIA 1 - NENHUMA TABELA ABERTA
--
-- rls_ligada = false e tabela que qualquer um le e grava com a chave
-- publica. Ideal: nenhuma linha com false.
-- ============================================================
select c.relname as tabela,
       c.relrowsecurity as rls_ligada,
       (select count(*) from pg_policies p
         where p.schemaname = 'public' and p.tablename = c.relname) as politicas
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
  and not c.relrowsecurity
order by c.relname;


-- ============================================================
-- CONFERENCIA 2 - POLITICA QUE LIBERA DEMAIS
--
-- Varredura mais ampla que a da limpeza anterior, que olhava so o nome e o
-- texto da condicao. Esta olha tambem os PAPEIS da politica e o with_check,
-- que e onde mora a permissao de escrita. Ideal: nenhuma linha.
-- ============================================================
select tablename as tabela, policyname as politica, cmd as comando, roles as papeis,
  case
    when 'anon' = any(roles)                                 then 'ABERTA PARA ANONIMO'
    when btrim(coalesce(qual,''))       in ('true','(true)') then 'LEITURA SEM CONDICAO'
    when btrim(coalesce(with_check,'')) in ('true','(true)') then 'ESCRITA SEM CONDICAO'
    else 'CITA ANON'
  end as risco
from pg_policies
where schemaname = 'public'
  and ( 'anon' = any(roles)
     or btrim(coalesce(qual,''))       in ('true','(true)')
     or btrim(coalesce(with_check,'')) in ('true','(true)')
     or coalesce(qual,'') || coalesce(with_check,'') ilike '%anon%' )
order by tablename, policyname;


-- ============================================================
-- CONFERENCIA 3 - QUEM DA PECUARIA ESTAVA TRAVADO
--
-- Estas sao as pessoas que ate agora viam o financeiro da pecuaria zerado
-- e nao conseguiam registrar venda. Depois deste script, voltam a
-- funcionar. Vale pedir para uma delas conferir na tela.
-- ============================================================
select nome, usuario, papel,
       permissoes ->> 'pec_financeiro'   as pec_financeiro,
       permissoes ->> 'pec_resultados'   as pec_resultados,
       permissoes ->> 'matriz_financeiro' as matriz_financeiro
from profiles
where ativo
  and papel not in ('admin','proprietario')
  and (permissoes ? 'pec_financeiro' or permissoes ? 'pec_resultados')
  and coalesce(permissoes ->> 'matriz_financeiro', '') = ''
order by nome;


-- ============================================================
-- CONFERENCIA 4 - MES FORA DE FORMATO
--
-- Tem que voltar vazia. Qualquer linha aqui e um lancamento que existe na
-- tabela e nao aparece em relatorio nenhum.
-- ============================================================
select id, tipo, atividade, data, mes, descricao, valor
from lancamentos_financeiros
where mes is not null and mes !~ '^\d{4}-(0[1-9]|1[0-2])$'
order by id;
