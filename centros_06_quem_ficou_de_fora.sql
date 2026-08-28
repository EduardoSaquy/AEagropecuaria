-- ============================================================
-- OS 23 QUE NAO ESTAO NA ARVORE DO CONAG
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). SO LE, nao grava nada.
--
-- ------------------------------------------------------------
-- POR QUE ISSO IMPORTA AGORA
--
-- O centros_05 confirmou a hipotese: 63 dos 64 centros estao no nivel 3,
-- e 93 das 96 contas do Conag ainda nao existem aqui. Ate ai, esperado.
--
-- O que precisa de olho sao os 23 que nao acharam par nenhum na arvore.
-- Cada um deles e uma de duas coisas:
--
--   a) conta nossa mesmo, que o Conag nao tem. Fica como esta.
--   b) a MESMA conta deles, escrita diferente. Se for esse o caso e eu nao
--      pegar agora, o conag_12 vai criar a versao do Conag ao lado da
--      nossa - dois centros para a mesma coisa, os 2.760 lancamentos
--      antigos num e os 9.400 novos no outro. Exatamente o problema que
--      este trabalho todo existe para evitar.
--
-- Esta consulta poe cada um dos 23 ao lado do nome MAIS PARECIDO da arvore,
-- com o quanto ja foi lancado nele. Nome parecido com valor alto dos dois
-- lados e candidato a fusao; nome parecido com valor zero e coincidencia.
--
-- pg_trgm compara por trigrama - pedaco de tres letras. Aguenta abreviacao,
-- plural e ordem trocada, que e onde o unaccent do centros_05 nao chega.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
end $$;

create extension if not exists pg_trgm;

with fora as (
  select c.id, c.nome, c.tipo, c.subcategoria
    from centros_custo c
   where not exists (select 1 from conag_plano_contas p
                      where plano_norm(p.classe) = plano_norm(c.nome)
                         or plano_norm(p.conta)  = plano_norm(c.nome))
),
uso as (
  select centro_custo_id, count(*) as qtd, coalesce(sum(valor),0) as total
    from lancamentos_financeiros group by centro_custo_id
),
parecido as (
  select f.id,
         p.conta   as candidato,
         p.classe  as classe_do_candidato,
         round(similarity(plano_norm(f.nome), plano_norm(p.conta))::numeric, 2) as parecenca,
         row_number() over (partition by f.id
                            order by similarity(plano_norm(f.nome), plano_norm(p.conta)) desc,
                                     p.conta) as rn
    from fora f
    cross join conag_plano_contas p
)
select f.nome                                as centro_nosso,
       coalesce(u.qtd, 0)::text              as lancamentos,
       to_char(coalesce(u.total, 0), 'FM999G999G990D00') as ja_lancado,
       coalesce(f.tipo, '(sem tipo)')        as tipo,
       coalesce(pa.candidato, '(nenhum)')    as parecido_no_conag,
       coalesce(pa.parecenca, 0)::text       as parecenca,
       case
         when pa.parecenca >= 0.60 then 'OLHAR - provavel a mesma conta'
         when pa.parecenca >= 0.35 then 'talvez'
         else 'nossa mesmo, o Conag nao tem'
       end                                   as veredito
  from fora f
  left join uso u        on u.centro_custo_id = f.id
  left join parecido pa  on pa.id = f.id and pa.rn = 1
 order by pa.parecenca desc nulls last, coalesce(u.total, 0) desc;
