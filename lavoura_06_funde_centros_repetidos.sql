-- ============================================================
-- FUNDE OS CENTROS DE CUSTO REPETIDOS E TERMINA O lavoura_05
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O QUE ACONTECEU
--
-- O lavoura_05 fez duas coisas: promoveu os centros a globais (isso deu
-- certo) e tentou criar o indice unico sobre lower(nome) (isso falhou):
--
--   could not create unique index "uq_centro_custo_nome"
--   Key (lower(nome))=(custas contratuais) is duplicated.
--
-- O erro e meu. No lavoura_05 eu so tratei um tipo de duplicata: centro com
-- fazenda que tinha um global de mesmo nome. Nao tratei duplicata entre
-- centros que JA eram globais com grafia diferente - "CUSTAS CONTRATUAIS" e
-- "Custas contratuais" convivem sem problema no indice antigo, que comparava
-- o texto exato, e colidem no novo, que compara em minusculas.
--
-- Comparar em minusculas e o certo: e justamente essa a duplicata que
-- estraga o relatorio, porque as duas linhas parecem a mesma conta para
-- quem le e sao contas diferentes para o banco.
--
-- ------------------------------------------------------------
-- ESTADO DE AGORA
--
-- O lavoura_05 nao foi desfeito: os centros ja estao globais. Falta so a
-- fusao das grafias repetidas e o indice. Este script termina o servico e
-- pode rodar mesmo que o 05 tenha rodado parcialmente ou nem tenha rodado.
--
-- ------------------------------------------------------------
-- COMO ELE DECIDE QUAL FICA
--
-- Dentro de cada grupo de mesmo nome (ignorando maiusculas e acentos de
-- espaco), fica o de MENOR id - o mais antigo, que e o que tem mais chance
-- de ser o do plano de contas original. Todos os lancamentos dos outros
-- passam a apontar para ele antes de qualquer exclusao, e o grupo fica
-- ativo se qualquer um dos seus estava ativo.
--
-- NENHUM LANCAMENTO E APAGADO. So muda para qual centro ele aponta.
-- ============================================================

-- ------------------------------------------------------------
-- 1) O QUE ESTA REPETIDO (so leitura - rode antes se quiser conferir)
-- ------------------------------------------------------------
select
  lower(btrim(c.nome)) as nome_comparado,
  count(*)             as quantas_linhas,
  string_agg(c.id || ' = "' || c.nome || '"', ' | ' order by c.id) as linhas,
  sum((select count(*) from lancamentos_financeiros l where l.centro_custo_id = c.id)) as lancamentos_no_grupo
from centros_custo c
group by lower(btrim(c.nome))
having count(*) > 1
order by 1;


-- ------------------------------------------------------------
-- 2) A FUSAO
-- ------------------------------------------------------------
do $funde$
declare
  g record;
  id_fica bigint;
  n_movidos int;
  n_agora int;
  n_grupos int := 0;
  n_apagados int := 0;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- garante o que o lavoura_05 fazia, caso ele nao tenha chegado ao fim
  update centros_custo set fazenda_id = null where fazenda_id is not null;

  for g in
    select lower(btrim(nome)) as chave, min(id) as menor_id
    from centros_custo
    group by lower(btrim(nome))
    having count(*) > 1
  loop
    id_fica := g.menor_id;

    -- 2a) tudo que aponta para os irmaos passa a apontar para o que fica
    update lancamentos_financeiros set centro_custo_id = id_fica
     where centro_custo_id in (select id from centros_custo
                               where lower(btrim(nome)) = g.chave and id <> id_fica);
    get diagnostics n_movidos = row_count;

    -- as tabelas legadas ainda referenciam centros_custo; move junto para
    -- nao deixar referencia orfa em quem consultar o historico antigo
    update despesas_cana  set centro_custo_id = id_fica
     where centro_custo_id in (select id from centros_custo where lower(btrim(nome)) = g.chave and id <> id_fica);
    update despesas_graos set centro_custo_id = id_fica
     where centro_custo_id in (select id from centros_custo where lower(btrim(nome)) = g.chave and id <> id_fica);
    update receitas_cana  set centro_custo_id = id_fica
     where centro_custo_id in (select id from centros_custo where lower(btrim(nome)) = g.chave and id <> id_fica);
    update receitas_graos set centro_custo_id = id_fica
     where centro_custo_id in (select id from centros_custo where lower(btrim(nome)) = g.chave and id <> id_fica);

    -- 2b) se qualquer um do grupo estava ativo, o que fica continua ativo
    update centros_custo set ativo = true
     where id = id_fica
       and exists (select 1 from centros_custo o
                   where lower(btrim(o.nome)) = g.chave and coalesce(o.ativo, true));

    -- 2c) agora da para apagar os irmaos: nada mais aponta para eles
    delete from centros_custo
     where lower(btrim(nome)) = g.chave and id <> id_fica;
    get diagnostics n_agora = row_count;
    n_apagados := n_apagados + n_agora;

    n_grupos := n_grupos + 1;
    raise notice 'Fundido "%": ficou o id %, % lancamentos movidos', g.chave, id_fica, n_movidos;
  end loop;

  -- 2d) tira espaco sobrando do nome, que e outra forma da mesma duplicata
  update centros_custo set nome = btrim(nome) where nome <> btrim(nome);

  raise notice 'Grupos fundidos: % | centros apagados: %', n_grupos, n_apagados;
end
$funde$;


-- ------------------------------------------------------------
-- 3) AGORA O INDICE ENTRA
--
-- Compara em minusculas e sem espaco nas pontas: e a comparacao que
-- corresponde ao que a pessoa enxerga na tela.
-- ------------------------------------------------------------
drop index if exists uq_centro_custo_global;
drop index if exists uq_centro_custo_nome;
create unique index uq_centro_custo_nome on centros_custo (lower(btrim(nome)));

alter table centros_custo alter column fazenda_id set default null;


-- ============================================================
-- CONFERENCIA
--
-- Todas as tres primeiras colunas tem que dar 0.
-- ============================================================
select
  (select count(*) from centros_custo where fazenda_id is not null) as com_fazenda,
  (select count(*) from (
      select 1 from centros_custo group by lower(btrim(nome)) having count(*) > 1
   ) x) as nomes_repetidos,
  (select count(*) from lancamentos_financeiros l
    where not exists (select 1 from centros_custo c where c.id = l.centro_custo_id)
  ) as lancamentos_orfaos,
  (select count(*) from centros_custo) as total_de_centros,
  (select count(*) from lancamentos_financeiros) as total_de_lancamentos,
  (select coalesce(sum(valor), 0) from lancamentos_financeiros) as soma_dos_lancamentos;
