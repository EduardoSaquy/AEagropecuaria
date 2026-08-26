-- ============================================================
-- FUNDE OS PARES QUE SAO A MESMA CONTA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- O QUE ESTA SENDO CORRIGIDO
--
-- Dois planos de contas conviveram no mesmo banco: o do AE Cana (nomes
-- curtos) e o do Conag (MAIUSCULAS). A fusao anterior so juntou nomes
-- IDENTICOS ignorando maiusculas, entao pares como "Combustiveis" e
-- "COMBUSTIVEIS DA OPERACAO AGROPECUARIA" continuaram separados - o mesmo
-- gasto dividido em duas linhas do relatorio.
--
-- SETE pares foram confirmados como a mesma conta. Fica o nome do Conag,
-- que e o que o contador ve.
--
-- IMPORTANTE: o total POR GRUPO nao muda. As duas metades de cada par ja
-- caem no mesmo grupo do plano de contas, entao o relatorio agrupado ja
-- somava certo. Esta fusao arruma a lista de centros, nao o numero.
--
-- ------------------------------------------------------------
-- O QUE NAO ESTA SENDO FUNDIDO, E POR QUE
--
-- O detector casou por pedaco de texto e trouxe seis pares que NAO sao a
-- mesma conta:
--
--   DEDUCOES DA RECEITA BRUTA x Vendas       deducao nao e venda
--   PRODUCAO AGROPECUARIA x VENDAS INTRAEMPRESA   externa nao e interna
--   DESPESAS FINANCEIRAS x OUTRAS DESPESAS FINANCEIRAS   distincao real
--   ...- ADMINISTRACAO x versao da pecuaria (veiculos, instalacoes)
--       separados de proposito: um e escritorio, outro e operacao, e
--       ficaram em grupos diferentes no centros_02
--
-- ------------------------------------------------------------
-- TRAVA DE SEGURANCA
--
-- O script CONFERE, par a par, se os dois lados estao no mesmo grupo do
-- plano de contas. Se algum estiver em grupo diferente, ele PARA sem
-- gravar nada: fundir ali mudaria o relatorio, e isso e decisao sua, nao
-- consequencia escondida de uma limpeza de nomes.
--
-- Nenhum lancamento e apagado. So muda para qual centro ele aponta.
-- ============================================================

-- ------------------------------------------------------------
-- 1) O QUE SERA FEITO (so leitura)
-- ------------------------------------------------------------
with pares(fica, sai) as (values
  ('COMBUSTÍVEIS DA OPERAÇÃO AGROPECUÁRIA',        'Combustíveis'),
  ('SERVIÇOS PROFISSIONAIS',                       'Serviços Profissionais (Segurança/Cartório/Contabilidade)'),
  ('ENERGIA ELÉTRICA DE INFRAESTRUTURA OPERACIONAL','Energia Elétrica'),
  ('DESPESAS COM A CASA-SEDE',                     'Casa-Sede'),
  ('DESPESAS COM INSTALAÇÕES - ADMINISTRAÇÃO',     'Instalações - Administração'),
  ('DESPESAS COM VEÍCULOS - ADMINISTRAÇÃO',        'Veículos - Administração'),
  ('CONTRATAÇÃO DE SEGUROS',                       'Seguros')
)
select
  p.fica as nome_que_fica,
  p.sai  as nome_que_sai,
  (select coalesce(sum(l.valor),0) from lancamentos_financeiros l
    join centros_custo c on c.id=l.centro_custo_id where lower(btrim(c.nome))=lower(btrim(p.fica))) as total_que_fica,
  (select coalesce(sum(l.valor),0) from lancamentos_financeiros l
    join centros_custo c on c.id=l.centro_custo_id where lower(btrim(c.nome))=lower(btrim(p.sai)))  as total_que_migra,
  coalesce((select c.subcategoria from centros_custo c where lower(btrim(c.nome))=lower(btrim(p.fica))), '(sem grupo)') as grupo_do_que_fica,
  coalesce((select c.subcategoria from centros_custo c where lower(btrim(c.nome))=lower(btrim(p.sai))),  '(sem grupo)') as grupo_do_que_sai
from pares p
order by 4 desc;


-- ------------------------------------------------------------
-- 2) A FUSAO
-- ------------------------------------------------------------
do $funde2$
declare
  r record;
  id_fica bigint; id_sai bigint;
  g_fica text; g_sai text;
  n int; n_pares int := 0; n_lanc int := 0;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  for r in
    select * from (values
      ('COMBUSTÍVEIS DA OPERAÇÃO AGROPECUÁRIA',        'Combustíveis'),
      ('SERVIÇOS PROFISSIONAIS',                       'Serviços Profissionais (Segurança/Cartório/Contabilidade)'),
      ('ENERGIA ELÉTRICA DE INFRAESTRUTURA OPERACIONAL','Energia Elétrica'),
      ('DESPESAS COM A CASA-SEDE',                     'Casa-Sede'),
      ('DESPESAS COM INSTALAÇÕES - ADMINISTRAÇÃO',     'Instalações - Administração'),
      ('DESPESAS COM VEÍCULOS - ADMINISTRAÇÃO',        'Veículos - Administração'),
      ('CONTRATAÇÃO DE SEGUROS',                       'Seguros')
    ) as t(fica, sai)
  loop
    select id, subcategoria into id_fica, g_fica from centros_custo where lower(btrim(nome)) = lower(btrim(r.fica));
    select id, subcategoria into id_sai,  g_sai  from centros_custo where lower(btrim(nome)) = lower(btrim(r.sai));

    -- par ja fundido numa rodada anterior, ou nome que nao existe: segue
    if id_fica is null or id_sai is null then continue; end if;

    -- A TRAVA: grupos diferentes significa que fundir mudaria o relatorio
    if coalesce(btrim(g_fica),'') <> coalesce(btrim(g_sai),'') then
      raise exception
        'PAROU sem gravar nada. "%" esta em "%" e "%" esta em "%". Fundir juntaria dois grupos diferentes do plano de contas, e isso muda o relatorio - e decisao sua, nao consequencia de uma limpeza de nomes. Acerte o grupo dos dois na tela de Centros de Custo e rode de novo.',
        r.fica, coalesce(g_fica,'(sem grupo)'), r.sai, coalesce(g_sai,'(sem grupo)');
    end if;

    update lancamentos_financeiros set centro_custo_id = id_fica where centro_custo_id = id_sai;
    get diagnostics n = row_count; n_lanc := n_lanc + n;

    update despesas_cana  set centro_custo_id = id_fica where centro_custo_id = id_sai;
    update despesas_graos set centro_custo_id = id_fica where centro_custo_id = id_sai;
    update receitas_cana  set centro_custo_id = id_fica where centro_custo_id = id_sai;
    update receitas_graos set centro_custo_id = id_fica where centro_custo_id = id_sai;

    -- se qualquer um dos dois estava ativo, o que fica continua ativo
    update centros_custo set ativo = true
     where id = id_fica and exists (select 1 from centros_custo o where o.id in (id_fica, id_sai) and coalesce(o.ativo, true));

    delete from centros_custo where id = id_sai;
    n_pares := n_pares + 1;
    raise notice 'Fundido: "%" recebeu % lancamento(s) de "%"', r.fica, n, r.sai;
  end loop;

  raise notice 'Pares fundidos: % | lancamentos repontados: %', n_pares, n_lanc;
end
$funde2$;


-- ============================================================
-- CONFERENCIA 1 - O DINHEIRO CONTINUA TODO LA
-- Tem que dar 2.759 linhas e R$ 10.226.028,01 (ou mais, se voce lancou
-- coisa nova). O que nao pode e diminuir.
-- ============================================================
select count(*) as lancamentos, sum(valor) as total,
       count(*) filter (where not exists (
         select 1 from centros_custo c where c.id = l.centro_custo_id)) as orfaos
from lancamentos_financeiros l;


-- ============================================================
-- CONFERENCIA 2 - AS CONTAS QUE FORAM FUNDIDAS
-- Cada uma agora com o total somado das duas metades.
-- ============================================================
select c.nome as centro, c.subcategoria as grupo,
       count(l.id) as lancamentos, coalesce(sum(l.valor),0) as total
from centros_custo c
left join lancamentos_financeiros l on l.centro_custo_id = c.id
where lower(btrim(c.nome)) in (
  'combustíveis da operação agropecuária','serviços profissionais',
  'energia elétrica de infraestrutura operacional','despesas com a casa-sede',
  'despesas com instalações - administração','despesas com veículos - administração',
  'contratação de seguros')
group by c.id, c.nome, c.subcategoria
order by 4 desc;


-- ============================================================
-- CONFERENCIA 3 - O RELATORIO POR GRUPO
-- Tem que ser IGUAL ao de antes da fusao: as duas metades de cada par ja
-- estavam no mesmo grupo. Se algum grupo mudou de valor, me avise.
-- ============================================================
select
  coalesce(c.tipo, '(sem tipo)') as tipo,
  case when c.subcategoria is null then '(sem grupo)'
       when position('|' in c.subcategoria) > 0
         then btrim(split_part(c.subcategoria, '|', 1))
       else btrim(c.subcategoria) end as grupo,
  count(l.id) as lancamentos,
  sum(l.valor) as total
from lancamentos_financeiros l
join centros_custo c on c.id = l.centro_custo_id
group by 1, 2
order by 1, 4 desc;
