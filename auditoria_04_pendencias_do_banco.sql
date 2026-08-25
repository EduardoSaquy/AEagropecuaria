-- ============================================================
-- PENDENCIAS DO BANCO QUE SOBRARAM DA AUDITORIA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- Este script CONSERTA o que da para consertar sem risco e DIAGNOSTICA o
-- resto. Onde ele so diagnostica, esta dito no proprio resultado.
--
-- ------------------------------------------------------------
-- 1. COLUNA OBRIGATORIA QUE O APP NAO PREENCHE
--
-- Os arquivos de schema do repositorio declaram centros_custo.frente como
-- NOT NULL, e o app grava nulo - porque frente deixou de fazer sentido
-- depois da unificacao: quem diz a que atividade o gasto pertence e o
-- campo atividade do LANCAMENTO. Os 56 centros do plano de contas do Conag
-- ja estao com frente nula.
--
-- Se a restricao ainda existir no banco, criar centro de custo novo estoura
-- hoje. Como o script le o estado real antes de mexer, ele so age se o
-- problema existir de verdade.
--
-- O mesmo vale para reproducao_custos.item, que o app parou de escrever.
--
-- ------------------------------------------------------------
-- 2. UNIQUE QUE O upsert EXIGE
--
-- O Matriz grava area por atividade e alocacao de funcionario com
-- upsert(..., {onConflict:'fazenda_id,atividade'}). Isso exige uma
-- restricao UNIQUE exatamente nesse par. Sem ela, o upsert falha em tempo
-- de execucao com "there is no unique or exclusion constraint matching the
-- ON CONFLICT specification" - e so na hora de EDITAR uma fazenda, nao ao
-- criar, o que torna o erro dificil de associar a causa.
-- ============================================================

do $pend$
declare
  n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- ---------- 1) NOT NULL em coluna que o app nao preenche mais ----------
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='centros_custo'
               and column_name='frente' and is_nullable='NO') then
    alter table centros_custo alter column frente drop not null;
    raise notice 'centros_custo.frente: NOT NULL removido (o app grava nulo de proposito).';
  else
    raise notice 'centros_custo.frente: ja aceita nulo, nada a fazer.';
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='reproducao_custos'
               and column_name='item' and is_nullable='NO') then
    alter table reproducao_custos alter column item drop not null;
    raise notice 'reproducao_custos.item: NOT NULL removido (o app parou de escrever).';
  else
    raise notice 'reproducao_custos.item: ja aceita nulo ou nao existe, nada a fazer.';
  end if;

  -- ---------- 2) UNIQUE que o upsert do Matriz exige ----------
  if to_regclass('public.fazenda_atividades') is not null
     and not exists (
       select 1 from pg_constraint c
       where c.conrelid = 'fazenda_atividades'::regclass and c.contype = 'u'
         and (select array_agg(a.attname::text order by a.attname)
              from unnest(c.conkey) k(n)
              join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.n)
             = array['atividade','fazenda_id']) then
    -- limpa duplicata antes, senao a restricao nao entra
    delete from fazenda_atividades a using fazenda_atividades b
     where a.id > b.id and a.fazenda_id = b.fazenda_id and a.atividade = b.atividade;
    get diagnostics n = row_count;
    alter table fazenda_atividades
      add constraint uq_fazenda_atividade unique (fazenda_id, atividade);
    raise notice 'fazenda_atividades: UNIQUE(fazenda_id, atividade) criada (% duplicata removida).', n;
  end if;

  if to_regclass('public.funcionario_atividades') is not null
     and not exists (
       select 1 from pg_constraint c
       where c.conrelid = 'funcionario_atividades'::regclass and c.contype = 'u'
         and (select array_agg(a.attname::text order by a.attname)
              from unnest(c.conkey) k(n)
              join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.n)
             = array['atividade','funcionario_id']) then
    delete from funcionario_atividades a using funcionario_atividades b
     where a.id > b.id and a.funcionario_id = b.funcionario_id and a.atividade = b.atividade;
    get diagnostics n = row_count;
    alter table funcionario_atividades
      add constraint uq_funcionario_atividade unique (funcionario_id, atividade);
    raise notice 'funcionario_atividades: UNIQUE(funcionario_id, atividade) criada (% duplicata removida).', n;
  end if;
end
$pend$;


-- ============================================================
-- DIAGNOSTICO - AS TABELAS QUE O REPOSITORIO NAO DESCREVE
--
-- funcionarios, funcionario_atividades, fazenda_atividades e apps sao
-- usadas pelos apps e nenhum arquivo .sql da pasta as cria. Sem isso nao da
-- para afirmar que tem RLS, politica de cada comando ou chave estrangeira.
--
-- COMO LER: rls_ligada tem que ser true e politicas maior que zero. Onde
-- ao_apagar_o_pai vier "bloqueia" numa coluna opcional, apagar o pai trava
-- sem explicacao na tela.
-- ============================================================
select c.relname as tabela,
       c.relrowsecurity as rls_ligada,
       (select count(*) from pg_policies p
         where p.schemaname='public' and p.tablename=c.relname) as politicas,
       coalesce((select string_agg(
           a.attname || ' -> ' || con.confrelid::regclass::text || ' (' ||
           case con.confdeltype when 'n' then 'SET NULL' when 'c' then 'CASCADE'
                                else 'bloqueia' end || ')', ', ')
         from pg_constraint con
         join lateral unnest(con.conkey) k(n) on true
         join pg_attribute a on a.attrelid=con.conrelid and a.attnum=k.n
         where con.contype='f' and con.conrelid=c.oid), 'nenhuma') as chaves_estrangeiras
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
  and c.relname in ('funcionarios','funcionario_atividades','fazenda_atividades','apps')
order by c.relname;


-- ============================================================
-- DIAGNOSTICO - COLUNA SENSIVEL EM QUALQUER TABELA
--
-- A regra do projeto: CPF, salario e Pix nunca entram em tabela lida pela
-- chave publica. Tem que voltar VAZIA.
-- ============================================================
select c.table_name as tabela, c.column_name as coluna,
       (select count(*) from pg_policies p
         where p.schemaname='public' and p.tablename=c.table_name
           and p.cmd in ('SELECT','ALL')) as politicas_de_leitura
from information_schema.columns c
where c.table_schema='public'
  and c.column_name ~* '(^|_)(cpf|rg|pix|salario|salarios|conta_bancaria|agencia)($|_)'
order by 1, 2;


-- ============================================================
-- O SCHEMA REAL, PARA GUARDAR NO REPOSITORIO
--
-- Os arquivos *_schema.sql da pasta estao desatualizados e ja induziram ao
-- erro quatro vezes nesta sequencia de trabalho - valores de CHECK errados,
-- chave estrangeira que nao aparecia, coluna que dizia NOT NULL e nao era.
--
-- Este resultado e o estado REAL. Salve como schema_real.txt no
-- repositorio e regere depois de cada migracao: acaba com essa classe de
-- erro inteira.
-- ============================================================
select
  c.relname || '.' || a.attname
    || ' ' || format_type(a.atttypid, a.atttypmod)
    || case when a.attnotnull then ' NOT NULL' else '' end
    || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '') as coluna
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
where c.relkind = 'r'
order by c.relname, a.attnum;
