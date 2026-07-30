-- ============================================================
-- AE Cana — desmembra "Insumos Agrícolas" em centros de custo
-- mais específicos, a pedido do usuário.
--
-- "Insumos Agrícolas" (R$ 1.439.131,79, 81 lançamentos) vira:
--   - Adubos e Fertilizantes    (R$ 1.085.959,05, 27 lançamentos)
--   - Corretivos de Solo        (R$    11.420,15,  2 lançamentos)
--   - Defensivos Agrícolas      (R$   338.059,79, 50 lançamentos)
--   - Sementes e Mudas de Plantio (R$   3.200,00,  1 lançamento)
--   - Embalagens, Sacarias e Lonas (R$    492,80,  1 lançamento)
-- (soma bate com o total original: R$ 1.439.131,79)
--
-- "Corretivos de Solo" foi identificado pelo fornecedor (IBIATA
-- COMERCIO DE CORRETIVOS DE SOLO LTDA) — no relatório original ele
-- estava dentro de "Adubos e Fertilizantes" junto com os outros.
-- Os demais vêm direto do campo "Conta" do relatório original, que já
-- estava preservado no início do texto de cada descrição.
--
-- Rode este arquivo inteiro de uma vez, na ordem em que aparece.
-- ============================================================

-- 1. Cria os 5 novos centros de custo
with fz as (
  select id from fazendas where nome = 'Faz. Palhadão' limit 1
)
insert into centros_custo (fazenda_id, nome, frente, ativo)
select fz.id, v.nome, 'cana', true
from fz, (values
  ('Adubos e Fertilizantes'),
  ('Corretivos de Solo'),
  ('Defensivos Agrícolas'),
  ('Sementes e Mudas de Plantio'),
  ('Embalagens, Sacarias e Lonas')
) as v(nome)
on conflict (fazenda_id, nome) do nothing;

-- 2. Corretivos de Solo (mais específico — roda antes do de Adubos)
update despesas_cana d
set centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Corretivos de Solo' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
where d.centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
and d.descricao like 'ADUBOS E FERTILIZANTES — IBIATA COMERCIO DE CORRETIVOS DE SOLO%';

-- 3. Adubos e Fertilizantes (o que sobrou de "ADUBOS E FERTILIZANTES —")
update despesas_cana d
set centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Adubos e Fertilizantes' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
where d.centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
and d.descricao like 'ADUBOS E FERTILIZANTES — %';

-- 4. Defensivos Agrícolas
update despesas_cana d
set centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Defensivos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
where d.centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
and d.descricao like 'DEFENSIVOS AGRÍCOLAS — %';

-- 5. Sementes e Mudas de Plantio
update despesas_cana d
set centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Sementes e Mudas de Plantio' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
where d.centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
and d.descricao like 'SEMENTES E MUDAS DE PLANTIO — %';

-- 6. Embalagens, Sacarias e Lonas
update despesas_cana d
set centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Embalagens, Sacarias e Lonas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
where d.centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
)
and d.descricao like 'EMBALAGENS, SACARIAS E LONAS — %';

-- 7. Confere que não sobrou nenhuma despesa em "Insumos Agrícolas"
--    (se este select retornar linhas, alguma descrição não bateu com
--    nenhum dos padrões acima — pare aqui e me avise antes do passo 8).
select d.id, d.descricao, d.valor
from despesas_cana d
where d.centro_custo_id = (
  select cc.id from centros_custo cc, fazendas fz
  where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão'
);

-- 8. Remove o centro de custo antigo "Insumos Agrícolas" (só roda se o
--    select acima veio vazio — senão vai dar erro de referência).
delete from centros_custo cc using fazendas fz
where cc.nome = 'Insumos Agrícolas' and cc.fazenda_id = fz.id and fz.nome = 'Faz. Palhadão';
