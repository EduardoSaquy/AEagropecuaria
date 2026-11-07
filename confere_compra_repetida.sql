-- ============================================================
-- CONFERE UMA POSSIVEL COMPRA LANCADA DUAS VEZES (parcelas ou duplicata?)
--
-- SOMENTE LEITURA. Nao altera nada. RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- Cole inteiro, rode e mande o resultado.
--
-- CASO: R$ 30.400,00 do mesmo vendedor lancados duas vezes em 2026, um a mao (#508, 13/07/2026) e um
-- importado do ERP (#22173, 18/08/2026), mais um terceiro importado de R$ 25.900,00 (#22307, 10/09/2026).
-- Se forem parcelas de uma compra, os tres valem. Se for a mesma compra, um sai.
--
-- MOSTRA tudo que ha de 2025 em diante nos lancamentos desse vendedor (e de quem tem o mesmo valor no
-- mesmo periodo): data, vencimento, valor, centro, quem lancou, o texto do lancamento e a observacao
-- (onde o ERP escreve o documento). O Eduardo compara com o extrato do banco.
-- ============================================================
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

select '#' || f.id || ' ' || coalesce(to_char(f.data, 'DD/MM/YYYY'), 'sem data')
         || case when f.vencimento is not null then ' (venc. ' || to_char(f.vencimento, 'DD/MM/YYYY') || ')' else '' end as item,
       'R$ ' || round(f.valor, 2)::text || ' | ' || f.tipo || ' | ' || left(coalesce(c.nome, '(sem centro)'), 40) as valor,
       case when f.erp_id is not null then 'importacao' when f.criado_por like 'ERP (acerto%' then 'acerto' else 'a mao' end
         || ' | ' || left(coalesce(nullif(btrim(f.fornecedor), ''), '(sem fornecedor)'), 30)
         || ' | ' || left(coalesce(f.descricao, ''), 40)
         || ' | obs: ' || left(coalesce(f.observacao, ''), 70) as situacao
  from lancamentos_financeiros f
  left join centros_custo c on c.id = f.centro_custo_id
 where coalesce(f.data, f.vencimento) >= date '2025-01-01'
   and (f.fornecedor ilike '%ALEMAR%' or f.descricao ilike '%ALEMAR%' or f.id in (508, 22173, 22307))
 order by coalesce(f.data, f.vencimento), f.id;
