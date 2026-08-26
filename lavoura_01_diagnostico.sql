-- ============================================================
-- DIAGNOSTICO ANTES DE SEPARAR CANA E CEREAIS
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- NAO ALTERA NADA. So le e mostra.
--
-- ------------------------------------------------------------
-- IMPORTANTE: RODE UMA CONSULTA DE CADA VEZ
--
-- O editor do Supabase mostra so o resultado da ULTIMA instrucao. Selecione
-- o bloco de uma consulta, rode, me mande o resultado, e passe para a
-- proxima. Sao 5.
--
-- ------------------------------------------------------------
-- POR QUE ESTE PASSO EXISTE
--
-- Ja errei tres vezes nesta migracao por supor como um campo funcionava em
-- vez de ler o dado. Antes de separar os apps eu preciso do estado REAL de
-- quatro coisas:
--
--   1. quais politicas de seguranca citam as permissoes que vou dividir
--   2. quais chaves de permissao existem hoje nos usuarios
--   3. se as receitas de lavoura estao ou nao no modelo unico
--   4. se cada fazenda e mesmo de uma frente so
--
-- O item 4 e a premissa que voce me deu. Se o dado contrariar, o filtro dos
-- apps novos tem que ser outro, e e melhor descobrir agora.
-- ============================================================


-- ------------------------------------------------------------
-- CONSULTA 1 - POLITICAS DE SEGURANCA QUE CITAM AS PERMISSOES
--
-- Vou dividir a permissao 'cadastros' em duas (uma por frente). Estas sao
-- as politicas que precisam ser reescritas junto. Preciso do texto exato:
-- reescrever a partir do arquivo de schema, que esta desatualizado, foi o
-- que causou os erros anteriores.
-- ------------------------------------------------------------
select
  tablename            as tabela,
  policyname           as politica,
  cmd                  as comando,
  coalesce(qual, '')       as condicao_leitura,
  coalesce(with_check, '') as condicao_escrita
from pg_policies
where schemaname = 'public'
  and (coalesce(qual, '') || coalesce(with_check, '')) ~
      '(cadastros|operacoes|financeiro|resultados)'
order by tablename, policyname;


-- ------------------------------------------------------------
-- CONSULTA 2 - CHAVES DE PERMISSAO EM USO HOJE
--
-- Mostra cada chave que aparece no cadastro de algum usuario, quantos
-- usuarios a tem e com qual nivel. E o inventario do que existe de verdade,
-- que pode nao bater com o que os apps oferecem na tela.
-- ------------------------------------------------------------
select
  chave,
  count(*)                                          as usuarios,
  count(*) filter (where nivel = 'editar')          as podem_editar,
  count(*) filter (where nivel = 'visualizar')      as so_visualizam
from (
  select p.id, k.chave, p.permissoes ->> k.chave as nivel
  from profiles p
  cross join lateral jsonb_object_keys(coalesce(p.permissoes, '{}'::jsonb)) as k(chave)
) t
group by chave
order by chave;


-- ------------------------------------------------------------
-- CONSULTA 3 - AS RECEITAS DE LAVOURA ESTAO NO MODELO UNICO?
--
-- Eu migrei despesas_cana e despesas_graos para lancamentos_financeiros,
-- mas NAO migrei receitas_cana nem receitas_graos. Se a coluna
-- no_modelo_unico vier zerada com linhas_legado maior que zero, esta
-- confirmado: a receita da lavoura so existe na tabela antiga.
--
-- Isso importa agora porque, ao tirar a tela de Receita dos apps de
-- lavoura, a receita ficaria sem lugar nenhum para ser lancada.
-- ------------------------------------------------------------
select 'receitas_cana'  as origem,
       (select count(*) from receitas_cana)  as linhas_legado,
       (select coalesce(sum(valor_total), 0) from receitas_cana) as total_legado,
       (select count(*) from lancamentos_financeiros
          where tipo = 'receita' and atividade = 'cana')         as no_modelo_unico
union all
select 'receitas_graos',
       (select count(*) from receitas_graos),
       (select coalesce(sum(valor_total), 0) from receitas_graos),
       (select count(*) from lancamentos_financeiros
          where tipo = 'receita' and atividade = 'graos');


-- ------------------------------------------------------------
-- CONSULTA 4 - CADA FAZENDA E DE UMA FRENTE SO?
--
-- Cruza tres fontes: as atividades declaradas da fazenda
-- (fazenda_atividades), a frente dos talhoes dela (que vem da cultura) e a
-- frente dos lancamentos financeiros.
--
-- COMO LER: a coluna conclusao tem que dizer 'uma frente so' em todas as
-- linhas. Se aparecer 'MISTURADA', me mande a linha: o filtro dos apps
-- novos vai precisar ser por talhao em vez de por fazenda.
-- ------------------------------------------------------------
with ativ as (
  select fazenda_id, string_agg(distinct atividade, ', ' order by atividade) as atividades_declaradas
  from fazenda_atividades where coalesce(area_ha, 0) > 0
  group by fazenda_id
),
tal as (
  select t.fazenda_id, string_agg(distinct c.frente, ', ' order by c.frente) as frentes_dos_talhoes
  from talhoes_areas t
  join culturas c on c.id = t.cultura_id
  where t.tipo = 'talhao' and t.cultura_id is not null
  group by t.fazenda_id
),
lan as (
  select fazenda_id, string_agg(distinct atividade, ', ' order by atividade) as frentes_lancamentos
  from lancamentos_financeiros
  where fazenda_id is not null and atividade in ('cana', 'graos')
  group by fazenda_id
)
select
  f.id, f.nome, f.estado,
  coalesce(a.atividades_declaradas, '-') as atividades_declaradas,
  coalesce(t.frentes_dos_talhoes,   '-') as frentes_dos_talhoes,
  coalesce(l.frentes_lancamentos,   '-') as frentes_lancamentos,
  case
    when coalesce(t.frentes_dos_talhoes, '') like '%,%'
      or coalesce(l.frentes_lancamentos, '') like '%,%'
    then 'MISTURADA'
    else 'uma frente so'
  end as conclusao
from fazendas f
left join ativ a on a.fazenda_id = f.id
left join tal  t on t.fazenda_id = f.id
left join lan  l on l.fazenda_id = f.id
order by f.nome;


-- ------------------------------------------------------------
-- CONSULTA 5 - CADASTROS SEM FRENTE DEFINIDA
--
-- Talhao sem cultura nao tem frente, entao nao apareceria em nenhum dos
-- dois apps novos: sumiria da tela sem aviso. O mesmo vale para centro de
-- custo com frente nula.
--
-- Volta vazio = nada some. Qualquer linha aqui e um cadastro que precisa
-- ser classificado ANTES da separacao.
-- ------------------------------------------------------------
select 'talhao sem cultura' as pendencia, t.id, t.nome,
       (select nome from fazendas where id = t.fazenda_id) as fazenda
from talhoes_areas t
where t.tipo = 'talhao' and coalesce(t.ativo, true) and t.cultura_id is null
union all
select 'centro de custo sem frente', c.id, c.nome,
       coalesce((select nome from fazendas where id = c.fazenda_id), 'Global')
from centros_custo c
where coalesce(c.ativo, true) and coalesce(trim(c.frente), '') = ''
union all
select 'safra sem cultura', s.id, s.nome, '-'
from safras s
where s.cultura_id is null
order by pendencia, nome;
