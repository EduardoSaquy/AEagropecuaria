-- ============================================================
-- PASSO 4 — JUNTAR USUÁRIOS E PERMISSÕES
--
-- RODAR NO PROJETO DO **LAVOURA/MATRIZ**, depois que:
--   a) o passo 3 (dados) tiver conferido OK; e
--   b) as 5 contas novas já tiverem sido criadas pela tela de Usuários do
--      AE Matriz, com EXATAMENTE estes nomes de usuário:
--        creunice, davi, gustavo, irlei, joilson
--
-- Por que o nome de usuário tem que ser idêntico: a autoria dos lançamentos
-- da Pecuária (criado_por) é TEXTO com o nome de usuário, não um ID. Mantendo
-- o mesmo login, todo o histórico de "quem lançou" continua batendo sozinho,
-- sem precisar remapear nada.
-- ============================================================


-- ------------------------------------------------------------
-- ⛔ TRAVA DE PROJETO — não remova
--
-- Rodar isto na Pecuária sobrescreveria as permissões de lá com as chaves
-- pec_*, quebrando o acesso de todo mundo naquele banco.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'talhoes_areas'
  ) then
    raise exception E'PROJETO ERRADO.\nEste script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).\nRodar na Pecuaria quebraria o acesso de todos os usuarios de la. Troque de projeto.';
  end if;
  -- Sem o backup do passo 0, nao deixa seguir: este e o unico script que
  -- altera dado de producao que ja existia.
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'profiles_backup_unificacao'
  ) then
    raise exception E'SEM BACKUP.\nA tabela profiles_backup_unificacao nao existe: o PASSO 0 nao foi rodado neste projeto.\nEste e o unico script que altera dado ja existente. Rode o unificacao_00_backup.sql primeiro.';
  end if;
end $$;


-- ------------------------------------------------------------
-- 4.1 — Liberar os papéis da Pecuária no check de profiles
--
-- O Lavoura aceita: admin, proprietario, gestor, encarregado, colaborador,
-- operador. A Pecuária usa também 'consultor' (o irlei é consultor). Sem
-- isto, gravar o papel dele falha.
-- ------------------------------------------------------------
alter table profiles drop constraint if exists profiles_papel_check;
alter table profiles add constraint profiles_papel_check
  check (papel in ('admin','proprietario','gestor','encarregado','colaborador','operador','consultor'));


-- ------------------------------------------------------------
-- 4.2 — Conferir que todo mundo tem conta antes de continuar
--
-- Tem que listar os 9 usuários (os 4 que já existiam + as 5 contas novas).
-- Se faltar alguém, crie a conta e rode de novo antes de seguir.
-- ------------------------------------------------------------
select usuario, nome, papel, ativo
from profiles
where usuario in ('alice','eduardo','marcia','paulo','creunice','davi','gustavo','irlei','joilson')
order by usuario;


-- ------------------------------------------------------------
-- 4.3 — Foto do "antes" (guarde este resultado)
-- ------------------------------------------------------------
select usuario, papel, permissoes as permissoes_antes
from profiles
where usuario in ('alice','eduardo','marcia','paulo','creunice','davi','gustavo','irlei','joilson')
order by usuario;


-- ------------------------------------------------------------
-- 4.4 — Trazer as permissões da Pecuária
--
-- Regras aplicadas:
--   * 'financeiro'  -> 'pec_financeiro'   (colide com o Lavoura)
--   * 'resultados'  -> 'pec_resultados'   (colide com o Lavoura)
--   * as outras 9 chaves entram como estão (não colidem com nada)
--   * as permissões de Lavoura de quem já tinha são PRESERVADAS: o || do
--     jsonb mescla, e como as chaves da Pecuária agora são distintas,
--     nenhuma sobrescreve a outra.
--   * o papel NÃO é alterado aqui. Conferi que os 4 que existem nos dois
--     lados já têm papel idêntico, então não há nada a decidir. As 5 contas
--     novas recebem o papel na hora de criar (colaborador; irlei consultor).
-- ------------------------------------------------------------
with pec as (
  select * from (values
    ('alice',    '{"cadastro":"editar","manejo":"nenhum","insumos":"editar","dietas":"editar","lotesGeral":"editar","confinamento":"editar","pasto":"editar","cria":"editar","vendas":"editar","pec_financeiro":"editar","pec_resultados":"editar"}'::jsonb),
    ('creunice', '{"dietas":"editar","insumos":"editar","confinamento":"visualizar","pasto":"visualizar","cria":"visualizar","pec_financeiro":"editar","pec_resultados":"nenhum"}'::jsonb),
    ('davi',     '{"dietas":"visualizar","insumos":"nenhum","confinamento":"editar","pasto":"editar","cria":"editar","pec_financeiro":"nenhum","pec_resultados":"nenhum"}'::jsonb)
  ) as t(usuario, permissoes)
)
-- ⚠️ ATENÇÃO: os 3 acima são os que eu consegui ler ao vivo. Antes de rodar,
-- complete a lista com gustavo, irlei, joilson, marcia, paulo e eduardo,
-- copiando de: AE Pecuária → Administração → Usuários → Editar acesso.
-- Lembrando de já escrever pec_financeiro / pec_resultados no lugar de
-- financeiro / resultados.
update profiles p
set permissoes = coalesce(p.permissoes, '{}'::jsonb) || pec.permissoes
from pec
where p.usuario = pec.usuario;


-- ------------------------------------------------------------
-- 4.5 — ✅ CONFERÊNCIA
--
-- Olhe especialmente alice e paulo: eles têm permissão dos DOIS lados.
-- O resultado tem que mostrar as chaves do Lavoura (cadastros, operacoes,
-- financeiro, resultados, ...) E as da Pecuária (confinamento, cria, pasto,
-- pec_financeiro, pec_resultados, ...) convivendo na mesma linha.
-- ------------------------------------------------------------
select
  usuario,
  papel,
  (select count(*) from jsonb_object_keys(permissoes)) as total_chaves,
  permissoes ? 'financeiro'      as tem_financeiro_lavoura,
  permissoes ? 'pec_financeiro'  as tem_financeiro_pecuaria,
  permissoes
from profiles
where usuario in ('alice','eduardo','marcia','paulo','creunice','davi','gustavo','irlei','joilson')
order by usuario;
