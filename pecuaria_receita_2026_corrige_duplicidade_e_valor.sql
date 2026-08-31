-- ============================================================
-- AE Pecuária — corrige receita 2026: remove duplicidade do Conag
-- (mantendo a versão lançada à mão) e corrige um valor errado.
--
-- Baseado na conferência do relatório "ERP Conag - Painel de
-- Resultado - DRE / Contas a Receber - Ano 2026" enviado pelo usuário
-- contra o que já estava em lancamentos_financeiros.
--
-- NÃO MEXE no id 22802 (Conag, R$ 51.301,85, 01/07/2026) — não bate
-- com nenhum item do relatório e a origem ainda não foi confirmada.
-- Deixa como está até você confirmar o que é.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='lancamentos_financeiros') then
    raise exception 'PROJETO ERRADO — esta tabela nao existe aqui.';
  end if;
end $$;

-- 1. Remove os 4 duplicados do Conag (a versão lançada à mão, com o
--    mesmo valor, já existe e fica mantida).
delete from lancamentos_financeiros
where id in (22830, 22804, 22805, 22803);

-- 2. Corrige o valor do id 488 — estava R$ 90.219,00, o relatório
--    (item 193) e a importação do Conag (id 22801, que será apagado
--    a seguir) confirmam que o valor certo é R$ 88.742,22.
update lancamentos_financeiros
set valor = 88742.22
where id = 488;

-- 3. Remove o duplicado do Conag pra esse mesmo lançamento (id 488
--    já corrigido acima cobre o valor certo).
delete from lancamentos_financeiros
where id = 22801;

-- 4. Conferência: receita da Pecuária em 2026 antes e depois.
select 'PECUARIA: receita 2026 total depois da correção' as item,
       count(*)::text as qtd, round(sum(valor),2)::text as valor
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='receita' and mes like '2026%'
union all
select 'PECUARIA: linhas do Conag (conag_id preenchido) restantes em 2026 (deve sobrar só a 22802, ainda não resolvida)',
       count(*)::text, round(sum(valor),2)::text
  from lancamentos_financeiros
 where atividade='pecuaria' and tipo='receita' and mes like '2026%' and conag_id is not null;
