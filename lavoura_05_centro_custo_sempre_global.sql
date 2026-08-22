-- ============================================================
-- CENTRO DE CUSTO PASSA A SER SEMPRE GLOBAL
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O ERRO
--
-- Centro de custo e plano de contas: a mesma conta vale para toda fazenda e
-- para toda atividade. Quem diz de onde o gasto e sao os campos fazenda e
-- atividade DO LANCAMENTO, nao o centro.
--
-- Eu montei a tela nova de Centros de Custo com um seletor de fazenda,
-- copiando a estrutura antiga da tabela em vez de olhar para o que o
-- cadastro significa. Isso permite criar "MANUTENCAO DE VEICULOS" tres
-- vezes, uma por fazenda, e o relatorio por centro de custo passa a mostrar
-- tres linhas onde deveria haver uma.
--
-- A coluna fazenda_id vem do desenho antigo, de quando cada app tinha seu
-- proprio banco e centros_custo exigia fazenda. Os 56 centros do plano de
-- contas do Conag ja sao globais; os que tem fazenda sao resquicio.
--
-- ------------------------------------------------------------
-- O QUE ESTE SCRIPT FAZ
--
-- 1. Mostra o que sera mudado, ANTES de mudar.
-- 2. Onde ja existe um centro global com o mesmo nome, aponta os
--    lancamentos do centro por fazenda para o global e apaga o duplicado.
-- 3. O que sobrar vira global.
-- 4. Impede que apareca de novo: fazenda_id ganha um default nulo e a
--    unicidade por nome passa a valer para todos.
--
-- NENHUM LANCAMENTO E APAGADO. So muda para qual centro ele aponta.
-- ============================================================

-- ------------------------------------------------------------
-- 1) O QUE EXISTE HOJE (so leitura, rode antes se quiser conferir)
-- ------------------------------------------------------------
select
  c.id, c.nome,
  (select nome from fazendas f where f.id = c.fazenda_id) as fazenda,
  (select count(*) from lancamentos_financeiros l where l.centro_custo_id = c.id) as lancamentos,
  case when exists (
        select 1 from centros_custo g
        where g.fazenda_id is null and lower(g.nome) = lower(c.nome)
       ) then 'ja existe um global com este nome - sera fundido'
       else 'vira global' end as destino
from centros_custo c
where c.fazenda_id is not null
order by c.nome;


-- ------------------------------------------------------------
-- 2) A CORRECAO
-- ------------------------------------------------------------
do $global$
declare
  n_fundidos int := 0;
  n_movidos  int := 0;
  n_promovidos int := 0;
  r record;
  id_global bigint;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  -- ---------- 2a) FUNDE OS QUE JA TEM UM GLOBAL DE MESMO NOME ----------
  for r in
    select c.id, c.nome from centros_custo c
    where c.fazenda_id is not null
      and exists (select 1 from centros_custo g
                  where g.fazenda_id is null and lower(g.nome) = lower(c.nome))
  loop
    select g.id into id_global from centros_custo g
     where g.fazenda_id is null and lower(g.nome) = lower(r.nome) limit 1;

    update lancamentos_financeiros
       set centro_custo_id = id_global
     where centro_custo_id = r.id;
    get diagnostics n_movidos = row_count;

    -- as tabelas legadas ainda apontam para centros_custo; move junto para
    -- nao deixar referencia orfa caso alguem consulte o historico antigo
    update despesas_cana  set centro_custo_id = id_global where centro_custo_id = r.id;
    update despesas_graos set centro_custo_id = id_global where centro_custo_id = r.id;
    update receitas_cana  set centro_custo_id = id_global where centro_custo_id = r.id;
    update receitas_graos set centro_custo_id = id_global where centro_custo_id = r.id;

    delete from centros_custo where id = r.id;
    n_fundidos := n_fundidos + 1;
    raise notice 'Fundido: % (% lancamentos movidos)', r.nome, n_movidos;
  end loop;

  -- ---------- 2b) O RESTO VIRA GLOBAL ----------
  update centros_custo set fazenda_id = null where fazenda_id is not null;
  get diagnostics n_promovidos = row_count;

  raise notice 'Centros fundidos: % | centros promovidos a global: %',
    n_fundidos, n_promovidos;
end
$global$;


-- ------------------------------------------------------------
-- 3) IMPEDIR QUE VOLTE
--
-- O indice unico antigo so valia para os globais (era parcial). Como agora
-- todo centro e global, ele passa a valer para a tabela inteira - e um
-- segundo "MANUTENCAO DE VEICULOS" e recusado pelo banco, nao so pela tela.
-- ------------------------------------------------------------
alter table centros_custo alter column fazenda_id set default null;

drop index if exists uq_centro_custo_global;
create unique index if not exists uq_centro_custo_nome
  on centros_custo (lower(nome));


-- ============================================================
-- CONFERENCIA
--
-- centros_com_fazenda tem que ser 0.
-- nomes_repetidos tem que ser 0.
-- lancamentos_orfaos tem que ser 0 (nenhum lancamento perdeu o centro).
-- ============================================================
select
  (select count(*) from centros_custo where fazenda_id is not null) as centros_com_fazenda,
  (select count(*) from (
      select lower(nome) from centros_custo group by lower(nome) having count(*) > 1
   ) x) as nomes_repetidos,
  (select count(*) from lancamentos_financeiros l
    where not exists (select 1 from centros_custo c where c.id = l.centro_custo_id)
  ) as lancamentos_orfaos,
  (select count(*) from centros_custo) as total_de_centros;
