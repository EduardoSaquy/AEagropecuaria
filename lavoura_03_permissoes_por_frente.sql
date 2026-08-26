-- ============================================================
-- SEPARAR A PERMISSAO DE CADASTROS POR FRENTE
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- RODE JUNTO COM A SUBIDA DOS HTMLs NOVOS. Entre um e outro existe uma
-- janela em que a tela velha de Centros de Custo do AE Lavoura da erro ao
-- salvar para quem nao for admin. Ninguem perde dado, so nao consegue
-- gravar nesse intervalo.
--
-- ------------------------------------------------------------
-- O PROBLEMA
--
-- Hoje uma unica permissao, 'cadastros', libera Fazendas, Culturas,
-- Safras, Talhoes e Centros de Custo de uma vez so - para as duas frentes
-- juntas. Nao existe como dar cadastros da Cana a alguem sem dar tambem os
-- dos Cereais. Com as duas operacoes em estados diferentes, isso deixa de
-- fazer sentido.
--
-- ------------------------------------------------------------
-- O QUE MUDA, E O QUE DE PROPOSITO NAO MUDA
--
-- LEITURA continua ampla. Todo app precisa ler fazenda, cultura, safra e
-- talhao para desenhar qualquer tela: o Matriz calcula hectare por
-- atividade, a Pecuaria usa fazenda, os dois apps de lavoura usam tudo.
--
-- ESCRITA passa a ser por frente. Quem tem cadastros de Cana cria e edita
-- cultura, safra e talhao DE CANA; quem tem dos Cereais, so os de cereais.
--
-- POR QUE ESSA ASSIMETRIA, E NAO SEPARACAO TOTAL TAMBEM NA LEITURA
--
-- Porque os dois erros falham de formas muito diferentes. Politica de
-- ESCRITA errada da erro na cara de quem tentou salvar: aparece na hora.
-- Politica de LEITURA errada faz a tela mostrar zero sem reclamar - o
-- Matriz mostraria 0 hectare de cana, o relatorio mostraria custo por
-- hectare infinito, e ninguem descobre ate desconfiar do numero.
--
-- Como eu ja te entreguei tres erros nesta migracao justamente por supor
-- em vez de conferir, escolhi o modo que falha barulhento. A separacao que
-- voce vai enxergar na tela e total: cada app so lista o que e dele. A
-- diferenca e que, se alguem chamar a API na mao, ainda consegue LER o
-- cadastro da outra frente. Se voce quiser fechar isso tambem, da para
-- fazer depois, num passo separado e testavel - nao no meio da separacao.
--
-- SEGURANCA: a permissao antiga 'cadastros' NAO e apagada. Ela fica no
-- cadastro dos usuarios durante a transicao e sai num script de limpeza,
-- depois que os apps novos estiverem rodando.
-- ============================================================

do $perm$
declare
  t           text;
  expr_frente text;
  regra       text;
  -- Quem precisa LER os cadastros compartilhados. Lista explicita, montada
  -- a partir das chaves que o diagnostico mostrou existirem de verdade.
  leitura_ampla constant text :=
    'is_admin()'
    || ' or tem_permissao(''cana_cadastros'',''visualizar'')'
    || ' or tem_permissao(''cereais_cadastros'',''visualizar'')'
    || ' or tem_permissao(''cadastros'',''visualizar'')'
    || ' or tem_permissao(''operacoes'',''visualizar'')'
    || ' or tem_permissao(''operacoes_graos'',''visualizar'')'
    || ' or tem_permissao(''matriz_painel'',''visualizar'')'
    || ' or tem_permissao(''matriz_resultados'',''visualizar'')'
    || ' or tem_permissao(''matriz_financeiro'',''visualizar'')'
    || ' or tem_permissao(''matriz_fazendas'',''visualizar'')'
    || ' or tem_permissao(''pec_financeiro'',''visualizar'')'
    || ' or tem_permissao(''pec_resultados'',''visualizar'')';
  n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- ---------- 1) DAR AS CHAVES NOVAS A QUEM JA TINHA A ANTIGA ----------
  -- Quem tinha cadastros passa a ter as duas frentes, no mesmo nivel. Nada
  -- e tirado de ninguem: e exatamente o acesso que a pessoa ja tem hoje,
  -- so escrito de outro jeito. Quem separa depois e voce, na tela.
  update profiles p
  set permissoes = coalesce(p.permissoes, '{}'::jsonb)
                   || jsonb_build_object('cana_cadastros',    p.permissoes ->> 'cadastros')
                   || jsonb_build_object('cereais_cadastros', p.permissoes ->> 'cadastros')
  where p.permissoes ? 'cadastros'
    and coalesce(p.permissoes ->> 'cadastros', '') <> ''
    and not (p.permissoes ? 'cana_cadastros' and p.permissoes ? 'cereais_cadastros');
  get diagnostics n = row_count;
  raise notice 'Usuarios que ganharam as chaves novas: %', n;

  -- ---------- 2) LEITURA AMPLA NOS CADASTROS COMPARTILHADOS ----------
  foreach t in array array['fazendas','culturas','safras','talhoes_areas','centros_custo']
  loop
    execute format('drop policy if exists %I on %I', 'select ' || t, t);
    execute format('drop policy if exists %I on %I', 'ler ' || t, t);
    execute format('create policy %I on %I for select using (%s)',
                   'ler ' || t, t, leitura_ampla);
  end loop;

  -- ---------- 3) ESCRITA POR FRENTE ----------
  -- CULTURAS: a frente esta na propria linha.
  -- SAFRAS e TALHOES: a frente vem da cultura vinculada.
  -- O else do case cobre cultura nula e frente 'pecuaria': nesses casos
  -- basta ter cadastros de qualquer uma das duas frentes, para que um
  -- talhao sem cultura nunca fique impossivel de editar.
  foreach t in array array['culturas','safras','talhoes_areas']
  loop
    -- de onde sai a frente da linha, em cada tabela
    if t = 'culturas' then
      expr_frente := 'frente';
    else
      expr_frente := '(select c.frente from culturas c where c.id = cultura_id)';
    end if;

    regra := 'is_admin() or case ' || expr_frente
          || ' when ''cana''  then tem_permissao(''cana_cadastros'',''editar'')'
          || ' when ''graos'' then tem_permissao(''cereais_cadastros'',''editar'')'
          || ' else tem_permissao(''cana_cadastros'',''editar'')'
          || '      or tem_permissao(''cereais_cadastros'',''editar'') end';

    execute format('drop policy if exists %I on %I', 'inserir ' || t, t);
    execute format('drop policy if exists %I on %I', 'atualizar ' || t, t);
    execute format('drop policy if exists %I on %I', 'excluir ' || t, t);
    execute format('drop policy if exists %I on %I', 'escrever ' || t, t);

    execute format('create policy %I on %I for insert with check (%s)',
                   'inserir ' || t, t, regra);
    execute format('create policy %I on %I for update using (%s) with check (%s)',
                   'atualizar ' || t, t, regra, regra);
    execute format('create policy %I on %I for delete using (%s)',
                   'excluir ' || t, t, regra);
  end loop;

  -- FAZENDAS: o cadastro foi centralizado no Matriz. Quem manda e o modulo
  -- do Matriz, nao mais 'cadastros'.
  drop policy if exists "inserir fazendas"   on fazendas;
  drop policy if exists "atualizar fazendas" on fazendas;
  drop policy if exists "excluir fazendas"   on fazendas;
  create policy "inserir fazendas"   on fazendas for insert
    with check (is_admin() or tem_permissao('matriz_fazendas','editar'));
  create policy "atualizar fazendas" on fazendas for update
    using      (is_admin() or tem_permissao('matriz_fazendas','editar'))
    with check (is_admin() or tem_permissao('matriz_fazendas','editar'));
  create policy "excluir fazendas"   on fazendas for delete
    using      (is_admin() or tem_permissao('matriz_fazendas','editar'));

  -- CENTROS DE CUSTO: cadastro financeiro. Vai junto com o Financeiro para
  -- o Matriz. Os 56 centros globais do plano de contas do Conag continuam
  -- sem frente, e isso esta certo: a atividade e campo do lancamento, nao
  -- do centro de custo.
  drop policy if exists "inserir centros_custo"   on centros_custo;
  drop policy if exists "atualizar centros_custo" on centros_custo;
  drop policy if exists "excluir centros_custo"   on centros_custo;
  create policy "inserir centros_custo"   on centros_custo for insert
    with check (is_admin() or tem_permissao('matriz_financeiro','editar'));
  create policy "atualizar centros_custo" on centros_custo for update
    using      (is_admin() or tem_permissao('matriz_financeiro','editar'))
    with check (is_admin() or tem_permissao('matriz_financeiro','editar'));
  create policy "excluir centros_custo"   on centros_custo for delete
    using      (is_admin() or tem_permissao('matriz_financeiro','editar'));
end
$perm$;


-- ============================================================
-- CONFERENCIA 1 - AS POLITICAS FICARAM COMO DEVIAM
--
-- Espero ver, nas cinco tabelas: uma politica de leitura ampla e as de
-- escrita ja com as chaves novas. Nenhuma linha pode continuar citando
-- 'cadastros' sozinho na escrita.
-- ============================================================
select tablename as tabela, policyname as politica, cmd as comando,
       left(coalesce(qual, '') || case when with_check is null then ''
                                       else ' [escrita] ' || with_check end, 160) as condicao
from pg_policies
where schemaname = 'public'
  and tablename in ('fazendas','culturas','safras','talhoes_areas','centros_custo')
order by tablename, cmd, policyname;


-- ============================================================
-- CONFERENCIA 2 - NINGUEM PERDEU ACESSO
--
-- Cada usuario que tinha 'cadastros' tem que aparecer com as duas chaves
-- novas no MESMO nivel. A coluna confere tem que dar OK.
-- ============================================================
select
  p.nome,
  p.papel,
  p.permissoes ->> 'cadastros'         as antiga,
  p.permissoes ->> 'cana_cadastros'    as cana,
  p.permissoes ->> 'cereais_cadastros' as cereais,
  case when p.permissoes ->> 'cadastros' is not distinct from p.permissoes ->> 'cana_cadastros'
        and p.permissoes ->> 'cadastros' is not distinct from p.permissoes ->> 'cereais_cadastros'
       then 'OK' else '*** DIFERENTE ***' end as confere
from profiles p
where p.permissoes ? 'cadastros'
order by p.nome;
