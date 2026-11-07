-- ============================================================
-- COMPRA DE ANIMAIS, passo 2: os lotes (para ligar cada compra ao seu lote)
--
-- SOMENTE LEITURA. Nao altera nada. RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- Cole inteiro, rode e mande o resultado.
--
-- PARA QUE SERVE: nenhuma compra de animais tem lote nem numero de cabecas. Para o app contar o
-- custo dos animais quando o lote e vendido (resultado economico), cada compra precisa de um lote e
-- de uma quantidade. Esta consulta mostra, para cada lote, quando comecou e terminou, quantos
-- animais tem hoje, quantos ja foram vendidos (e por quanto) e a primeira pesagem. Com isso e a lista
-- de compras, o Claude propoe a ligacao e o Eduardo so confere.
-- ============================================================
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

with
vendas as (
  select a.lote_id,
         count(*) as n_vendas,
         sum(a.quantidade) as vendidos,
         min(a.data) as primeira_venda,
         max(a.data) as ultima_venda,
         coalesce(sum((select sum(f.valor) from lancamentos_financeiros f where f.abate_id = a.id)), 0) as receita
    from abates a
   group by a.lote_id
),
pesos as (
  select distinct on (p.lote_id) p.lote_id, p.data as data_peso, p.peso_medio_kg
    from pesagens p
   order by p.lote_id, p.data, p.id
),
compras as (
  select f.lote_id, count(*) as n_compras, sum(f.valor) as valor_compras, sum(f.quantidade) as cab_compras
    from lancamentos_financeiros f
   where f.lote_id is not null and f.tipo = 'investimento'
   group by f.lote_id
)
select
  'Lote #' || lo.id || ' ' || left(coalesce(lo.nome, '?'), 40) as item,
  'inicio ' || coalesce(to_char(lo.data_inicio, 'DD/MM/YYYY'), '?')
    || ' | fim ' || coalesce(to_char(lo.data_fim, 'DD/MM/YYYY'), 'em andamento')
    || ' | ' || coalesce(lo.destino, '?') || ' ' || coalesce(lo.sexo, '') as valor,
  'hoje ' || coalesce(lo.numero_animais, 0)::text || ' animais'
    || ' | vendidos ' || coalesce(v.vendidos, 0)::text || ' em ' || coalesce(v.n_vendas, 0)::text || ' venda(s)'
    || case when v.primeira_venda is not null
            then ' (' || to_char(v.primeira_venda, 'DD/MM/YYYY') || ' a ' || to_char(v.ultima_venda, 'DD/MM/YYYY') || ')' else '' end
    || ' | receita R$ ' || round(coalesce(v.receita, 0), 2)::text
    || ' | 1a pesagem ' || case when p.data_peso is null then 'nenhuma'
                                else to_char(p.data_peso, 'DD/MM/YYYY') || ' ' || round(p.peso_medio_kg, 0)::text || ' kg' end
    || case when c.n_compras is not null
            then ' | compras ligadas ' || c.n_compras::text || ' R$ ' || round(c.valor_compras, 2)::text else '' end as situacao
  from lotes lo
  left join vendas v on v.lote_id = lo.id
  left join pesos p on p.lote_id = lo.id
  left join compras c on c.lote_id = lo.id
 order by lo.data_inicio nulls last, lo.id;
