-- ============================================================
-- MOVIMENTOS DE FINANCIAMENTO (entrada de emprestimo e amortizacao)
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode de uma vez. Pode rodar mais de uma vez sem problema
-- (tudo usa IF NOT EXISTS / ON CONFLICT / DROP ... IF EXISTS), inclusive por
-- cima da versao anterior deste script (acrescenta a coluna `contrato`
-- e troca o numero real do contrato pelo apelido).
--
-- ------------------------------------------------------------
-- POR QUE UMA TABELA PROPRIA
--
-- Amortizar o principal nao e despesa (e divida saindo) e receber um
-- emprestimo nao e receita (e divida entrando). Por isso o import do ERP
-- deixou de fora os 75 titulos de AMORTIZACAO DE FINANCIAMENTO (R$ 17,8
-- milhoes) -- certo para o resultado, mas o fluxo de caixa da empresa ficou
-- sem a maior saida de caixa do periodo, e a divida a vencer ficou invisivel.
--
-- Esta tabela guarda esses movimentos SEM mexer em lancamentos_financeiros
-- (nenhum resultado, relatorio ou balancete existente muda). Quem le e a aba
-- Resultados > Empresa do AE Matriz.
--
-- Data no passado ou hoje = fluxo de caixa realizado. Data no futuro =
-- divida a vencer (so principal; os juros futuros nao estao no ERP).
--
-- ------------------------------------------------------------
-- QUANDO VOCE LANCAR UM CONTRATO NO MODULO FINANCIAMENTOS
--
-- Nao apague nada. Em Financiamentos, a lista "Divida do ERP ainda sem
-- contrato" tem um botao "Lancar contrato" por contrato: o app cria o
-- financiamento com as parcelas reais do ERP e grava aqui, em
-- financiamento_id, qual contrato assumiu cada linha. Linha assumida deixa de
-- contar nesta tabela (a divida e o fluxo passam a vir do contrato), entao
-- nada aparece duas vezes. Se o contrato for cancelado ou apagado, as linhas
-- voltam a valer sozinhas.
--
-- O ERP NAO tem entrada de emprestimo (so a amortizacao), entao so o
-- pagamento do principal e importado. 67 dos 75 titulos trazem o contrato (coluna
-- `contrato`); os outros se agrupam pelo valor da parcela.
--
-- O numero real do contrato NAO entra aqui: este repositorio e publico. Cada
-- contrato recebe um apelido C01, C02... pela ordem do 1o pagamento. Quem rodou
-- a versao antiga (com o numero real) roda este script de novo, ou so o
-- financiamentos_03_apelidos_contratos.sql: os dois trocam o numero pelo apelido.
-- ============================================================

-- ------------------------------------------------------------
-- 0) TRAVA DE PROJETO
-- ------------------------------------------------------------
do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'financiamentos') then
    raise exception 'Rode antes o financiamentos_01_criar_modulo.sql.';
  end if;
end
$trava$;

-- ------------------------------------------------------------
-- 1) TABELA
-- ------------------------------------------------------------
create table if not exists movimentos_financiamento (
  id               bigint generated always as identity primary key,
  data             date not null,
  tipo             text not null check (tipo in ('entrada','amortizacao')),
  valor            numeric(14,2) not null check (valor > 0),
  credor           text,
  -- apelido do contrato (C01, C02...), nunca o numero real; pode ser nulo
  contrato         text,
  descricao        text,
  origem           text not null default 'manual' check (origem in ('manual','erp')),
  -- id do titulo no ERP: impede importar a mesma linha duas vezes
  erp_id         bigint unique,
  -- contrato do modulo Financiamentos que assumiu esta linha (nulo = ainda vale aqui)
  financiamento_id bigint references financiamentos(id) on delete set null,
  created_at       timestamptz not null default now(),
  created_by       uuid default auth.uid()
);

-- quem ja rodou a versao anterior deste script (sem contrato, sem on delete set null)
alter table movimentos_financiamento add column if not exists contrato text;
alter table movimentos_financiamento
  drop constraint if exists movimentos_financiamento_financiamento_id_fkey;
alter table movimentos_financiamento
  add constraint movimentos_financiamento_financiamento_id_fkey
  foreign key (financiamento_id) references financiamentos(id) on delete set null;

create index if not exists idx_mov_fin_data on movimentos_financiamento (data);

-- ------------------------------------------------------------
-- 2) RLS
-- Quem ve Resultados ou Financiamentos ve os movimentos (entram no fluxo de
-- caixa da empresa); so quem edita Financiamentos grava.
-- ------------------------------------------------------------
alter table movimentos_financiamento enable row level security;

drop policy if exists "ve movimentos financiamento" on movimentos_financiamento;
create policy "ve movimentos financiamento" on movimentos_financiamento
  for select using (is_admin()
    or tem_permissao('matriz_financiamentos','visualizar')
    or tem_permissao('matriz_resultados','visualizar'));
drop policy if exists "lanca movimento financiamento" on movimentos_financiamento;
create policy "lanca movimento financiamento" on movimentos_financiamento
  for insert with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "edita movimento financiamento" on movimentos_financiamento;
create policy "edita movimento financiamento" on movimentos_financiamento
  for update using (is_admin() or tem_permissao('matriz_financiamentos','editar'))
          with check (is_admin() or tem_permissao('matriz_financiamentos','editar'));
drop policy if exists "exclui movimento financiamento" on movimentos_financiamento;
create policy "exclui movimento financiamento" on movimentos_financiamento
  for delete using (is_admin() or tem_permissao('matriz_financiamentos','editar'));

-- ------------------------------------------------------------
-- 3) IMPORTACAO DO ERP: 75 titulos de amortizacao
-- (75 titulos, total R$ 17.829.159,91; credor "BANCO BRASIL" unificado em "BANCO DO BRASIL")
-- Vencimento = data do movimento. Rodar de novo atualiza so o apelido do contrato:
-- nao desfaz o vinculo (financiamento_id) de quem ja foi lancado no modulo.
-- ------------------------------------------------------------
insert into movimentos_financiamento (data, tipo, valor, credor, contrato, descricao, origem, erp_id)
values
  ('2023-03-15', 'amortizacao', 6287.14, 'BANCO DO BRASIL', 'C01', 'Amortizacao de financiamento (importado do ERP)', 'erp', 434),
  ('2023-05-11', 'amortizacao', 3672989.65, 'BANCO DA AMAZONIA BASA', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 797),
  ('2023-05-15', 'amortizacao', 104986.00, 'SICOOB COCRED', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 813),
  ('2023-05-15', 'amortizacao', 74571.43, 'BANCO DO BRASIL', 'C02', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1417),
  ('2023-06-15', 'amortizacao', 3760.00, 'BANCO DO BRASIL', 'C03', 'Amortizacao de financiamento (importado do ERP)', 'erp', 911),
  ('2023-06-15', 'amortizacao', 12200.00, 'BANCO DO BRASIL', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 1196),
  ('2023-06-15', 'amortizacao', 2030.00, 'BANCO DO BRASIL', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 1198),
  ('2023-06-15', 'amortizacao', 2030.00, 'BANCO DO BRASIL', 'C04', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1370),
  ('2023-06-15', 'amortizacao', 9231.43, 'BANCO DO BRASIL', 'C05', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1387),
  ('2023-06-28', 'amortizacao', 210000.00, 'BANCO DO BRASIL', 'C06', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1326),
  ('2023-06-28', 'amortizacao', 125000.00, 'BANCO DO BRASIL', 'C07', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1540),
  ('2023-07-14', 'amortizacao', 735944.88, 'BANCO DO BRASIL', 'C08', 'Amortizacao de financiamento (importado do ERP)', 'erp', 467),
  ('2023-07-17', 'amortizacao', 12142.86, 'BANCO DO BRASIL', 'C09', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1357),
  ('2023-07-20', 'amortizacao', 299826.91, 'BANCO DO BRASIL', 'C10', 'Amortizacao de financiamento (importado do ERP)', 'erp', 330),
  ('2023-07-28', 'amortizacao', 210000.00, 'BANCO DO BRASIL', 'C06', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1327),
  ('2023-07-28', 'amortizacao', 125000.00, 'BANCO DO BRASIL', 'C07', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1541),
  ('2023-08-02', 'amortizacao', 1000000.00, 'BANCO DO BRASIL', 'C11', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1331),
  ('2023-08-15', 'amortizacao', 41840.96, 'BANCO DO BRASIL', 'C12', 'Amortizacao de financiamento (importado do ERP)', 'erp', 525),
  ('2023-08-15', 'amortizacao', 187500.00, 'BANCO DO BRASIL', 'C13', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1335),
  ('2023-08-28', 'amortizacao', 210000.00, 'BANCO DO BRASIL', 'C06', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1328),
  ('2023-08-28', 'amortizacao', 125000.00, 'BANCO DO BRASIL', 'C07', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1542),
  ('2023-09-11', 'amortizacao', 600000.00, 'BANCO DO BRASIL', 'C14', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1332),
  ('2023-09-28', 'amortizacao', 210000.00, 'BANCO DO BRASIL', 'C06', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1329),
  ('2023-09-28', 'amortizacao', 125000.00, 'BANCO DO BRASIL', 'C07', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1543),
  ('2023-10-16', 'amortizacao', 187500.00, 'BANCO DO BRASIL', 'C15', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1290),
  ('2023-10-16', 'amortizacao', 37939.47, 'BANCO DO BRASIL', 'C16', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1299),
  ('2023-11-16', 'amortizacao', 84306.47, 'BANCO DO BRASIL', 'C17', 'Amortizacao de financiamento (importado do ERP)', 'erp', 552),
  ('2023-12-15', 'amortizacao', 308900.59, 'BANCO DO BRASIL', 'C18', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1396),
  ('2024-03-15', 'amortizacao', 6287.14, 'BANCO DO BRASIL', 'C01', 'Amortizacao de financiamento (importado do ERP)', 'erp', 498),
  ('2024-05-15', 'amortizacao', 9231.43, 'BANCO DO BRASIL', 'C05', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1388),
  ('2024-05-15', 'amortizacao', 74571.43, 'BANCO DO BRASIL', 'C02', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1425),
  ('2024-06-17', 'amortizacao', 3930.15, 'BANCO DO BRASIL', 'C03', 'Amortizacao de financiamento (importado do ERP)', 'erp', 912),
  ('2024-06-17', 'amortizacao', 2121.86, 'BANCO DO BRASIL', 'C04', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1381),
  ('2024-06-27', 'amortizacao', 165000.00, 'BANCO DO BRASIL', 'C19', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1125),
  ('2024-07-15', 'amortizacao', 12142.86, 'BANCO DO BRASIL', 'C09', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1548),
  ('2024-07-19', 'amortizacao', 165000.00, 'BANCO DO BRASIL', 'C19', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1126),
  ('2024-07-19', 'amortizacao', 200000.00, 'BANCO DO BRASIL', 'C20', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1129),
  ('2024-08-20', 'amortizacao', 300000.10, 'BANCO DO BRASIL', 'C21', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1695),
  ('2024-08-26', 'amortizacao', 600000.39, 'BANCO DO BRASIL', 'C22', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1696),
  ('2024-08-29', 'amortizacao', 41840.96, 'BANCO DO BRASIL', 'C12', 'Amortizacao de financiamento (importado do ERP)', 'erp', 526),
  ('2024-08-29', 'amortizacao', 165000.00, 'BANCO DO BRASIL', 'C19', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1127),
  ('2024-08-29', 'amortizacao', 187500.00, 'BANCO DO BRASIL', 'C13', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1336),
  ('2024-10-04', 'amortizacao', 165000.00, 'BANCO DO BRASIL', 'C19', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1128),
  ('2024-10-15', 'amortizacao', 187500.00, 'BANCO DO BRASIL', 'C15', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1291),
  ('2024-11-18', 'amortizacao', 84306.47, 'BANCO DO BRASIL', 'C17', 'Amortizacao de financiamento (importado do ERP)', 'erp', 553),
  ('2024-11-21', 'amortizacao', 37939.47, 'BANCO DO BRASIL', 'C16', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1300),
  ('2024-12-16', 'amortizacao', 308900.59, 'BANCO DO BRASIL', 'C18', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1397),
  ('2025-05-15', 'amortizacao', 74571.43, 'BANCO DO BRASIL', 'C02', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1426),
  ('2025-07-15', 'amortizacao', 12142.86, 'BANCO DO BRASIL', 'C09', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1549),
  ('2025-08-15', 'amortizacao', 41840.96, 'BANCO DO BRASIL', 'C12', 'Amortizacao de financiamento (importado do ERP)', 'erp', 527),
  ('2025-08-15', 'amortizacao', 187500.00, 'BANCO DO BRASIL', 'C13', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1337),
  ('2025-10-15', 'amortizacao', 270632.00, 'BANCO DO BRASIL', 'C15', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1292),
  ('2025-10-15', 'amortizacao', 103835.00, 'BANCO DO BRASIL', 'C16', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1301),
  ('2025-11-17', 'amortizacao', 84306.47, 'BANCO DO BRASIL', 'C17', 'Amortizacao de financiamento (importado do ERP)', 'erp', 554),
  ('2025-12-15', 'amortizacao', 308900.59, 'BANCO DO BRASIL', 'C18', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1398),
  ('2026-03-17', 'amortizacao', 6287.14, 'BANCO DO BRASIL', 'C01', 'Amortizacao de financiamento (importado do ERP)', 'erp', 500),
  ('2026-08-03', 'amortizacao', 12142.86, 'BANCO DO BRASIL', 'C09', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1550),
  ('2026-08-19', 'amortizacao', 128571.43, 'BANCO DO BRASIL', 'C13', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1338),
  ('2026-08-19', 'amortizacao', 456737.72, 'BANCO DO BRASIL', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 10001),
  ('2026-10-15', 'amortizacao', 354064.10, 'BANCO DO BRASIL', 'C15', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1293),
  ('2026-10-15', 'amortizacao', 60334.75, 'BANCO DO BRASIL', 'C16', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1302),
  ('2026-11-16', 'amortizacao', 136004.85, 'BANCO DO BRASIL', 'C17', 'Amortizacao de financiamento (importado do ERP)', 'erp', 555),
  ('2026-12-15', 'amortizacao', 394620.50, 'BANCO DO BRASIL', 'C18', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1399),
  ('2027-07-15', 'amortizacao', 13261.37, 'BANCO DO BRASIL', 'C09', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1551),
  ('2027-08-15', 'amortizacao', 456737.72, 'BANCO DO BRASIL', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 10002),
  ('2027-08-16', 'amortizacao', 281436.02, 'BANCO DO BRASIL', 'C13', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1339),
  ('2027-10-15', 'amortizacao', 375307.94, 'BANCO DO BRASIL', 'C15', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1294),
  ('2027-11-15', 'amortizacao', 150244.25, 'BANCO DO BRASIL', 'C17', 'Amortizacao de financiamento (importado do ERP)', 'erp', 556),
  ('2027-12-15', 'amortizacao', 366047.20, 'BANCO DO BRASIL', 'C18', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1400),
  ('2028-08-15', 'amortizacao', 298322.19, 'BANCO DO BRASIL', 'C13', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1340),
  ('2028-10-16', 'amortizacao', 397953.46, 'BANCO DO BRASIL', 'C15', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1295),
  ('2028-11-15', 'amortizacao', 166065.32, 'BANCO DO BRASIL', 'C17', 'Amortizacao de financiamento (importado do ERP)', 'erp', 557),
  ('2028-12-15', 'amortizacao', 337555.70, 'BANCO DO BRASIL', 'C18', 'Amortizacao de financiamento (importado do ERP)', 'erp', 1401),
  ('2029-08-15', 'amortizacao', 456737.72, 'BANCO DO BRASIL', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 10003),
  ('2029-08-15', 'amortizacao', 456737.72, 'BANCO DO BRASIL', null, 'Amortizacao de financiamento (importado do ERP)', 'erp', 10004)
on conflict (erp_id) do update set contrato = excluded.contrato;

-- ------------------------------------------------------------
-- 4) CONFERENCIA (rode junto, o resultado aparece no fim)
-- Deve dar 75 titulos e R$ 17.829.159,91 no total, assim por ano de vencimento:
--   2023: R$ 8.723.987,79
--   2024: R$ 2.716.272,85
--   2025: R$ 1.083.729,31
--   2026: R$ 1.548.763,35
--   2027: R$ 1.643.034,50
--   2028: R$ 1.199.896,67
--   2029: R$ 913.475,44
-- ------------------------------------------------------------
select extract(year from data)::int as ano,
       count(*)                     as titulos,
       sum(valor)                   as total
  from movimentos_financiamento
 where origem = 'erp'
 group by 1
 order by 1;
