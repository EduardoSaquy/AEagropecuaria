-- ============================================================
-- APAGA O INVESTIMENTO DUPLICADO DA PECUARIA EM 2026
--
-- CONFERIDO: dos 7 titulos de investimento do ERP em 2026, 4 batem
-- exato (valor e mes) com um lancamento manual - mesmo criterio ja
-- usado e confirmado pra despesa/receita:
--   jan/2026 - um vendedor - R$ 144.524,71
--   jan/2026 - um vendedor - R$ 72.000,00
--   mar/2026 - um vendedor - R$ 5.800,00
--   jul/2026 - um vendedor - R$ 30.400,00
-- total: R$ 252.724,71
--
-- Os outros 3 titulos do ERP (dois pagamentos de um vendedor em jan - pareciam uma
-- compra parcelada -, e um de outro em ago) NAO tem par exato e ficam intocados -
-- pareciam investimento novo, nao duplicidade. (Revisto em 05/11/2026: aquele
-- pareamento era por mes; ver o CLAUDE.md.)
--
-- O QUE FAZ: apaga so os titulos do ERP que batem exato com um
-- lancamento manual (mesmo valor, mesmo mes) - mantem a versao lancada
-- a mao, mesma decisao ja tomada pra despesa/receita. NAO toca em
-- nenhum outro investimento, nem em Cana/Graos.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

delete from lancamentos_financeiros c
where c.atividade='pecuaria' and c.tipo='investimento' and c.erp_id is not null and c.mes >= '2026-01'
  and exists(
    select 1 from lancamentos_financeiros m
     where m.atividade='pecuaria' and m.tipo='investimento' and m.erp_id is null
       and m.mes = c.mes and round(m.valor,2) = round(c.valor,2)
  );

select 1::numeric as ordem, 'PECUARIA: investimento do ERP restante em 2026 (esperado: 3 titulos, R$ 209.999,99)' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='investimento' and erp_id is not null and mes >= '2026-01'
union all
select 2, 'PECUARIA: investimento lancado a mao em 2026 (nao muda)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='investimento' and erp_id is null and mes >= '2026-01'
order by ordem;
