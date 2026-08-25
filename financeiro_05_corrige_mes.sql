-- ============================================================
-- CORRIGE O MES DAS DESPESAS MIGRADAS DA PECUARIA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O ERRO
--
-- Em custos_fixos, mes e data sao colunas INDEPENDENTES. Os lancamentos
-- historicos (vindos do Conag) tem mes preenchido e data vazia: sao
-- competencias mensais, sem dia especifico.
--
-- Na migracao eu derivei o mes a partir da data. Como esses historicos nao
-- tem data, o mes virou nulo neles. E no modelo novo mes nulo significa
-- RECORRENTE, isto e, vale para todo mes. Centenas de despesas de anos
-- anteriores passaram a ser contadas como despesa fixa de qualquer mes.
--
-- Foi isso que levou o custo do mes de R$ 43.928,73 para mais de um milhao.
--
-- Alem disso, a restricao que eu criei na tabela (mes so pode existir se
-- data existir) PROIBE guardar o dado do jeito certo. Ela partia de uma
-- suposicao errada minha sobre o significado dos dois campos.
--
-- ------------------------------------------------------------
-- O QUE ESTE SCRIPT FAZ
--
-- 1. Troca a restricao por uma correta: quando existe data, o mes tem que
--    bater com ela; sem data, o mes pode estar preenchido (competencia
--    mensal) ou vazio (recorrente de verdade).
--
-- 2. Refaz a migracao das despesas da pecuaria, preservando o mes original
--    e mantendo o nome separado do detalhe.
--
-- SEGURANCA: custos_fixos continua intacta e e dela que os dados sao
-- relidos. O script recusa rodar se o numero de despesas de pecuaria no
-- modelo novo nao bater com a origem, porque isso indicaria lancamento
-- feito a mao depois da migracao, que seria apagado junto.
-- ============================================================

do $corrigemes$
declare
  n_origem  int;
  n_atual   int;
  id_nao_classificado bigint;
  n_novo    int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  select count(*) into n_origem from custos_fixos where coalesce(valor_mensal, 0) > 0;
  select count(*) into n_atual  from lancamentos_financeiros
    where tipo = 'despesa' and atividade = 'pecuaria';

  if n_atual <> n_origem then
    raise exception
      'Origem tem % despesas e o modelo novo tem %. Como nao batem, pode haver lancamento feito a mao depois da migracao, que seria apagado. Me avise antes de seguir.',
      n_origem, n_atual;
  end if;

  -- ---------- 1) RESTRICAO CORRETA ----------
  alter table lancamentos_financeiros drop constraint if exists mes_bate_com_data;
  alter table lancamentos_financeiros add constraint mes_bate_com_data check (
    -- com data, o mes tem que ser o dela; sem data, o mes e livre:
    -- preenchido significa competencia mensal, vazio significa recorrente
    data is null or mes = to_char(data, 'YYYY-MM')
  );

  -- ---------- 2) REFAZ AS DESPESAS DA PECUARIA ----------
  select id into id_nao_classificado
    from centros_custo where fazenda_id is null and nome = 'Nao classificado';

  delete from lancamentos_financeiros
   where tipo = 'despesa' and atividade = 'pecuaria';

  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     fornecedor, observacao, areas)
  select
    'despesa', 'pecuaria', null,
    coalesce(
      (select c.id from centros_custo c
        where c.fazenda_id is null and lower(c.nome) = lower(trim(cf.categoria)) limit 1),
      id_nao_classificado
    ),
    -- so o nome: o detalhe vai para observacao. Juntar os dois quebraria o
    -- agrupamento que impede contar a mesma conta duas vezes no mes.
    cf.nome,
    cf.valor_mensal,
    cf.data,
    -- o mes vem do proprio campo mes, como na origem. Se ele estiver vazio
    -- mas houver data, deriva da data; se os dois estiverem vazios, e
    -- recorrente de verdade.
    coalesce(cf.mes, case when cf.data is not null then to_char(cf.data, 'YYYY-MM') end),
    nullif(trim(coalesce(cf.fornecedor, '')), ''),
    nullif(trim(
      coalesce(cf.observacao, '')
      || case when coalesce(trim(cf.descricao), '') = '' then ''
              else case when coalesce(trim(cf.observacao), '') = '' then '' else ' | ' end
                   || trim(cf.descricao) end
    ), ''),
    coalesce(cf.areas, '{}')
  from custos_fixos cf
  where coalesce(cf.valor_mensal, 0) > 0;

  get diagnostics n_novo = row_count;
  raise notice 'Despesas da pecuaria refeitas: %', n_novo;
end
$corrigemes$;


-- ============================================================
-- CONFERENCIA
--
-- Reproduz a regra do app nas duas tabelas e compara o total do mes atual.
-- A coluna confere tem que dar OK, e total_agora tem que voltar para perto
-- de R$ 43.928,73.
-- ============================================================
with mes_alvo as (select to_char(current_date, 'YYYY-MM') as m),

antigo as (
  select
    cf.nome || '||' || coalesce(cf.categoria, '') || '||'
      || array_to_string(array(select unnest(coalesce(cf.areas, '{}')) order by 1), ',') as chave,
    cf.mes, cf.valor_mensal
  from custos_fixos cf
  where coalesce(cf.valor_mensal, 0) > 0
),
antigo_vigente as (
  select a.* from antigo a, mes_alvo t
  where a.mes = t.m
     or (a.mes is null and not exists (
           select 1 from antigo b, mes_alvo t2 where b.chave = a.chave and b.mes = t2.m))
),

novo as (
  select
    l.descricao || '||' || coalesce(c.nome, '') || '||'
      || array_to_string(array(select unnest(coalesce(l.areas, '{}')) order by 1), ',') as chave,
    l.mes, l.valor
  from lancamentos_financeiros l
  join centros_custo c on c.id = l.centro_custo_id
  where l.tipo = 'despesa' and l.atividade = 'pecuaria'
),
novo_vigente as (
  select n.* from novo n, mes_alvo t
  where n.mes = t.m
     or (n.mes is null and not exists (
           select 1 from novo b, mes_alvo t2 where b.chave = n.chave and b.mes = t2.m))
)

select
  (select m from mes_alvo)                                    as mes,
  (select count(*) from antigo_vigente)                       as linhas_antes,
  (select count(*) from novo_vigente)                         as linhas_agora,
  (select coalesce(sum(valor_mensal), 0) from antigo_vigente) as total_antes,
  (select coalesce(sum(valor), 0) from novo_vigente)          as total_agora,
  case when (select coalesce(sum(valor_mensal), 0) from antigo_vigente)
          = (select coalesce(sum(valor), 0) from novo_vigente)
       then 'OK' else '*** DIFERENTE ***' end                 as confere;
