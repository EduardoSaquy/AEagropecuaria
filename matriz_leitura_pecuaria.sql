-- Rodar no projeto do AE PECUÁRIA (https://leojfqlbdtlriemdgnyw.supabase.co),
-- na aba SQL Editor do painel do Supabase. NÃO rodar no projeto do Lavoura.
--
-- Por quê: o AE Matriz lê essas tabelas com a anon key (sb_publishable_...)
-- do próprio projeto da Pecuária, sem fazer login lá (ele já loga no
-- projeto do Lavoura). Hoje essas tabelas só liberam SELECT pra usuário
-- autenticado com permissão (tem_permissao(...)), então o Matriz recebe 0
-- linhas em tudo — os indicadores do card "AE Pecuária" e o Resultado dela
-- ficam zerados/errados até isto ser aplicado.
--
-- O que faz: adiciona, em cada tabela, uma política de SELECT adicional
-- restrita a requisição NÃO autenticada (auth.role() = 'anon'). É aditiva:
-- não mexe nas políticas existentes nem no acesso de quem já loga no AE
-- Pecuária — aquele fluxo continua exatamente igual, gated por
-- tem_permissao(). Só passa a liberar leitura pra quem chega sem sessão
-- nenhuma (que hoje já teria acesso de qualquer forma, já que a anon key
-- fica embutida no HTML público dos apps — não é um dado novo exposto).

drop policy if exists "leitura anon (AE Matriz)" on lotes;
create policy "leitura anon (AE Matriz)" on lotes for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on dietas;
create policy "leitura anon (AE Matriz)" on dietas for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on ingredientes;
create policy "leitura anon (AE Matriz)" on ingredientes for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on saidas_racao;
create policy "leitura anon (AE Matriz)" on saidas_racao for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on pasto;
create policy "leitura anon (AE Matriz)" on pasto for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on reproducao_custos;
create policy "leitura anon (AE Matriz)" on reproducao_custos for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on custos_fixos;
create policy "leitura anon (AE Matriz)" on custos_fixos for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on receitas;
create policy "leitura anon (AE Matriz)" on receitas for select using (auth.role() = 'anon');

drop policy if exists "leitura anon (AE Matriz)" on fazendas;
create policy "leitura anon (AE Matriz)" on fazendas for select using (auth.role() = 'anon');

-- profiles: NOVO — habilita o módulo Funcionários (AE Matriz) a listar as
-- contas reais já cadastradas na Pecuária, pra vincular funcionário a login
-- por um <select> de verdade em vez de campo de texto livre. Só SELECT;
-- criar/editar conta continua exclusivamente via Edge Function
-- ('criar-usuario'), nunca por policy de escrita liberada pro anon.
drop policy if exists "leitura anon (AE Matriz)" on profiles;
create policy "leitura anon (AE Matriz)" on profiles for select using (auth.role() = 'anon');

-- Depois de rodar: abra o AE Matriz (Painel) e confira se o card "AE
-- Pecuária" mostra números (lotes ativos, animais, dietas) em vez de
-- "carregando"/erro. Se continuar zerado, o mais provável é a chave do
-- dbPecuaria no AEMatriz.html estar desatualizada, não a política em si.
-- Pra conferir o módulo Funcionários: abra Funcionários > Editar em
-- qualquer um, o campo "Login no AE Pecuária" deve virar uma lista com os
-- usuários reais da Pecuária (não mais um campo de texto livre).
