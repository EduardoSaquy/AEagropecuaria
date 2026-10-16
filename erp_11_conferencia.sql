-- ============================================================
-- ETAPA 2 DE 3: O QUE JA EXISTE, ANTES DE IMPORTAR NADA
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz), DEPOIS de carregar
-- o CSV em erp_staging.
--
-- So leitura. Nao insere, nao apaga, nao altera nada.
--
-- ------------------------------------------------------------
-- O PROBLEMA QUE ESTA CONSULTA RESOLVE
--
-- Os 2.760 lancamentos que ja estao no app vieram da migracao da pecuaria
-- e da cana - a mesma origem dos 9.400 do ERP. Importar por cima
-- duplicaria, e o total iria para R$ 73 milhoes sem que nada tivesse
-- acontecido.
--
-- Nenhum dos 2.760 tem erp_id, entao nao da para casar por chave. O
-- casamento e por SEMELHANCA: mesmo valor, mesmo fornecedor, data
-- proxima. Nao e prova - e suspeita, e por isso esta consulta so MOSTRA.
--
-- Quem decide o que fazer com cada suspeito e voce, na etapa 3.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='erp_staging') then
    raise exception 'erp_staging nao existe - rode o erp_10_estrutura primeiro';
  end if;
  if not exists (select 1 from erp_staging) then
    raise exception 'erp_staging esta vazia - carregue o CSV antes';
  end if;
end $$;

create extension if not exists unaccent;

create or replace function norm_txt(t text) returns text
language sql immutable as $$
  select upper(btrim(regexp_replace(unaccent(coalesce(t,'')), '[^[:alnum:]]+', ' ', 'g')));
$$;


with base as (
  select s.*,
         nullif(s.valor,'')::numeric               as v,
         nullif(s.vencimento,'')::date             as venc,
         norm_txt(s.entidade)                      as ent
  from erp_staging s
),
-- suspeito: mesmo valor e mesmo fornecedor, com data a menos de 40 dias.
-- A janela e larga de proposito: a data do ERP e o VENCIMENTO e a nossa
-- costuma ser a do pagamento ou da competencia. Larga demais gera falso
-- positivo; estreita demais deixa passar duplicata. 40 dias erra para o
-- lado de mostrar mais, que e o lado seguro numa consulta que so mostra.
suspeitos as (
  select b.erp_id, b.entidade, b.centro_custo, b.venc, b.v,
         l.id as nosso_id, l.descricao, l.data as nossa_data, l.fornecedor, l.atividade
  from base b
  join lancamentos_financeiros l
    on l.erp_id is null
   and l.valor = b.v
   and norm_txt(l.fornecedor) = b.ent
   and b.ent <> ''
   and l.data is not null
   and abs(l.data - b.venc) <= 40
)
select 1 as ordem, 'Lancamentos no app hoje' as item,
       count(*)::text as valor, 'nenhum tem erp_id' as detalhe
from lancamentos_financeiros
union all
select 2, 'Linhas no CSV', count(*)::text, 'esperado 9400' from erp_staging
union all
select 3, 'Valor total do CSV', round(sum(nullif(valor,'')::numeric),2)::text,
       'esperado 62609569.50' from erp_staging
union all
select 4, 'SUSPEITOS de ja existir', count(distinct erp_id)::text,
       'mesmo valor, mesmo fornecedor, ate 40 dias' from suspeitos
union all
select 5, 'Valor dos suspeitos',
       round(coalesce(sum(v),0),2)::text, 'nao seria importado'
from (select distinct erp_id, v from suspeitos) x
union all
select 6, 'Entrariam de fato',
       ((select count(*) from erp_staging) - (select count(distinct erp_id) from suspeitos))::text,
       'o resto do CSV'
union all
select 7, 'Valor que entraria',
       round((select sum(nullif(valor,'')::numeric) from erp_staging)
             - coalesce((select sum(v) from (select distinct erp_id, v from suspeitos) y),0), 2)::text,
       'somado ao que ja existe'
union all
select 8, 'Sem centro de custo correspondente',
       count(*)::text, 'precisam ser criados antes'
from (select distinct centro_custo from erp_staging) s
where not exists (select 1 from centros_custo c where norm_txt(c.nome) = norm_txt(s.centro_custo))
union all
select 9, 'Sem entidade correspondente',
       count(*)::text, 'serao criadas na importacao'
from (select distinct entidade from erp_staging where entidade <> '') s
where not exists (select 1 from entidades e where norm_txt(e.nome) = norm_txt(s.entidade))
union all
select 10, 'Fazendas do ERP sem par aqui',
       count(*)::text, 'precisam ser criadas antes'
from (select distinct fazenda_erp from erp_staging where fazenda_erp <> '') s
where not exists (select 1 from fazendas f
                  where norm_txt(f.nome) = norm_txt(s.fazenda_erp)
                     or norm_txt(f.nome) = norm_txt(replace(s.fazenda_erp,'FAZENDA ','')))
order by ordem;
