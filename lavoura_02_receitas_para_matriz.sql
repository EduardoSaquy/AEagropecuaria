-- ============================================================
-- MIGRAR AS RECEITAS DE LAVOURA PARA O MODELO UNICO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O FURO QUE ELE TAPA
--
-- Na migracao financeira eu levei despesas_cana e despesas_graos para
-- lancamentos_financeiros, mas nao levei receitas_cana nem receitas_graos.
-- O diagnostico confirmou:
--
--   receitas_cana    5 linhas   R$ 2.587.195,27   no modelo unico: 0
--   receitas_graos   0 linhas   R$ 0,00           no modelo unico: 0
--
-- Ou seja: R$ 2,58 milhoes de receita de cana existem so na tabela antiga.
-- O Financeiro do Matriz nao enxerga nenhum centavo disso, entao a cana
-- aparece la com R$ 2,45 milhoes de despesa e receita zero.
--
-- Isso tambem bloqueia a separacao dos apps: a unica tela que hoje lanca
-- receita de lavoura e a que ia deixar de existir.
--
-- ------------------------------------------------------------
-- COLUNAS NOVAS
--
-- receitas_cana guarda duas informacoes que nao tem onde entrar hoje:
-- toneladas entregues e safra. Sem elas nao da para calcular R$ por
-- tonelada, que e o numero que interessa numa venda para usina.
--
--   quantidade + unidade   quanto foi entregue e em que medida
--                          ('t' tonelada, 'sc' saca, '@' arroba, 'kg')
--   safra_id               a safra da entrega
--   cultura_id             qual cultura (usado pelos cereais)
--
-- SOBRE A COLUNA arrobas: ela ja existe e e usada pela Pecuaria. Nao vou
-- mexer nela agora. Fica redundante com quantidade/unidade ate a Pecuaria
-- ser convertida, e isso esta anotado de proposito - trocar o que ja
-- funciona no meio de uma migracao e como eu criei os erros anteriores.
--
-- SEGURANCA: nao apaga nada. receitas_cana e receitas_graos continuam
-- intactas. O script se recusa a rodar se ja houver receita de lavoura no
-- modelo unico, para nao duplicar.
-- ============================================================

-- ------------------------------------------------------------
-- 1) COLUNAS NOVAS (nao destrutivo)
-- ------------------------------------------------------------
alter table lancamentos_financeiros add column if not exists quantidade numeric;
alter table lancamentos_financeiros add column if not exists unidade    text;
alter table lancamentos_financeiros add column if not exists safra_id   bigint references safras(id);
alter table lancamentos_financeiros add column if not exists cultura_id bigint references culturas(id);

alter table lancamentos_financeiros drop constraint if exists unidade_valida;
alter table lancamentos_financeiros add constraint unidade_valida check (
  unidade is null or unidade in ('t', 'sc', '@', 'kg')
);


-- ------------------------------------------------------------
-- 2) A MIGRACAO
-- ------------------------------------------------------------
do $recmig$
declare
  id_vendas bigint;
  n_cana int; n_graos int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  if exists (select 1 from lancamentos_financeiros
             where tipo = 'receita' and atividade in ('cana', 'graos')) then
    raise exception
      'Ja existe receita de lavoura no modelo unico (% linhas). Rodar de novo duplicaria a receita.',
      (select count(*) from lancamentos_financeiros
        where tipo = 'receita' and atividade in ('cana', 'graos'));
  end if;

  -- Centro de custo de destino quando a receita nao tem um proprio.
  -- 'Vendas' foi criado na migracao financeira anterior.
  select id into id_vendas from centros_custo where fazenda_id is null and nome = 'Vendas';
  if id_vendas is null then
    insert into centros_custo (fazenda_id, nome, frente, ativo)
    values (null, 'Vendas', 'geral', true) returning id into id_vendas;
  end if;

  -- ---------- RECEITA DE CANA ----------
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     observacao, talhao_id, safra_id, quantidade, unidade)
  select
    'receita', 'cana', r.fazenda_id,
    coalesce(r.centro_custo_id, id_vendas),
    -- receitas_cana nao tem campo de descricao. O Matriz ja mostrava estas
    -- linhas como "Venda de cana"; mantenho o mesmo texto para o historico
    -- nao mudar de nome na tela.
    'Venda de cana',
    r.valor_total, r.data, to_char(r.data, 'YYYY-MM'),
    nullif(trim(coalesce(r.observacao, '')), ''),
    r.talhao_id, r.safra_id,
    nullif(r.toneladas, 0), case when coalesce(r.toneladas, 0) > 0 then 't' end
  from receitas_cana r
  where coalesce(r.valor_total, 0) > 0 and r.data is not null;
  get diagnostics n_cana = row_count;

  -- ---------- RECEITA DE CEREAIS ----------
  -- Hoje sao 0 linhas. O bloco existe para quando houver.
  insert into lancamentos_financeiros
    (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor, data, mes,
     observacao, talhao_id, safra_id, cultura_id, quantidade, unidade)
  select
    'receita', 'graos', r.fazenda_id,
    coalesce(r.centro_custo_id, id_vendas),
    coalesce(
      'Venda de ' || (select lower(c.nome) from culturas c where c.id = r.cultura_id),
      'Venda de graos'
    ),
    r.valor_total, r.data, to_char(r.data, 'YYYY-MM'),
    nullif(trim(coalesce(r.observacao, '')), ''),
    r.talhao_id, r.safra_id, r.cultura_id,
    nullif(r.sacas, 0), case when coalesce(r.sacas, 0) > 0 then 'sc' end
  from receitas_graos r
  where coalesce(r.valor_total, 0) > 0 and r.data is not null;
  get diagnostics n_graos = row_count;

  raise notice 'Receitas migradas - cana: % | cereais: %', n_cana, n_graos;
end
$recmig$;


-- ============================================================
-- CONFERENCIA
--
-- A coluna confere tem que dar OK nas duas linhas.
-- ============================================================
select 'receita cana' as origem,
       (select count(*) from receitas_cana where coalesce(valor_total,0) > 0 and data is not null) as linhas_legado,
       (select count(*) from lancamentos_financeiros where tipo='receita' and atividade='cana') as linhas_novo,
       (select coalesce(sum(valor_total),0) from receitas_cana where coalesce(valor_total,0) > 0 and data is not null) as total_legado,
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='cana') as total_novo,
       case when (select coalesce(sum(valor_total),0) from receitas_cana where coalesce(valor_total,0) > 0 and data is not null)
               = (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='cana')
            then 'OK' else '*** DIFERENTE ***' end as confere
union all
select 'receita cereais',
       (select count(*) from receitas_graos where coalesce(valor_total,0) > 0 and data is not null),
       (select count(*) from lancamentos_financeiros where tipo='receita' and atividade='graos'),
       (select coalesce(sum(valor_total),0) from receitas_graos where coalesce(valor_total,0) > 0 and data is not null),
       (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='graos'),
       case when (select coalesce(sum(valor_total),0) from receitas_graos where coalesce(valor_total,0) > 0 and data is not null)
               = (select coalesce(sum(valor),0) from lancamentos_financeiros where tipo='receita' and atividade='graos')
            then 'OK' else '*** DIFERENTE ***' end;
