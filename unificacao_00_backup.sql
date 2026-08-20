-- ============================================================
-- PASSO 0 — BACKUP (rodar ANTES de qualquer outro script)
--
-- RODAR NO PROJETO DO **LAVOURA/MATRIZ** (kmkystqgpvmzrccxvyaz).
--
-- ------------------------------------------------------------
-- POR QUE ESTE ARQUIVO É CURTO
--
-- Revisando a migração passo a passo, o dado de produção que corre risco
-- de verdade é MUITO menor do que "os dois bancos inteiros":
--
--   * Banco da PECUÁRIA  -> só é LIDO durante toda a migração. Nenhum script
--     escreve nele. Ele continua sendo, por si só, a cópia íntegra de tudo
--     que era dele. Não precisa de backup pra ficar seguro.
--
--   * Passo 2 (estrutura) -> só CRIA tabelas novas. Não toca em nada que já
--     existe. Se der errado, é só dar drop nas tabelas novas.
--
--   * Passo 3 (dados)     -> só INSERE nas tabelas novas criadas no passo 2.
--     Nenhuma tabela antiga do Lavoura é tocada.
--
--   * Passo 4 (permissões) -> AQUI SIM. É o único ponto em que a migração
--     altera dado que já existe em produção: um UPDATE em profiles.permissoes
--     e uma troca do check de papel.
--
-- Ou seja: a tabela em risco é UMA — profiles do Lavoura. É isso que este
-- script protege, e leva alguns segundos.
-- ============================================================


-- ------------------------------------------------------------
-- 0.1 — Cópia de segurança da tabela profiles, dentro do próprio banco
--
-- Cópia interna é melhor que CSV aqui: não depende de download, não perde
-- tipo de dado e o restore é uma linha de SQL.
-- ------------------------------------------------------------
drop table if exists profiles_backup_unificacao;
create table profiles_backup_unificacao as select * from profiles;

-- ✅ Verificação: os dois números têm que ser iguais.
select
  (select count(*) from profiles)                     as profiles_agora,
  (select count(*) from profiles_backup_unificacao)   as backup,
  case when (select count(*) from profiles) = (select count(*) from profiles_backup_unificacao)
       then 'OK' else '*** NÃO CONFERE — PARE ***' end as confere;


-- ------------------------------------------------------------
-- 0.2 — Guardar a definição atual do check de papel
--
-- O passo 4 troca esse check pra aceitar 'consultor'. Guarde o texto que
-- este select devolver, pra conseguir recriar o original se precisar.
-- ------------------------------------------------------------
select con.conname, pg_get_constraintdef(con.oid) as definicao_atual
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
where rel.relname = 'profiles' and con.contype = 'c';


-- ------------------------------------------------------------
-- 0.3 — COMO DESFAZER (não rode agora; é a receita de emergência)
--
-- Se o passo 4 bagunçar as permissões, isto devolve tudo ao estado atual:
--
--   update profiles p
--   set permissoes = b.permissoes,
--       papel      = b.papel,
--       ativo      = b.ativo
--   from profiles_backup_unificacao b
--   where p.id = b.id;
--
-- E, se precisar voltar o check de papel, use o texto guardado no 0.2:
--
--   alter table profiles drop constraint profiles_papel_check;
--   alter table profiles add constraint profiles_papel_check <texto do 0.2>;
--
-- Para desfazer os passos 2 e 3 (estrutura + dados), basta dar drop nas
-- tabelas novas — nenhuma delas existia antes no Lavoura:
--
--   drop table if exists saidas_racao, reproducao_custos, receitas,
--     protocolos_inseminacao, producoes_racao, precos_arroba,
--     pesagens_animais, pesagens, pasto, movimentos, manejos,
--     leituras_cocho, investimentos, ingredientes, dietas,
--     diagnosticos_gestacionais, desmamas, partos, custos_fixos,
--     config_financeiro, config_fazenda, animais, abates, lotes cascade;
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 0.4 — Backup extra (opcional, recomendado mesmo assim)
--
-- O acima cobre o risco real da migração. Se quiser dormir mais tranquilo,
-- exporte também em CSV, pelo Table Editor -> Export, as tabelas do Lavoura
-- que concentram o histórico e seriam caras de recompor:
--
--   fazendas, fazenda_atividades, funcionarios, funcionario_atividades,
--   talhoes_areas, despesas_cana, receitas_cana, despesas_graos,
--   receitas_graos, colheitas_cana, colheitas_graos
--
-- Nenhuma delas é tocada pela migração — isto é cinto além do suspensório.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 0.5 — Anotar os números de HOJE, pra conferir depois
--
-- Guarde este resultado. Depois que os apps estiverem no banco único, os
-- números do Painel do Matriz têm que continuar os mesmos.
-- ------------------------------------------------------------
select 'fazendas' as tabela, count(*) from fazendas
union all select 'fazenda_atividades', count(*) from fazenda_atividades
union all select 'funcionarios', count(*) from funcionarios
union all select 'funcionario_atividades', count(*) from funcionario_atividades
union all select 'talhoes_areas', count(*) from talhoes_areas
union all select 'profiles', count(*) from profiles
order by 1;
