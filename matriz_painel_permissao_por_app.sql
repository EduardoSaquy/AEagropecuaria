-- ============================================================
-- AE Matriz — separa a permissão "Painel" numa por app
--
-- Antes, um único módulo 'matriz_painel' liberava ver os indicadores
-- de TODOS os apps (Pecuária, Cana, Cereais, Combustível) de uma vez.
-- Agora cada app tem a sua: 'matriz_painel_pecuaria',
-- 'matriz_painel_cana', 'matriz_painel_cereais',
-- 'matriz_painel_combustivel'.
--
-- Este script preserva o acesso de quem já tinha 'matriz_painel'
-- liberado: copia o mesmo nível (visualizar/editar) pras 4 chaves
-- novas. A chave antiga 'matriz_painel' fica no banco sem uso.
--
-- NOTA: este banco é único (unificado — Matriz, Pecuária, Cana,
-- Cereais e Combustível no mesmo projeto), então a guarda abaixo só
-- confere que existe uma tabela 'profiles'. O AE Matriz não tem
-- tabela 'apps' — a lista de apps do Painel é fixa no código
-- (APPS_REGISTRO), não vem do banco.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='profiles') then
    raise exception 'PROJETO ERRADO — esta tabela nao existe aqui.';
  end if;
end $$;

update profiles
set permissoes = permissoes
  || jsonb_build_object('matriz_painel_pecuaria', permissoes->>'matriz_painel')
  || jsonb_build_object('matriz_painel_cana', permissoes->>'matriz_painel')
  || jsonb_build_object('matriz_painel_cereais', permissoes->>'matriz_painel')
  || jsonb_build_object('matriz_painel_combustivel', permissoes->>'matriz_painel')
where permissoes ? 'matriz_painel'
  and permissoes->>'matriz_painel' in ('visualizar','editar');

-- Conferência: quem ficou com o quê.
select id, nome, papel,
       permissoes->>'matriz_painel' as painel_antigo,
       permissoes->>'matriz_painel_pecuaria' as painel_pecuaria,
       permissoes->>'matriz_painel_cana' as painel_cana,
       permissoes->>'matriz_painel_cereais' as painel_cereais,
       permissoes->>'matriz_painel_combustivel' as painel_combustivel
from profiles
where permissoes ? 'matriz_painel'
order by nome;
