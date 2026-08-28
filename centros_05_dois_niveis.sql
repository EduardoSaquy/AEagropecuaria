-- ============================================================
-- O NIVEL QUE FALTAVA: A CLASSE
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- Substitui o centros_04_nivel_classe.sql, que partia de uma premissa
-- errada. NAO rode o 04.
--
-- ------------------------------------------------------------
-- O PROBLEMA
--
-- O plano do Conag tem QUATRO niveis. O nosso tem TRES:
--
--   nivel 1  ENTRADAS / SAIDAS                    centros_custo.tipo
--   nivel 2  OPERACIONAL | INSUMOS AGROPECUARIOS  centros_custo.subcategoria
--   nivel 3  INSUMOS AGRICOLAS                    <-- nao existia
--   nivel 4  ADUBOS E FERTILIZANTES               a conta em si
--
-- O erro do script 04 foi supor que os nossos 64 centros eram nivel 4.
-- Nao sao. Conferi um a um contra o balancete: os nossos nomes estao no
-- NIVEL 3. COMBUSTIVEIS DA OPERACAO AGROPECUARIA, ALUGUEL DE AREA
-- PRODUTIVA, ALIENACAO DE ATIVOS - todos classe, nenhum conta.
--
-- Os 9.400 lancamentos do Conag apontam para o NIVEL 4: ADUBOS E
-- FERTILIZANTES, NUTRICAO ANIMAL, SALARIOS, DEFENSIVOS AGRICOLAS.
--
-- Por isso 84 dos 85 centros do CSV nao acharam par: nao ha cruzamento
-- nenhum entre os dois conjuntos. Eles vivem em andares diferentes.
--
-- ------------------------------------------------------------
-- POR QUE NAO ACHATAR OS DOIS NUM NIVEL SO
--
-- Achatar para o nivel 3 jogaria fora a granularidade que o Conag tem:
--
--   INSUMOS AGRICOLAS  =  adubo R$ 2,6 mi
--                       + defensivo R$ 1,0 mi
--                       + semente R$ 0,6 mi
--                       + corretivo + embalagem
--
-- Vira um numero so. Deixa de dar para responder "quanto de adubo por
-- hectare" - que e exatamente a pergunta que o app existe para responder.
--
-- ------------------------------------------------------------
-- O QUE ESTE SCRIPT FAZ
--
-- Faz os dois niveis conviverem, com a CLASSE como denominador comum:
--
--   1. cria a coluna classe em centros_custo
--   2. cria conag_plano_contas - a arvore do Conag, 96 contas, 41 classes,
--      20 subcategorias, lida do balancete de 27/08/2026
--   3. preenche a classe dos 64 centros atuais. Como eles SAO nivel 3, a
--      classe recebe o proprio nome deles
--   4. de quebra, preenche tipo e subcategoria onde estavam nulos
--
-- NAO cria conta nova e NAO toca em lancamento nenhum. As 85 contas de
-- nivel 4 nascem no conag_12, a partir do CSV ja carregado - assim os
-- nomes vem com acento do proprio dado, sem literal acentuado aqui.
--
-- Depois disso, um relatorio que agrupe por CLASSE soma os 2.760 antigos
-- com os 9.400 novos sem nenhum de-para na mao. Um que agrupe por CONTA
-- mostra o detalhe onde ele existe.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
end $$;

create extension if not exists unaccent;


-- ------------------------------------------------------------
-- A COLUNA
-- ------------------------------------------------------------
alter table centros_custo add column if not exists classe text;


-- ------------------------------------------------------------
-- COMPARADOR DE NOMES
--
-- Os nossos nomes vieram de importacao e nem sempre batem caractere a
-- caractere com a tela do Conag: acento, caixa, espaco duplo, o "o" de
-- 13o SALARIO. Esta funcao tira tudo isso da frente.
--
-- unaccent em vez de translate escrito a mao: o arquivo fica sem um unico
-- caractere acentuado e o separador de statements nao tem como se perder.
-- chr(186) e o simbolo de ordinal masculino, chr(170) o feminino.
-- ------------------------------------------------------------
create or replace function plano_norm(txt text)
returns text
language sql
immutable
as $$
  select upper(
           regexp_replace(
             btrim(
               unaccent(
                 translate(coalesce(txt,''), chr(186)||chr(170), 'oa')
               )
             ),
             '\s+', ' ', 'g'
           )
         );
$$;

comment on function plano_norm(text) is
  'Normaliza nome de conta para comparacao: sem acento, maiusculo, sem '
  'espaco repetido. Usada para casar o nosso plano com o do Conag.';


-- ------------------------------------------------------------
-- A ARVORE DO CONAG
--
-- Fica no banco de proposito, e nao so neste arquivo: o conag_12 le dela
-- para saber em que classe pendurar cada conta nova, e daqui a seis meses
-- ela responde "de onde veio essa hierarquia" sem depender de eu estar por
-- perto.
--
-- So tem conta COM movimento - o balancete nao imprime conta zerada.
--
-- A chave e SUBCATEGORIA + CONTA, nao so a conta: TRIBUTOS existe em duas
-- subcategorias diferentes, cada uma numa classe. Casar so pelo nome poria
-- as duas na mesma.
--
-- tipo nulo nas VARIACOES NAO OPERACIONAIS DE CAIXA e proposital: ajuste
-- de saldo, estorno e outras movimentacoes andam nos dois sentidos. Centro
-- com tipo nulo aparece nas duas listas do app, que e o certo para elas.
-- ------------------------------------------------------------
drop table if exists conag_plano_contas;
create table conag_plano_contas (
  grupo         text not null,   -- nivel 1 do Conag
  subcategoria  text not null,   -- nivel 2
  classe        text not null,   -- nivel 3  <-- o que faltava
  conta         text not null,   -- nivel 4
  tipo          text,            -- entrada / saida / nulo = ambos
  primary key (subcategoria, conta)
);

comment on table conag_plano_contas is
  'Plano de contas do Conag lido do balancete de 27/08/2026 (2014-2030, '
  'todas as fazendas e atividades). Referencia da hierarquia: o conag_12 '
  'usa para classificar as contas que vierem do CSV.';

insert into conag_plano_contas (grupo, subcategoria, classe, conta, tipo) values
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS AGRICOLAS', 'ADUBOS E FERTILIZANTES', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS AGRICOLAS', 'DEFENSIVOS AGRICOLAS', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS AGRICOLAS', 'SEMENTES E MUDAS DE PLANTIO', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS AGRICOLAS', 'CORRETIVOS DE SOLO', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS AGRICOLAS', 'EMBALAGENS, SACARIAS E LONAS', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS PECUARIOS', 'NUTRICAO ANIMAL', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS PECUARIOS', 'REPRODUCAO ANIMAL', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS PECUARIOS', 'FERRAMENTAS E UTENSILIOS PARA MANEJO', 'saida'),
  ('OPERACIONAL', 'INSUMOS AGROPECUARIOS', 'INSUMOS PECUARIOS', 'SANIDADE ANIMAL', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'SALARIOS', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'DIARISTA', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'FGTS', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'FERIAS', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'PLANO DE SAUDE', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', '13O SALARIO', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'RESCISAO', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'GRATIFICACOES', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'OUTROS ENCARGOS', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'MAO-DE-OBRA DE OPERACIONAL', 'IMPOSTO DE RENDA - FOLHA DE PAGAMENTO', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'REFEITORIO, RESTAURANTES & ALIMENTACAO', 'AQUISICAO DE REFEICOES PRONTAS', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'REFEITORIO, RESTAURANTES & ALIMENTACAO', 'COMPRA DE ALIMENTOS', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'REFEITORIO, RESTAURANTES & ALIMENTACAO', 'MATERIAIS DE LIMPEZA', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'REFEITORIO, RESTAURANTES & ALIMENTACAO', 'PAGAMENTO DE SERVICOS TERCEIRIZADOS RELACIONADOS AO REFEITORIO', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'GASTOS COM PESSOAL', 'SEGURANCA DO TRABALHO E EPI', 'saida'),
  ('OPERACIONAL', 'MAO DE OBRA OPERACIONAL', 'GASTOS COM PESSOAL', 'EXAME MEDICO OCUPACIONAL E PERIODICO', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'MANUTENCAO DE TRATORES, CAMINHOES, MAQUINAS, EQUIPAMENTOS E IMPLEMENTOS', 'MANUTENCAO DA FROTA DE VEICULOS, MAQUINAS E EQUIPAMENTOS DE CAMPO', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'MANUTENCAO DE TRATORES, CAMINHOES, MAQUINAS, EQUIPAMENTOS E IMPLEMENTOS', 'SEGURO DE MAQUINAS E EQUIPAMENTOS', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'MANUTENCAO E REPARO DE INFRAESTRUTURAS', 'MANUTENCAO DE INFRAESTRUTURA', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'MANUTENCAO E REPARO DE INFRAESTRUTURAS', 'MANUTENCAO DE ESTRADAS E CARREADORES', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'MANUTENCAO E REPARO DE INFRAESTRUTURAS', 'REDE ELETRICA', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'MANUTENCAO E REPARO DE INFRAESTRUTURAS', 'REDE HIDRICA', 'saida'),
  ('OPERACIONAL', 'MANUTENCAO GERAL DA FAZENDA', 'DESPESAS COM OFICINA', 'MATERIAIS DE OFICINA', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'TERCEIRIZACAO DE SERVICOS AGROPECUARIOS', 'PRESTACAO DE SERVICOS PARA O CAMPO', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'TERCEIRIZACAO DE SERVICOS AGROPECUARIOS', 'FRETE COMPRA DE PRODUTOS', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'TERCEIRIZACAO DE SERVICOS AGROPECUARIOS', 'TERCEIRIZACAO DE COLHEITA', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'TERCEIRIZACAO DE SERVICOS AGROPECUARIOS', 'ALUGUEL DE MAQUINAS E EQUIPAMENTOS', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'TERCEIRIZACAO DE SERVICOS AGROPECUARIOS', 'FRETE DE ANIMAIS', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'TERCEIRIZACAO DE SERVICOS AGROPECUARIOS', 'ANALISES AGRICOLAS (SOLO, FOLHA, ETC)', 'saida'),
  ('OPERACIONAL', 'PRESTACAO DE SERVICOS', 'SERVICOS TECNICOS PROFISSIONAIS (CONSULTORIAS DE CAMPO)', 'SERVICOS TECNICOS PROFISSIONAIS', 'saida'),
  ('OPERACIONAL', 'GASTOS COM COMBUSTIVEIS', 'COMBUSTIVEIS DA OPERACAO AGROPECUARIA', 'COMBUSTIVEL PARA FROTA TRATORES, MAQUINAS E VEICULOS DA OPERACAO', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'SERVICOS PROFISSIONAIS', 'CARTORIO', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'SERVICOS PROFISSIONAIS', 'CONTABILIDADE', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'SERVICOS PROFISSIONAIS', 'SEGURANCA E VIGILANCIA', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'SERVICOS PROFISSIONAIS', 'OUTROS SERVICOS PROFISSIONAIS', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'SERVICOS PROFISSIONAIS', 'TECNOLOGIA E SOFTWARE', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'SERVICOS PROFISSIONAIS', 'JURIDICO', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM VEICULOS - ADMINISTRACAO', 'MANUTENCAO DOS VEICULOS DA ADMINISTRACAO', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM VEICULOS - ADMINISTRACAO', 'MULTAS E OUTRAS INDENIZACOES', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM INSTALACOES - ADMINISTRACAO', 'MANUTENCAO GERAL DO ESCRITORIO', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM INSTALACOES - ADMINISTRACAO', 'ALUGUEL', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM INSTALACOES - ADMINISTRACAO', 'COMUNICACAO E TELEFONIA', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM INSTALACOES - ADMINISTRACAO', 'ENERGIA ELETRICA', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM INSTALACOES - ADMINISTRACAO', 'HIGIENE E LIMPEZA', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM INSTALACOES - ADMINISTRACAO', 'AGUA', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM A CASA-SEDE', 'DESPESAS COM A CASA-SEDE', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM A CASA-SEDE', 'MANUTENCAO E PRESTADORES DE SERVICO NA CASA-SEDE', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM A CASA-SEDE', 'DESPESAS GERAIS NA CASA-SEDE', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS GERAIS - ADMINISTRACAO', 'VIAGENS E ESTADIAS', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS GERAIS - ADMINISTRACAO', 'DESPESAS GERAIS DA ADMINISTRACAO', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS GERAIS - ADMINISTRACAO', 'CORREIOS E TRANSPORTES', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS GERAIS - ADMINISTRACAO', 'LICENCAS E TAXAS', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DOACOES', 'DOACOES', 'saida'),
  ('ADM', 'DESPESAS COM ADMINISTRACAO', 'DESPESAS COM SOCIOS E DIRIGENTES', 'OUTROS BENEFICIOS', 'saida'),
  ('OPERACIONAL', 'ARRENDAMENTO DE TERRAS E PARCERIAS', 'ALUGUEL DE AREA PRODUTIVA', 'ARRENDAMENTO DE AREA PRODUTIVA', 'saida'),
  ('TRIBUTOS', 'TRIBUTOS E CONTRIBUICOES', 'TRIBUTOS E CONTRIBUICOES', 'TRIBUTOS', 'saida'),
  ('TRIBUTOS', 'TRIBUTOS E CONTRIBUICOES', 'TRIBUTOS E CONTRIBUICOES', 'IMPOSTO DE RENDA SOBRE LUCRO LIQUIDO', 'saida'),
  ('COMERCIAL', 'DESPESAS COM COMERCIALIZACAO', 'ARMAZENAGEM & LOGISTICA', 'FRETE PARA COMERCIALIZACAO DA PRODUCAO AGROPECUARIA', 'saida'),
  ('OPERACIONAL', 'ENERGIA ELETRICA DA FAZENDA', 'ENERGIA ELETRICA DE INFRAESTRUTURA OPERACIONAL', 'ENERGIA ELETRICA DA FAZENDA', 'saida'),
  ('OPERACIONAL', 'OUTROS CUSTOS', 'CONTRATACAO DE SEGUROS', 'SEGUROS AGROPECUARIOS (SEGURO DE SAFRA)', 'saida'),
  ('OPERACIONAL', 'OUTROS CUSTOS', 'CONTRATACAO DE SEGUROS', 'OUTROS SEGUROS', 'saida'),
  ('DESPESAS', 'PARTICIPACOES NOS RESULTADOS', 'PARTICIPACAO NOS LUCROS E RESULTADOS (PLR)', 'BONUS DOS FUNCIONARIOS DA(S) FAZENDA(S)', 'saida'),
  ('TRIBUTOS', 'IMPOSTOS SOBRE LUCRO', 'DEDUCOES DA RECEITA BRUTA DE VENDAS', 'TRIBUTOS', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO EM ANIMAIS', 'COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO EM ANIMAIS', 'COMPRA DE MATRIZES PARA REPRODUCAO', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO EM ANIMAIS', 'COMPRA DE EQUINOS', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO EM ATIVOS', 'AQUISICAO DE MAQUINAS, CAMINHOES E EQUIPAMENTOS', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO EM ATIVOS', 'INVESTIMENTO EM TERRAS', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO EM ATIVOS', 'INVESTIMENTOS EM INFRAESTRUTURA', 'saida'),
  ('INVESTIMENTOS', 'SAIDA PARA INVESTIMENTOS', 'INVESTIMENTO FINANCEIRO', 'INVESTIMENTO EM CONSORCIO (NAO CONTEMPLADO)', 'saida'),
  ('FINANCIAMENTOS', 'AMORTIZACAO DE FINANCIAMENTOS', 'AMORTIZACOES DE EMPRESTIMOS E FINANCIAMENTOS', 'AMORTIZACAO DE FINANCIAMENTO', 'saida'),
  ('FINANCIAMENTOS', 'DESPESAS FINANCEIRAS', 'DESPESAS FINANCEIRAS', 'JUROS PAGOS OU INCORRIDOS', 'saida'),
  ('FINANCIAMENTOS', 'DESPESAS FINANCEIRAS', 'CUSTAS CONTRATUAIS', 'PROJETOS TECNICOS', 'saida'),
  ('FINANCIAMENTOS', 'DESPESAS FINANCEIRAS', 'CUSTAS CONTRATUAIS', 'DESPESAS COM CARTORIO PARA CONTRATOS DE FINANCIAMENTO', 'saida'),
  ('FINANCIAMENTOS', 'DESPESAS FINANCEIRAS', 'CUSTAS CONTRATUAIS', 'IOF', 'saida'),
  ('ATIVIDADES OPERACIONAIS', 'ATIVIDADES OPERACIONAIS', 'PRODUCAO AGROPECUARIA', 'RECEITA COM PRODUCAO AGROPECUARIA - VENDA FISICA', 'entrada'),
  ('ATIVIDADES OPERACIONAIS', 'ATIVIDADES OPERACIONAIS', 'RECEITA COM ARRENDAMENTO DE TERRAS E PARCERIAS', 'RECEBIMENTO DE ARRENDAMENTO DE TERRAS', 'entrada'),
  ('ATIVIDADES OPERACIONAIS', 'ATIVIDADES OPERACIONAIS', 'RECEITA COM PRESTACAO DE SERVICOS', 'PRESTACAO DE SERVICOS AGROPECUARIOS', 'entrada'),
  ('ATIVIDADES DE INVESTIMENTO', 'ATIVIDADES DE INVESTIMENTO', 'ALIENACAO DE ATIVOS', 'VENDA DE VEICULOS, MAQUINAS E EQUIPAMENTOS', 'entrada'),
  ('ATIVIDADES DE FINANCIAMENTO', 'ATIVIDADES DE FINANCIAMENTO', 'INTEGRALIZACAO DE CAPITAL', 'APORTE DE CAPITAL DE TERCEIROS (FUNDOS DE INVESTIMENTOS, NOVOS SOCIOS, OUTROS)', 'entrada'),
  ('ATIVIDADES DE FINANCIAMENTO', 'ATIVIDADES DE FINANCIAMENTO', 'RECEITAS FINANCEIRAS', 'RENDIMENTOS DE APLICACOES FINANCEIRAS', 'entrada'),
  ('VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES DE CAIXA NAO OPERACIONAL', 'AJUSTE DE SALDO BANCARIO', null),
  ('VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES DE CAIXA NAO OPERACIONAL', 'ESTORNO E/OU DEVOLUCAO DE PAGAMENTO', null),
  ('VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES DE CAIXA NAO OPERACIONAL', 'OUTRAS MOVIMENTACOES DE CAIXA', null),
  ('VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES NAO OPERACIONAIS DE CAIXA', 'APLICACOES FINANCEIRAS', 'RESGATE DE APLICACOES FINANCEIRAS', null),
  ('VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES NAO OPERACIONAIS DE CAIXA', 'OUTRAS RECEITAS NAO OPERACIONAIS', 'OUTROS RECEBIMENTOS NAO RELACIONADOS A ATIVIDADE RURAL', null),
  ('VARIACOES NAO OPERACIONAIS DE CAIXA', 'VARIACOES NAO OPERACIONAIS DE CAIXA', 'OUTRAS DESPESAS NAO OPERACIONAIS', 'OUTROS PAGAMENTOS NAO RELACIONADOS A ATIVIDADE RURAL', null)
;


-- ------------------------------------------------------------
-- CLASSIFICA OS CENTROS QUE JA EXISTEM
--
-- Tres caminhos, nesta ordem:
--
--   1. o nome do centro E uma classe do Conag  -> classe recebe o proprio
--      nome. E o caso da maioria: eles estao no nivel 3.
--   2. o nome do centro e uma CONTA do Conag   -> classe vem da arvore.
--      Sobra pouco, mas existe.
--   3. nao esta na arvore                      -> classe recebe o proprio
--      nome mesmo assim, para nenhum centro ficar sem classe e sumir de um
--      relatorio agrupado. A consulta do fim lista quais foram.
--
-- Onde tipo e subcategoria estavam nulos, sao preenchidos junto. Onde ja
-- tinham valor, ficam como estao - o que esta no banco vale mais do que o
-- que eu deduzi de um balancete.
-- ------------------------------------------------------------

-- 1. centro cujo nome e uma classe
update centros_custo c
   set classe       = c.nome,
       subcategoria = coalesce(c.subcategoria,
                        case when p.grupo = p.subcategoria then p.grupo
                             else p.grupo || ' | ' || p.subcategoria end),
       tipo         = coalesce(c.tipo, p.tipo),
       updated_at   = now()
  from (select distinct on (plano_norm(classe))
               plano_norm(classe) as classe_norm, grupo, subcategoria, tipo
          from conag_plano_contas
         order by plano_norm(classe), conta) p
 where c.classe is null
   and plano_norm(c.nome) = p.classe_norm;

-- 2. centro cujo nome e uma conta de nivel 4
update centros_custo c
   set classe       = p.classe,
       subcategoria = coalesce(c.subcategoria,
                        case when p.grupo = p.subcategoria then p.grupo
                             else p.grupo || ' | ' || p.subcategoria end),
       tipo         = coalesce(c.tipo, p.tipo),
       updated_at   = now()
  from (select distinct on (plano_norm(conta))
               plano_norm(conta) as conta_norm, grupo, subcategoria, classe, tipo
          from conag_plano_contas
         -- TRIBUTOS existe em duas classes. Entre TRIBUTOS E CONTRIBUICOES
         -- e DEDUCOES DA RECEITA BRUTA DE VENDAS, a primeira e a de custo -
         -- a segunda desconta receita. Aqui vale a de custo.
         order by plano_norm(conta),
                  case when classe = 'DEDUCOES DA RECEITA BRUTA DE VENDAS'
                       then 1 else 0 end) p
 where c.classe is null
   and plano_norm(c.nome) = p.conta_norm;

-- 3. o resto fica com a propria cara
update centros_custo
   set classe = nome, updated_at = now()
 where classe is null;

comment on column centros_custo.classe is
  'Nivel 3 do plano de contas, entre a subcategoria e o nome da conta. '
  'Ex: subcategoria OPERACIONAL | INSUMOS AGROPECUARIOS, classe INSUMOS '
  'AGRICOLAS, nome ADUBOS E FERTILIZANTES. Os centros antigos estao NO '
  'nivel 3 e por isso tem classe igual ao nome; os que vieram do Conag '
  'estao no nivel 4 e tem classe diferente do nome. Relatorio que agrupa '
  'por classe soma os dois sem de-para.';

create index if not exists ix_centros_classe on centros_custo (classe);


-- ------------------------------------------------------------
-- CONFERE - uma consulta so
--
-- O editor do Supabase mostra o resultado de UMA consulta por arquivo.
-- Por isso tudo vem grudado num union all.
-- ------------------------------------------------------------
select 1 as ordem, 'Arvore do Conag carregada' as item,
       count(*)::text as valor,
       'contas de nivel 4 com movimento' as situacao
from conag_plano_contas
union all
select 2, 'Classes distintas na arvore', count(distinct classe)::text,
       'o nivel que faltava'
from conag_plano_contas
union all
select 3, 'Centros nossos hoje', count(*)::text,
       'nenhum foi criado nem apagado'
from centros_custo
union all
select 4, 'Centros com classe preenchida', count(*)::text,
       case when count(*) = (select count(*) from centros_custo)
            then 'todos' else 'FALTOU ALGUM - conferir' end
from centros_custo where classe is not null
union all
select 5, 'Deles, classe = nome (estao no nivel 3)',
       count(*)::text, 'esperado: quase todos'
from centros_custo where plano_norm(classe) = plano_norm(nome)
union all
select 6, 'Deles, classe diferente do nome (nivel 4)',
       count(*)::text, 'esperado: poucos'
from centros_custo where plano_norm(classe) <> plano_norm(nome)
union all
select 7, 'Centros nossos que NAO estao na arvore do Conag',
       count(*)::text, 'ficaram com classe = o proprio nome'
from centros_custo c
where not exists (select 1 from conag_plano_contas p
                   where plano_norm(p.classe) = plano_norm(c.nome)
                      or plano_norm(p.conta)  = plano_norm(c.nome))
union all
select 8, 'Contas de nivel 4 do Conag que ainda nao existem aqui',
       count(*)::text, 'nascem no conag_12, a partir do CSV'
from conag_plano_contas p
where not exists (select 1 from centros_custo c
                   where plano_norm(c.nome) = plano_norm(p.conta))
union all
select 9, 'Lancamentos', count(*)::text, 'NAO pode ter mudado'
from lancamentos_financeiros
union all
select 10, 'Total lancado', round(sum(valor),2)::text, 'NAO pode ter mudado'
from lancamentos_financeiros
order by ordem;
