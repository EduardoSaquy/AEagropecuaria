-- ============================================================
-- CONFERENCIA (SO LEITURA): lancamentos que parecem lancados duas vezes
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- Procura, de maio/2026 em diante (despesa e investimento), lancamentos com o MESMO
-- fornecedor, o MESMO valor e o MESMO mes. Repeticao assim pode ser legitima (duas
-- compras iguais no mesmo mes) ou duplicidade; quem decide e quem conhece a conta.
-- Pistas para decidir: se um veio do ERP e o outro foi lancado a mao ("ERP x lancado a
-- mao"), ou se os dois vieram do ERP com codigos de documento diferentes (a observacao
-- guarda o codigo), e se os vencimentos sao diferentes.
-- A mesma conta em MESES diferentes (parcelas) nao entra: e o normal de uma parcela.
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
base as (
  select l.id, l.tipo, l.mes, l.vencimento, l.valor, l.erp_id, l.criado_por, l.observacao,
         coalesce(cc.nome, '(sem centro de custo)') as centro,
         coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '(sem nome)') as fornecedor,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(l.fornecedor), ''), l.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm
    from lancamentos_financeiros l
    left join centros_custo cc on cc.id = l.centro_custo_id
   where l.valor > 0 and l.mes >= '2026-05' and l.tipo in ('despesa', 'investimento')
),
grupos as (
  select tipo, forn_norm, mes, valor,
         count(*) as n,
         count(*) filter (where erp_id is not null) as n_erp,
         count(*) filter (where erp_id is null) as n_manual,
         min(fornecedor) as fornecedor, min(centro) as centro,
         string_agg(id::text, ', ' order by id) as ids,
         string_agg(coalesce(to_char(vencimento, 'DD/MM'), '-'), ', ' order by id) as vencimentos,
         string_agg(coalesce(nullif(substring(observacao from '^ERP [0-9]+'), ''), '-'), ', ' order by id) as documentos,
         string_agg(coalesce(criado_por, '-'), ', ' order by id) as quem
    from base
   group by tipo, forn_norm, mes, valor
  having count(*) > 1
)
select case when n_erp > 0 and n_manual > 0 then '1) ERP x lancado a mao'
            when n_manual = 0 then '2) so do ERP'
            else '3) so lancado a mao' end as tipo_de_repeticao,
       centro as centro_de_custo, fornecedor, mes, valor, n as vezes,
       round(valor * (n - 1), 2) as possivel_excesso, ids, vencimentos, documentos, quem
  from grupos
 order by 1, valor * (n - 1) desc, fornecedor;
