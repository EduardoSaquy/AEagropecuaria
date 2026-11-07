-- ============================================================
-- O QUE DIZ O TEXTO DE CADA COMPRA (matriz ou recria/engorda?)
--
-- SOMENTE LEITURA. Nao altera nada. RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- Cole inteiro, rode e mande o resultado.
--
-- Mostra as 8 compras lancadas a mao que a classificacao do dia 06/11/2026 moveu e as duas do ERP do Alemar:
-- o texto de cada uma (descricao e observacao) e o centro em que ficou. Serve para conferir se o centro bate com o
-- que o proprio lancamento diz.
-- ============================================================
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

select '#' || f.id || ' ' || coalesce(to_char(coalesce(f.data, f.vencimento), 'DD/MM/YYYY'), 'sem data') as item,
       'R$ ' || round(f.valor, 2)::text || ' | ' || left(coalesce(nullif(btrim(f.fornecedor), ''), '(sem fornecedor)'), 30) as valor,
       'centro: ' || left(coalesce(c.nome, '(sem centro)'), 44)
         || ' | texto: ' || left(coalesce(f.descricao, ''), 60)
         || ' | obs: ' || left(coalesce(f.observacao, ''), 50) as situacao
  from lancamentos_financeiros f
  left join centros_custo c on c.id = f.centro_custo_id
 where f.id in (490, 491, 492, 494, 496, 497, 502, 508, 22173, 22307)
 order by f.id;
