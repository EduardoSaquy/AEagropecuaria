-- ============================================================
-- OS QUE ESTAVAM ESCRITOS DIFERENTE
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz), DEPOIS DO centros_05.
--
-- ------------------------------------------------------------
-- ANTES DE MAIS NADA: UM DEFEITO NO centros_06
--
-- O centros_06 comparava o nome do nosso centro so contra as CONTAS do
-- Conag (nivel 4). Nao comparava contra as CLASSES (nivel 3) - que e
-- justamente onde os nossos nomes moram.
--
-- Por isso ele deu vereditos errados nos casos que mais importavam:
--
--   "Mao de Obra Operacional" (985 lancamentos, R$ 317.857,68) saiu como
--   "nossa mesmo, o Conag nao tem" com parecenca 0,19 contra EXAME MEDICO
--   OCUPACIONAL. E o maior centro em uso que temos, e o Conag tem sim: a
--   classe MAO-DE-OBRA DE OPERACIONAL. Nao casou no centros_05 por causa
--   dos hifens, e o centros_06 nao pegou porque olhou para o andar errado.
--
-- Conferi os 23 na mao contra a arvore. O que segue e o resultado disso,
-- nao a saida do 06.
--
-- ------------------------------------------------------------
-- O QUE ESTE SCRIPT FAZ
--
-- 1. Seis centros NOSSOS, EM USO, ganham a classe certa do Conag. O nome
--    deles nao muda, os lancamentos nao se mexem. So passam a somar junto
--    com as contas do Conag num relatorio agrupado por classe.
--
-- 2. Tres centros VAZIOS que sao a mesma coisa que uma conta do Conag
--    saem de circulacao (ativo = false). Nao sao apagados: ativo volta a
--    true numa linha de SQL se voce quiser.
--
-- 3. Os outros 14 ficam como estao. Sao contas do plano que montamos e o
--    Conag nao movimentou no periodo - ENTRADA DE FINANCIAMENTOS,
--    DIVIDENDOS, CERTIFICACOES E RASTREABILIDADE e por ai. Conta sem
--    movimento nao sai no balancete; nao aparecer la nao quer dizer que
--    nao exista.
--
-- Nenhum lancamento e criado, movido ou apagado.
--
-- ------------------------------------------------------------
-- POR QUE COMPARAR COM plano_norm E NAO COM O NOME ESCRITO
--
-- Para este arquivo nao ter um unico caractere acentuado. plano_norm tira
-- o acento do lado do banco, entao "Servicos Tecnicos / Consultoria" aqui
-- casa com "Servicos Tecnicos / Consultoria" la, com cedilha e til.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_name='centros_custo' and column_name='classe') then
    raise exception 'RODE O centros_05 PRIMEIRO - a coluna classe nao existe';
  end if;
end $$;


-- ------------------------------------------------------------
-- 1. OS SEIS EM USO: SO A CLASSE
--
-- Cada linha foi conferida contra hierarquia_nivel3.txt, lida do balancete.
-- A quarta coluna e o volume que o Conag tem na mesma classe, para dar
-- ideia do que vai passar a somar junto.
-- ------------------------------------------------------------
with de_para(nome_norm, classe_certa, sub_certa, obs) as (values
  ('MAO DE OBRA OPERACIONAL',
   'MAO-DE-OBRA DE OPERACIONAL',
   'OPERACIONAL | MAO DE OBRA OPERACIONAL',
   'nossos 985 encontram SALARIOS, FGTS, FERIAS, 13o, DIARISTA do Conag'),

  ('MANUTENCAO DE MAQUINAS E FROTA',
   'MANUTENCAO DE TRATORES, CAMINHOES, MAQUINAS, EQUIPAMENTOS E IMPLEMENTOS',
   'OPERACIONAL | MANUTENCAO GERAL DA FAZENDA',
   'nossos 288 encontram os 1.407 de MANUTENCAO DA FROTA'),

  ('SERVICOS TECNICOS / CONSULTORIA',
   'SERVICOS TECNICOS PROFISSIONAIS (CONSULTORIAS DE CAMPO)',
   'OPERACIONAL | PRESTACAO DE SERVICOS',
   'nossos 68 encontram os 170 de SERVICOS TECNICOS PROFISSIONAIS'),

  ('DESPESAS COM VEICULOS',
   'DESPESAS COM VEICULOS - ADMINISTRACAO',
   'ADM | DESPESAS COM ADMINISTRACAO',
   'nossos 5 encontram os 364 de MANUTENCAO DOS VEICULOS DA ADMINISTRACAO'),

  ('DESPESAS COM INSTALACOES',
   'DESPESAS COM INSTALACOES - ADMINISTRACAO',
   'ADM | DESPESAS COM ADMINISTRACAO',
   'nossos 8 encontram ALUGUEL, ENERGIA, AGUA, TELEFONIA do escritorio'),

  -- Vendas guarda R$ 4,76 milhoes de receita nossa. A classe PRODUCAO
  -- AGROPECUARIA e onde o Conag poe a venda fisica da producao. Sem isso a
  -- nossa receita fica num balde e a deles noutro.
  ('VENDAS',
   'PRODUCAO AGROPECUARIA',
   'ATIVIDADES OPERACIONAIS',
   'nossos 21 (R$ 4,76 mi) encontram RECEITA COM PRODUCAO - VENDA FISICA')
)
update centros_custo c
   set classe       = d.classe_certa,
       subcategoria = coalesce(c.subcategoria, d.sub_certa),
       updated_at   = now()
  from de_para d
 where plano_norm(c.nome) = d.nome_norm
   and c.classe is distinct from d.classe_certa;


-- ------------------------------------------------------------
-- 2. OS TRES VAZIOS QUE DUPLICAM CONTA DO CONAG
--
-- So sai de circulacao quem tem ZERO lancamento. O "not exists" e a trava:
-- se algum tiver ganhado lancamento entre a consulta do 06 e agora, ele
-- fica ativo e a conferencia do fim mostra que sobrou.
-- ------------------------------------------------------------
update centros_custo c
   set ativo = false, updated_at = now()
 where plano_norm(c.nome) in (
         -- vira COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE (45 no Conag)
         'COMPRA DE ANIMAIS PARA ENGORDA',
         -- vira JUROS PAGOS OU INCORRIDOS (85 no Conag, R$ 1,4 mi)
         'JUROS E ENCARGOS DE FINANCIAMENTO',
         -- vira MANUTENCAO DOS VEICULOS DA ADMINISTRACAO (364 no Conag)
         'MANUTENCAO DE VEICULOS LEVES'
       )
   and c.ativo
   and not exists (select 1 from lancamentos_financeiros l where l.centro_id = c.id);


-- ------------------------------------------------------------
-- CONFERE - uma consulta so
-- ------------------------------------------------------------
select 1 as ordem, 'Centros em uso que ganharam classe do Conag' as item,
       count(*)::text as valor,
       'esperado: 6' as situacao
from centros_custo
where plano_norm(nome) in ('MAO DE OBRA OPERACIONAL','MANUTENCAO DE MAQUINAS E FROTA',
                           'SERVICOS TECNICOS / CONSULTORIA','DESPESAS COM VEICULOS',
                           'DESPESAS COM INSTALACOES','VENDAS')
  and plano_norm(classe) <> plano_norm(nome)
union all
select 2, 'Lancamentos que passam a cair em classe do Conag',
       count(*)::text, 'esperado: 1.375'
from lancamentos_financeiros l
join centros_custo c on c.id = l.centro_id
where plano_norm(c.nome) in ('MAO DE OBRA OPERACIONAL','MANUTENCAO DE MAQUINAS E FROTA',
                             'SERVICOS TECNICOS / CONSULTORIA','DESPESAS COM VEICULOS',
                             'DESPESAS COM INSTALACOES','VENDAS')
union all
select 3, 'Valor deles', round(coalesce(sum(l.valor),0),2)::text,
       'so mudou de gaveta, nao de valor'
from lancamentos_financeiros l
join centros_custo c on c.id = l.centro_id
where plano_norm(c.nome) in ('MAO DE OBRA OPERACIONAL','MANUTENCAO DE MAQUINAS E FROTA',
                             'SERVICOS TECNICOS / CONSULTORIA','DESPESAS COM VEICULOS',
                             'DESPESAS COM INSTALACOES','VENDAS')
union all
select 4, 'Centros vazios tirados de circulacao', count(*)::text,
       'esperado: 3 - da para reativar quando quiser'
from centros_custo
where not ativo
  and plano_norm(nome) in ('COMPRA DE ANIMAIS PARA ENGORDA',
                           'JUROS E ENCARGOS DE FINANCIAMENTO',
                           'MANUTENCAO DE VEICULOS LEVES')
union all
select 5, 'Centros fora da arvore que sobraram', count(*)::text,
       'esperado: 14 - contas nossas sem movimento no Conag'
from centros_custo c
where c.ativo
  and not exists (select 1 from conag_plano_contas p
                   where plano_norm(p.classe) = plano_norm(c.classe))
union all
select 6, 'Centros ativos', count(*)::text, 'eram 64'
from centros_custo where ativo
union all
select 7, 'Lancamentos', count(*)::text, 'NAO pode ter mudado'
from lancamentos_financeiros
union all
select 8, 'Total lancado', round(sum(valor),2)::text, 'NAO pode ter mudado'
from lancamentos_financeiros
order by ordem;
