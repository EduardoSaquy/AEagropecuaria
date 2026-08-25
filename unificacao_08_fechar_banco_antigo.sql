-- ============================================================
-- FECHAR O BANCO ANTIGO DA PECUARIA PARA LANCAMENTOS
--
-- RODAR NO PROJETO ANTIGO DA PECUARIA (leojfqlbdtlriemdgnyw).
-- E o unico script depois da unificacao que roda la, e nao no Lavoura.
--
-- ------------------------------------------------------------
-- POR QUE
--
-- O app guarda uma copia de si mesmo para funcionar sem sinal. Quem abrir
-- offline pode receber a versao antiga, que aponta para este banco. Como
-- este projeto continua no ar, o login antigo funcionaria e a pessoa
-- lancaria aqui achando que deu certo. O lancamento ficaria perdido: nao
-- estaria no banco novo, e ninguem perceberia.
--
-- Desativando as contas, esse caminho fecha. Quem cair na versao antiga ve
-- a tela de "aguardando liberacao" em vez de conseguir lancar - erro
-- visivel, que gera um telefonema em vez de um dado perdido.
--
-- ------------------------------------------------------------
-- ISTO NAO APAGA NADA
--
-- Os dados continuam todos aqui, intactos, e este projeto segue sendo a
-- rede de seguranca. Muda so o campo ativo dos usuarios, e o script guarda
-- os valores atuais numa copia antes de mexer.
--
-- Para reverter (se precisar reabrir o app antigo por algum motivo):
--   update profiles p set ativo = b.ativo
--   from profiles_ativo_antes_do_fechamento b where p.id = b.id;
-- ============================================================

do $fechar$
declare
  n_ativos int;
begin
  -- ---------- TRAVA: tem que ser o projeto ANTIGO ----------
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script roda no projeto ANTIGO da Pecuaria (leojfqlbdtlriemdgnyw), nao no Lavoura. Rodar aqui desativaria todos os logins em uso.';
  end if;

  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'lotes') then
    raise exception 'Este nao parece ser o banco da Pecuaria.';
  end if;

  select count(*) into n_ativos from profiles where ativo = true;

  -- ---------- COPIA DO ESTADO ATUAL ----------
  execute 'drop table if exists profiles_ativo_antes_do_fechamento';
  execute 'create table profiles_ativo_antes_do_fechamento as select id, usuario, ativo from profiles';

  -- ---------- FECHAR ----------
  update profiles set ativo = false where ativo = true;

  raise notice 'Contas desativadas: %. Estado anterior guardado em profiles_ativo_antes_do_fechamento.', n_ativos;
end
$fechar$;

-- Conferencia: a coluna ativo tem que estar toda em false.
select usuario, nome, ativo from profiles order by usuario;
