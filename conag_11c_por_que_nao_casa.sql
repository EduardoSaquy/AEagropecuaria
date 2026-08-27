-- ============================================================
-- POR QUE OS CENTROS DE CUSTO NAO ESTAO CASANDO
--
-- So leitura.
--
-- A conferencia acusou 127 dos 129 centros do CSV sem par - mas nosso
-- plano de contas VEIO do Conag, entao quase tudo deveria casar. E as
-- entidades casaram (126 das nossas 129), o que mostra que a comparacao
-- por nome funciona.
--
-- Esta consulta poe os dois lados lado a lado para eu ver onde diverge.
-- ============================================================

do $$
begin
  if not exists (select 1 from conag_staging) then
    raise exception 'conag_staging vazia';
  end if;
end $$;

-- tira o sufixo "(Contrato: XXX)": 44 nomes do CSV o trazem colado, e nao
-- sao contas diferentes - e a mesma conta com o numero do contrato junto.
create or replace function conta_base(t text) returns text
language sql immutable as $$
  select btrim(regexp_replace(coalesce(t,''), '\s*\(Contrato:.*$', ''));
$$;

select 1 as ordem, 'Centros no nosso banco' as item, count(*)::text as valor, '' as extra
from centros_custo
union all
select 2, 'Centros distintos no CSV', count(distinct centro_custo)::text, ''
from conag_staging
union all
select 3, 'Centros distintos SEM o sufixo de contrato',
       count(distinct conta_base(centro_custo))::text, 'os 44 com (Contrato: ) colapsam'
from conag_staging
union all
select 4, 'Casam ignorando o sufixo', count(*)::text, ''
from (select distinct conta_base(centro_custo) as n from conag_staging) s
where exists (select 1 from centros_custo c where norm_txt(c.nome) = norm_txt(s.n))
union all
select 5, 'NAO casam', count(*)::text, ''
from (select distinct conta_base(centro_custo) as n from conag_staging) s
where not exists (select 1 from centros_custo c where norm_txt(c.nome) = norm_txt(s.n))
union all
-- os 12 nossos, para eu ver como estao escritos
select 6, 'NOSSO: ' || nome, coalesce(subcategoria,'sem grupo'), coalesce(tipo,'sem tipo')
from (select nome, subcategoria, tipo from centros_custo order by nome limit 12) x
union all
-- os 12 mais usados do CSV que nao casam
select 7, 'CSV SEM PAR: ' || n, quantos::text, 'R$ ' || round(total,2)::text
from (
  select conta_base(centro_custo) as n, count(*) as quantos,
         sum(nullif(valor,'')::numeric) as total
  from conag_staging s
  where not exists (select 1 from centros_custo c
                    where norm_txt(c.nome) = norm_txt(conta_base(s.centro_custo)))
  group by 1 order by 3 desc limit 12
) y
order by ordem, item;
