-- ============================================================
-- ALEMAR: as duas parcelas do ERP (#22173 e #22307) passam do centro de GIRO para o de MATRIZ
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode. SO RODE SE O ELE CONFIRMAR.
--
-- CONTEXTO: o Eduardo disse (06/11/2026) que a compra do Alemar e de MATRIZES e que nao foi paga com dinheiro do custeio.
-- Ela tem tres pagamentos: #508 (R$ 30.400,00, lancado a mao, ja no centro de matriz), #22173 (R$ 30.400,00, ERP 5986,
-- vence 18/08/2026) e #22307 (R$ 25.900,00, ERP 6304, vence 10/09/2026). Os dois do ERP entraram no centro de GIRO (#99), que
-- e como o ERP os classificou. Este script passa os dois para o centro de matriz (#122).
-- So muda o centro de custo. Guarda o centro atual em zz_backup_alemar_matriz_2026_11_06 (fechada). Rodar de novo recusa.
--
-- GUARDAS (tudo ou nada): os dois precisam estar exatamente como na conferencia (investimento, valores certos, no centro #99,
-- fornecedor Alemar) e os centros #99 e #122 precisam ter os nomes certos.
--
-- PARA DESFAZER:
--   update lancamentos_financeiros l set centro_custo_id = b.centro_custo_id from zz_backup_alemar_matriz_2026_11_06 b where b.id = l.id;
-- ============================================================
do $alemar$
declare
  n int;
  atualizadas int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_alemar_matriz_2026_11_06') is not null then
    raise exception 'Este script ja rodou (a copia zz_backup_alemar_matriz_2026_11_06 existe). Nao mexo em nada.';
  end if;

  select count(*) into n from centros_custo
   where (id = 99 and translate(upper(btrim(nome)), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') = 'COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE')
      or (id = 122 and translate(upper(btrim(nome)), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') = 'COMPRA DE MATRIZES PARA REPRODUCAO');
  if n <> 2 then
    raise exception 'Os centros #99 (giro) e #122 (matriz) nao estao com os nomes esperados. Nao mexo em nada.';
  end if;

  select count(*) into n from lancamentos_financeiros l
   where l.tipo = 'investimento' and l.centro_custo_id = 99 and l.fornecedor ilike '%ALEMAR%'
     and ((l.id = 22173 and l.valor = 30400.00) or (l.id = 22307 and l.valor = 25900.00));
  if n <> 2 then
    raise exception 'Achei % dos 2 lancamentos (#22173 R$ 30.400,00 e #22307 R$ 25.900,00, do Alemar, no centro #99). Nao mexo em nada.', n;
  end if;

  create table zz_backup_alemar_matriz_2026_11_06 as select id, centro_custo_id from lancamentos_financeiros where id in (22173, 22307);
  alter table zz_backup_alemar_matriz_2026_11_06 enable row level security;
  revoke all on zz_backup_alemar_matriz_2026_11_06 from anon, authenticated;

  update lancamentos_financeiros set centro_custo_id = 122 where id in (22173, 22307);
  get diagnostics atualizadas = row_count;
  if atualizadas <> 2 then
    raise exception 'Atualizei % lancamento(s), esperava 2. Desfeito.', atualizadas;
  end if;
end
$alemar$;

select '#' || l.id || ' ' || coalesce(to_char(coalesce(l.data, l.vencimento), 'DD/MM/YYYY'), '?') as item,
       'R$ ' || round(l.valor, 2)::text || ' | ' || coalesce(l.fornecedor, '') as valor,
       'centro agora: #' || c.id || ' ' || c.nome as situacao
  from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
 where l.id in (508, 22173, 22307) order by l.id;
