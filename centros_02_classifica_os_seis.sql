-- ============================================================
-- CLASSIFICA OS SEIS CENTROS QUE FALTAVAM
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode.
--
-- ------------------------------------------------------------
-- AS DECISOES SAO SUAS, E ESTAO ANOTADAS AQUI
--
-- Tributos e Contribuicoes      -> TRIBUTOS | TRIBUTOS E CONTRIBUICOES
--   Grupo NOVO, do lado de IMPOSTOS SOBRE LUCRO. Sua escolha: imposto
--   sobre lucro e contribuicao/taxa sao naturezas diferentes e nao devem
--   somar na mesma linha do relatorio.
--
-- Servicos Tecnicos / Consultoria -> OPERACIONAL | PRESTACAO DE SERVICOS
--   Consultoria de campo entra no custo da producao, nao no escritorio.
--
-- Custas Contratuais            -> FINANCIAMENTOS | DESPESAS FINANCEIRAS
--   Ligadas a contrato de financiamento, nao a cartorio.
--
-- Os tres menores, um a um (voce disse "cada um e um", entao nao juntei):
--
-- Seguros                       -> OPERACIONAL | OUTROS CUSTOS
--   Seguro rural e custo da operacao, e nao ha grupo proprio de seguro.
--
-- Despesas com Veiculos         -> OPERACIONAL | MANUTENCAO GERAL DA FAZENDA
--   Veiculo da pecuaria e da operacao. Diferente de "Veiculos -
--   Administracao", que ja foi para ADM no script anterior.
--
-- Despesas com Instalacoes      -> OPERACIONAL | MANUTENCAO GERAL DA FAZENDA
--   Mesma logica: instalacao da fazenda, nao do escritorio. Diferente de
--   "Instalacoes - Administracao", que ficou em ADM.
--
-- Os tres ultimos sao R$ 4.753 no total, 4% do que faltava. Se eu errei
-- algum, e um clique na tela de Centros de Custo do Matriz para corrigir.
-- ============================================================


-- ------------------------------------------------------------
-- Tira acento sem depender da extensao unaccent, que pode nao estar
-- instalada no projeto. So os acentos que aparecem em nome de conta.
-- ------------------------------------------------------------
create or replace function unaccent_simples(txt text) returns text
language sql immutable as $ua$
  select translate($1,
    'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
    'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')
$ua$;


-- ------------------------------------------------------------
-- 1) O QUE SERA FEITO (so leitura)
-- ------------------------------------------------------------
with proposta(nome, novo_tipo, nova_subcategoria) as (values
  ('Tributos e Contribuições',       'saida','TRIBUTOS | TRIBUTOS E CONTRIBUIÇÕES'),
  ('Serviços Técnicos / Consultoria','saida','OPERACIONAL | PRESTAÇÃO DE SERVIÇOS'),
  ('Custas Contratuais',             'saida','FINANCIAMENTOS | DESPESAS FINANCEIRAS'),
  ('Seguros',                        'saida','OPERACIONAL | OUTROS CUSTOS'),
  ('Despesas com Veículos',          'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA'),
  ('Despesas com Instalações',       'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA')
)
select c.nome as centro, p.nova_subcategoria as vai_para,
       (select count(*) from lancamentos_financeiros l where l.centro_custo_id = c.id) as lancamentos,
       (select coalesce(sum(l.valor),0) from lancamentos_financeiros l where l.centro_custo_id = c.id) as total
from centros_custo c
join proposta p on lower(btrim(p.nome)) = lower(btrim(c.nome))
order by 4 desc;


-- ------------------------------------------------------------
-- 2) APLICA
-- ------------------------------------------------------------
do $seis$
declare
  n int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  with proposta(nome, novo_tipo, nova_subcategoria) as (values
    ('Tributos e Contribuições',       'saida','TRIBUTOS | TRIBUTOS E CONTRIBUIÇÕES'),
    ('Serviços Técnicos / Consultoria','saida','OPERACIONAL | PRESTAÇÃO DE SERVIÇOS'),
    ('Custas Contratuais',             'saida','FINANCIAMENTOS | DESPESAS FINANCEIRAS'),
    ('Seguros',                        'saida','OPERACIONAL | OUTROS CUSTOS'),
    ('Despesas com Veículos',          'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA'),
    ('Despesas com Instalações',       'saida','OPERACIONAL | MANUTENÇÃO GERAL DA FAZENDA')
  )
  update centros_custo c
     set tipo = p.novo_tipo, subcategoria = p.nova_subcategoria
    from proposta p
   where lower(btrim(p.nome)) = lower(btrim(c.nome));
  get diagnostics n = row_count;
  raise notice 'Centros classificados: %', n;
end
$seis$;


-- ============================================================
-- CONFERENCIA 1 - NAO PODE SOBRAR NENHUM SEM GRUPO
-- Tem que voltar VAZIA.
-- ============================================================
select nome,
       (select coalesce(sum(l.valor),0) from lancamentos_financeiros l where l.centro_custo_id = c.id) as total
from centros_custo c
where coalesce(trim(c.subcategoria), '') = ''
order by 2 desc;


-- ============================================================
-- CONFERENCIA 2 - O DINHEIRO POR GRUPO, AGORA COMPLETO
--
-- A soma das linhas tem que dar R$ 10.226.028,01 em 2.759 lancamentos.
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


-- ============================================================
-- DIAGNOSTICO - CONTAS PARECIDAS QUE PODEM SER A MESMA COISA
--
-- Os dois planos de contas conviveram no mesmo banco, e a fusao so juntou
-- os que tinham nome IDENTICO ignorando maiusculas. Nomes parecidos mas
-- diferentes continuam separados - "Seguros" e "CONTRATACAO DE SEGUROS",
-- por exemplo, se as duas ainda existirem.
--
-- Cada par aqui e um candidato a estar dividindo o mesmo gasto em duas
-- linhas do relatorio. NAO junte no automatico: olhe os lancamentos de
-- cada e decida. Voltar vazia tambem e um bom resultado.
-- ============================================================
select a.nome as conta_1, b.nome as conta_2,
       (select coalesce(sum(l.valor),0) from lancamentos_financeiros l where l.centro_custo_id = a.id) as total_1,
       (select coalesce(sum(l.valor),0) from lancamentos_financeiros l where l.centro_custo_id = b.id) as total_2
from centros_custo a
join centros_custo b on a.id < b.id
where
  -- uma contem a outra depois de tirar acento, pontuacao e palavra curta
  position(
    regexp_replace(lower(unaccent_simples(a.nome)), '[^a-z]', '', 'g') in
    regexp_replace(lower(unaccent_simples(b.nome)), '[^a-z]', '', 'g')
  ) > 0
  or position(
    regexp_replace(lower(unaccent_simples(b.nome)), '[^a-z]', '', 'g') in
    regexp_replace(lower(unaccent_simples(a.nome)), '[^a-z]', '', 'g')
  ) > 0
order by 3 + 4 desc;
