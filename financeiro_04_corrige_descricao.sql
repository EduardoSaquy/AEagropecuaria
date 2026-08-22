-- ============================================================
-- CORRIGE A DESCRICAO DAS DESPESAS MIGRADAS DA PECUARIA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O ERRO QUE ELE CONSERTA
--
-- A Pecuaria evita contar despesa em dobro agrupando por
-- nome + centro de custo + atividades, e dentro do grupo o lancamento com
-- mes substitui o recorrente. So conta um dos dois.
--
-- Na migracao eu juntei nome e descricao detalhada num campo so:
--
--   cf.nome || ' - ' || cf.descricao
--
-- Com isso "Mao de obra" (recorrente) e "Mao de obra - folha de julho" (do
-- mes) viraram nomes diferentes. Pararam de agrupar, entao as duas passaram
-- a ser contadas em vez de uma substituir a outra, e o custo subiu.
--
-- A correcao devolve a descricao ao nome original e joga o detalhe para a
-- observacao, que e onde ele deveria ter ficado desde o inicio.
--
-- SEGURANCA: so mexe em linha cujo nome reconstruido realmente existe em
-- custos_fixos, que continua intacta. Se o nome nao bater, a linha nao e
-- tocada. Nenhum valor em reais e alterado.
-- ============================================================

do $corrige$
declare
  n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  update lancamentos_financeiros l
  set descricao  = novo.nome,
      observacao = novo.obs
  from (
    select
      l2.id,
      split_part(l2.descricao, ' — ', 1) as nome,
      nullif(trim(
        coalesce(l2.observacao, '')
        || case when coalesce(l2.observacao, '') = '' then '' else ' | ' end
        || substr(l2.descricao, length(split_part(l2.descricao, ' — ', 1)) + 4)
      ), '') as obs
    from lancamentos_financeiros l2
    where l2.tipo = 'despesa'
      and l2.atividade = 'pecuaria'
      and position(' — ' in l2.descricao) > 0
      -- so corrige se o nome reconstruido existir mesmo na origem
      and exists (
        select 1 from custos_fixos cf
        where cf.nome = split_part(l2.descricao, ' — ', 1)
      )
  ) novo
  where l.id = novo.id;

  get diagnostics n = row_count;
  raise notice 'Linhas corrigidas: %', n;
end
$corrige$;


-- ============================================================
-- CONFERENCIA: o total do mes tem que voltar a bater
--
-- Reproduz em SQL a mesma regra do app (agrupa por nome + centro de custo +
-- atividades; o lancamento com mes substitui o recorrente) nas duas
-- tabelas, e compara.
--
-- A coluna confere tem que dar OK. Se der DIFERENTE, me mande o resultado.
-- ============================================================
with mes_alvo as (select to_char(current_date, 'YYYY-MM') as m),

-- lado antigo: custos_fixos, como a Pecuaria calculava antes da migracao
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

-- lado novo: lancamentos_financeiros, como a Pecuaria calcula agora
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
  (select m from mes_alvo)                                        as mes,
  (select count(*) from antigo_vigente)                           as linhas_antes,
  (select count(*) from novo_vigente)                             as linhas_agora,
  (select coalesce(sum(valor_mensal), 0) from antigo_vigente)     as total_antes,
  (select coalesce(sum(valor), 0) from novo_vigente)              as total_agora,
  case when (select coalesce(sum(valor_mensal), 0) from antigo_vigente)
          = (select coalesce(sum(valor), 0) from novo_vigente)
       then 'OK' else '*** DIFERENTE ***' end                     as confere;
