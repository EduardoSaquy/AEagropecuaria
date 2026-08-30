-- ============================================================
-- SO LEITURA - investiga se o investimento da Pecuaria em 2026
-- (Conag x lancado a mao) e duplicidade de verdade, mesmo metodo usado
-- pra achar a duplicidade de despesa/receita: compara valor e mes exatos.
-- Nao muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

-- 1) os 7 titulos do Conag, um por linha, pra ver do que se trata
select 1::numeric as ordem, 'Conag: ' || c.mes || ' - ' || c.descricao as item,
       round(c.valor,2)::text as valor,
       case when exists(
         select 1 from lancamentos_financeiros m
          where m.atividade='pecuaria' and m.tipo='investimento' and m.conag_id is null
            and m.mes = c.mes and round(m.valor,2) = round(c.valor,2)
       ) then 'TEM par exato lancado a mao no mesmo mes - duplicidade provavel'
         else 'sem par exato - pode ser investimento novo' end as situacao
  from lancamentos_financeiros c
 where c.atividade='pecuaria' and c.tipo='investimento' and c.conag_id is not null and c.mes >= '2026-01'
 order by c.mes
