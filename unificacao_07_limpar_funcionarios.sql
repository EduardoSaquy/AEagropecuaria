-- ============================================================
-- LIMPEZA DO CADASTRO DE FUNCIONARIOS
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole o arquivo inteiro e aperte Run.
--
-- ------------------------------------------------------------
-- POR QUE
--
-- O botao "Importar contas sem funcionario vinculado" tratava a conta do
-- Lavoura e a conta da Pecuaria como pessoas diferentes. Como quatro
-- pessoas tinham conta nos dois lados, elas foram cadastradas duas vezes:
--
--   Alice Marini Saquy (com perfil_id)  +  Alice (so usuario_pecuaria)
--   Eduardo Saquy                       +  Eduardo
--   Marcia Mariani Saquy                +  Marcia
--   Paulo                               +  Paulo
--
-- Alem disso ha uma linha "Sem nome" vazia e a conta de teste, que
-- combinamos nao migrar.
--
-- ------------------------------------------------------------
-- QUANDO RODAR
--
-- Depois de criar os 5 logins que faltam (creunice, davi, gustavo, irlei,
-- joilson) na tela Usuarios do AE Matriz. Assim o script consegue ligar
-- cada funcionario ao login certo de uma vez.
--
-- Pode rodar antes tambem: nesse caso ele resolve as duplicatas e deixa
-- os 5 sem vinculo, e voce roda de novo depois de criar as contas.
--
-- ------------------------------------------------------------
-- O QUE ELE FAZ
--
-- 1. Guarda uma copia de funcionarios antes de mexer.
-- 2. Liga cada funcionario ao login, casando usuario_pecuaria com o
--    usuario da tabela profiles.
-- 3. Junta as duplicatas: quando duas linhas apontam para o mesmo login,
--    mantem a de nome mais completo e apaga a outra.
-- 4. Remove a linha "Sem nome" e a conta de teste.
--
-- SEGURO: funcionario_atividades esta vazia hoje, entao nenhuma alocacao
-- por atividade se perde. O script confere isso e recusa rodar se houver
-- alocacao cadastrada, para nao apagar trabalho seu sem avisar.
-- ============================================================

do $limpafunc$
declare
  n_antes      int;
  n_depois     int;
  n_alocacoes  int;
  n_vinculados int;
begin
  -- ---------- TRAVAS ----------
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  select count(*) into n_alocacoes from funcionario_atividades;
  if n_alocacoes > 0 then
    raise exception 'Existem % alocacoes em funcionario_atividades. Apagar funcionario apagaria elas junto. Me chame antes de rodar.', n_alocacoes;
  end if;

  select count(*) into n_antes from funcionarios;

  -- ---------- COPIA DE SEGURANCA ----------
  execute 'drop table if exists funcionarios_backup_limpeza';
  execute 'create table funcionarios_backup_limpeza as select * from funcionarios';

  -- ---------- 1) LIGAR AO LOGIN ----------
  -- usuario_pecuaria e texto; profiles.usuario e o mesmo texto. Onde casar
  -- e ainda nao houver vinculo, grava o perfil_id de verdade.
  update funcionarios f
  set perfil_id = p.id
  from profiles p
  where f.perfil_id is null
    and f.usuario_pecuaria is not null
    and p.usuario = f.usuario_pecuaria;

  -- ---------- 2) JUNTAR AS DUPLICATAS ----------
  -- Duas linhas com o mesmo perfil_id sao a mesma pessoa. Fica a de nome
  -- mais completo (com sobrenome); empate desempata pelo menor id.
  delete from funcionarios
  where id in (
    select id from (
      select id,
             row_number() over (
               partition by perfil_id
               order by (case when position(' ' in trim(nome)) > 0 then 0 else 1 end), id
             ) as ordem
      from funcionarios
      where perfil_id is not null
    ) ranqueado
    where ordem > 1
  );

  -- ---------- 3) LIXO ----------
  delete from funcionarios
  where perfil_id is null
    and coalesce(usuario_pecuaria, '') = ''
    and (nome is null or trim(nome) = '' or lower(trim(nome)) = 'sem nome');

  delete from funcionarios
  where perfil_id is null and usuario_pecuaria = 'teste';

  select count(*) into n_depois from funcionarios;
  select count(*) into n_vinculados from funcionarios where perfil_id is not null;

  raise notice 'funcionarios: % -> % linhas (% com login vinculado)', n_antes, n_depois, n_vinculados;
end
$limpafunc$;

-- Como ficou. A coluna acesso mostra o login de cada um.
select
  f.nome,
  f.cargo,
  coalesce(p.usuario, '--- SEM LOGIN ---') as acesso,
  p.papel,
  f.usuario_pecuaria as vinculo_antigo
from funcionarios f
left join profiles p on p.id = f.perfil_id
order by (p.usuario is null) desc, f.nome;

-- Para desfazer, se algo ficou errado:
--   delete from funcionarios;
--   insert into funcionarios overriding system value
--     select * from funcionarios_backup_limpeza;
