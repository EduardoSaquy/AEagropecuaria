-- ============================================================
-- DEVOLVE O GRUPO AOS CENTROS DE CUSTO QUE PERDERAM A CLASSIFICACAO
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
--
-- LEIA A PRIMEIRA CONSULTA ANTES DE RODAR O RESTO. Ela mostra o que sera
-- feito, sem fazer.
--
-- ------------------------------------------------------------
-- O QUE ACONTECEU
--
-- Existiam dois planos de contas no mesmo banco: o do AE Cana (nomes em
-- caixa mista, sem grupo) e o do Conag (nomes em MAIUSCULAS, com tipo e
-- subcategoria). Varias contas eram a mesma coisa nos dois - "Insumos
-- Agricolas" e "INSUMOS AGRICOLAS", por exemplo.
--
-- O lavoura_06 fundiu esses pares mantendo o de MENOR id. Os centros do
-- AE Cana sao mais antigos, entao ganharam a disputa: sobreviveu o nome sem
-- classificacao, e o do Conag, que trazia o grupo, foi apagado.
--
-- Nenhum lancamento se perdeu - todos foram repontados antes de qualquer
-- exclusao, e a conferencia geral confirma os R$ 10.226.028,01 intactos. O
-- que se perdeu foi o GRUPO, e e isso que este script devolve.
--
-- O criterio certo teria sido preferir o centro classificado, e nao o mais
-- antigo. Fica registrado para a proxima fusao.
--
-- ------------------------------------------------------------
-- O QUE ESTE SCRIPT FAZ, E O QUE NAO FAZ
--
-- FAZ: classifica os 12 centros cujo nome corresponde a um grupo do Conag
-- sem margem para duvida.
--
-- NAO FAZ: os 6 em que a escolha e sua de verdade, porque muda o
-- relatorio. Eles saem listados no fim, para voce decidir.
-- ============================================================


-- ------------------------------------------------------------
-- 1) O QUE SERA FEITO (so leitura - rode primeiro)
-- ------------------------------------------------------------
with proposta(nome, novo_tipo, nova_subcategoria) as (values
  ('Vendas',                                                  'entrada','ATIVIDADES OPERACIONAIS'),
  ('Insumos Agrícolas',                                       'saida','OPERACIONAL | INSUMOS AGROPECUÁRIOS'),
  ('Mão de Obra Operacional',                                 'saida','OPERACIONAL | MÃO DE OBRA OPERACIONAL'),
  ('Combustíveis',                                            'saida','OPERACIONAL | GASTOS COM COMBUSTÍVEIS'),
  ('Energia Elétrica',                                        'saida','OPERACIONAL | ENERGIA ELÉTRICA DA FAZENDA'),
  ('Terceirização de Serviços Agropecuários',                 'saida','OPERACIONAL | PRESTAÇÃO DE SERVIÇOS'),
  ('Manutenção de Infraestrutura',                            'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA'),
  ('Manutenção de Máquinas e Frota',                          'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA'),
  ('Casa-Sede',                                               'saida','ADM | DESPESAS COM ADMINISTRAÇÃO'),
  ('Instalações - Administração',                             'saida','ADM | DESPESAS COM ADMINISTRAÇÃO'),
  ('Veículos - Administração',                                'saida','ADM | DESPESAS COM ADMINISTRAÇÃO'),
  ('Serviços Profissionais (Segurança/Cartório/Contabilidade)','saida','ADM | DESPESAS COM ADMINISTRAÇÃO')
)
select c.nome as centro,
       p.novo_tipo, p.nova_subcategoria,
       (select count(*) from lancamentos_financeiros l where l.centro_custo_id = c.id) as lancamentos,
       (select coalesce(sum(l.valor),0) from lancamentos_financeiros l where l.centro_custo_id = c.id) as total
from centros_custo c
join proposta p on lower(btrim(p.nome)) = lower(btrim(c.nome))
where coalesce(trim(c.subcategoria), '') = ''
order by 5 desc;


-- ------------------------------------------------------------
-- 2) APLICA (rode depois de conferir a consulta acima)
-- ------------------------------------------------------------
do $reclass$
declare
  n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  with proposta(nome, novo_tipo, nova_subcategoria) as (values
    ('Vendas',                                                  'entrada','ATIVIDADES OPERACIONAIS'),
    ('Insumos Agrícolas',                                       'saida','OPERACIONAL | INSUMOS AGROPECUÁRIOS'),
    ('Mão de Obra Operacional',                                 'saida','OPERACIONAL | MÃO DE OBRA OPERACIONAL'),
    ('Combustíveis',                                            'saida','OPERACIONAL | GASTOS COM COMBUSTÍVEIS'),
    ('Energia Elétrica',                                        'saida','OPERACIONAL | ENERGIA ELÉTRICA DA FAZENDA'),
    ('Terceirização de Serviços Agropecuários',                 'saida','OPERACIONAL | PRESTAÇÃO DE SERVIÇOS'),
    ('Manutenção de Infraestrutura',                            'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA'),
    ('Manutenção de Máquinas e Frota',                          'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA'),
    ('Casa-Sede',                                               'saida','ADM | DESPESAS COM ADMINISTRAÇÃO'),
    ('Instalações - Administração',                             'saida','ADM | DESPESAS COM ADMINISTRAÇÃO'),
    ('Veículos - Administração',                                'saida','ADM | DESPESAS COM ADMINISTRAÇÃO'),
    ('Serviços Profissionais (Segurança/Cartório/Contabilidade)','saida','ADM | DESPESAS COM ADMINISTRAÇÃO')
  )
  update centros_custo c
     set tipo = p.novo_tipo, subcategoria = p.nova_subcategoria
    from proposta p
   where lower(btrim(p.nome)) = lower(btrim(c.nome))
     and coalesce(trim(c.subcategoria), '') = '';
  get diagnostics n = row_count;
  raise notice 'Centros classificados: %', n;

  -- "Nao classificado" foi criado pela migracao para receber o que viesse
  -- sem centro de custo na origem. Ficou com zero lancamentos: nada precisou
  -- dele. So apaga se continuar vazio.
  delete from centros_custo c
   where lower(btrim(c.nome)) = 'nao classificado'
     and not exists (select 1 from lancamentos_financeiros l where l.centro_custo_id = c.id)
     and not exists (select 1 from despesas_cana  d where d.centro_custo_id = c.id)
     and not exists (select 1 from despesas_graos d where d.centro_custo_id = c.id);
  get diagnostics n = row_count;
  if n > 0 then raise notice 'Centro "Nao classificado" removido (estava sem uso).'; end if;
end
$reclass$;


-- ============================================================
-- CONFERENCIA 1 - O QUE AINDA FALTA CLASSIFICAR
--
-- Devem sobrar 6, os que dependem de decisao sua. Estao no fim da tela de
-- Centros de Custo do Matriz, em "Sem classificação".
-- ============================================================
select c.nome as centro,
       (select count(*) from lancamentos_financeiros l where l.centro_custo_id = c.id) as lancamentos,
       (select coalesce(sum(l.valor),0) from lancamentos_financeiros l where l.centro_custo_id = c.id) as total
from centros_custo c
where coalesce(trim(c.subcategoria), '') = ''
order by 3 desc;


-- ============================================================
-- CONFERENCIA 2 - O DINHEIRO POR GRUPO
--
-- E o relatorio que a tela do Matriz passa a mostrar. Confira se a divisao
-- faz sentido contra a sua contabilidade: e o teste que vale mais que
-- qualquer conferencia minha.
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
-- ordena pelas POSICOES das colunas do resultado: c.tipo nao existe aqui,
-- porque o agrupamento e pela expressao coalesce(c.tipo, ...), nao pela
-- coluna crua
order by 1, 4 desc;
