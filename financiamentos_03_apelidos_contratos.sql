-- ============================================================
-- APELIDOS NOS CONTRATOS DO ERP (tira o numero real do banco de dados)
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode de uma vez. Pode rodar mais de uma vez sem problema.
--
-- A primeira versao do financiamentos_02_movimentos_erp.sql gravou o
-- numero real de cada contrato na coluna `contrato`, e a lista "Divida do
-- ERP ainda sem contrato" mostrava esse numero na tela. Este script troca
-- cada numero por um apelido C01, C02... pela ordem do 1o pagamento (empate:
-- o menor erp_id). Nada mais muda: as linhas do mesmo contrato continuam
-- juntas, so o nome do grupo e outro.
--
-- Quem ja rodou a versao NOVA do financiamentos_02 (que ja grava o apelido)
-- nao precisa deste: rodar de novo nao muda nada.
-- ============================================================

with ranking as (
  select contrato,
         'C' || lpad((row_number() over (order by min(data), min(erp_id)))::text, 2, '0') as apelido
    from movimentos_financiamento
   where origem = 'erp' and contrato is not null
   group by contrato
)
update movimentos_financiamento m
   set contrato = r.apelido
  from ranking r
 where m.contrato = r.contrato;

-- conferencia: um apelido por contrato, com quantas parcelas e o periodo
select contrato, count(*) as parcelas, min(data) as primeira, max(data) as ultima, sum(valor) as total
  from movimentos_financiamento
 where origem = 'erp' and contrato is not null
 group by contrato
 order by min(data), min(erp_id);
