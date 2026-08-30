-- ===================================================================
-- AE Combustível — Operador vira Funcionário (reaproveitado do Matriz)
-- ===================================================================
-- Decisão do Eduardo em 30/08/2026: "Operador" deixa de ser um cadastro
-- próprio do Combustível (nome digitado à mão + CPF, tabela `operadores`)
-- e passa a listar direto os funcionários já cadastrados no Matriz,
-- excluindo cargo "Administrativo" (regra dele — quem abastece nunca é
-- do administrativo). Mesmo motivo de sempre: reaproveitar cadastro em
-- vez de duplicar, como fazendas/talhões/culturas/safras já são.
--
-- Confirmado antes de rodar isso (combustivel_confere_funcionarios_e_
-- operadores.sql + combustivel_confere_funcionarios_todas_policies.sql):
--   - 0 operadores cadastrados, 0 abastecimentos lançados — a troca de
--     FK não precisa religar nada.
--   - funcionarios já tem RLS liberado pra qualquer usuário autenticado
--     (policy "leitura/escrita autenticado", for ALL) — não precisa de
--     nenhuma policy nova pra combustível conseguir ler.
-- Por isso este script SÓ mexe na FK e apaga a tabela operadores (que
-- confirmadamente está vazia) — nada de RLS aqui.
--
-- SÓ COLE DEPOIS de já ter rodado combustivel_unificado_01_schema.sql.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='abastecimentos') then
    raise exception 'abastecimentos nao existe - rode o combustivel_unificado_01_schema.sql primeiro.';
  end if;
  -- Confere de novo na hora de rodar (não só confia no diagnóstico de
  -- antes) -- se alguém cadastrou algo nesse meio tempo, este script
  -- pararia sem religar dado nenhum, então é melhor parar aqui com um
  -- aviso claro do que apagar operadores com gente cadastrada ou quebrar
  -- a FK de um abastecimento já lançado.
  if exists (select 1 from abastecimentos limit 1) then
    raise exception 'Já existe abastecimento lançado -- pare e me avise, este script precisa ser ajustado pra religar os operador_id existentes antes de trocar a FK.';
  end if;
  if exists (select 1 from operadores limit 1) then
    raise exception 'Já existe operador cadastrado -- pare e me avise antes de rodar isso (o script apaga a tabela operadores).';
  end if;
end $$;

-- 1. Troca a FK de abastecimentos.operador_id: de operadores(id) pra
--    funcionarios(id). O nome da constraint é o padrão que o Postgres
--    dá quando ela nasce inline no CREATE TABLE (sem "constraint nome").
alter table abastecimentos drop constraint if exists abastecimentos_operador_id_fkey;
alter table abastecimentos add constraint abastecimentos_operador_id_fkey
  foreign key (operador_id) references funcionarios(id);

-- 2. A tabela operadores confirmadamente está vazia (checado acima) --
--    sem mais nenhum uso, sai do banco.
drop table if exists operadores;

select 1::numeric as ordem, item, valor, situacao from (
  select 'tabela operadores (esperado: 0 -- não existe mais)' as item,
         count(*)::text as valor,
         case when count(*)=0 then 'OK' else 'ERRO - ainda existe' end as situacao
    from information_schema.tables
   where table_schema='public' and table_name='operadores'
  union all
  select 'FK abastecimentos.operador_id aponta pra funcionarios (esperado: 1)',
         count(*)::text,
         case when count(*)=1 then 'OK' else 'ERRO' end
    from information_schema.constraint_column_usage ccu
    join information_schema.table_constraints tc on tc.constraint_name = ccu.constraint_name
   where tc.table_schema='public' and tc.table_name='abastecimentos'
     and tc.constraint_type='FOREIGN KEY' and ccu.table_name='funcionarios'
     and ccu.column_name='id'
) x order by 1;
