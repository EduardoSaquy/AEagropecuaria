-- seguranca_05_troca_de_senha.sql (12/11/2026)
-- Decisao do Eduardo: todos trocam para uma senha de 10 ou mais caracteres na proxima entrada com internet, e quem for
-- criado depois troca a senha provisoria no primeiro acesso.
--   1. profiles.precisa_trocar_senha (todos comecam com true) e profiles.senha_trocada_em;
--   2. gatilho em auth.users: quando a senha muda DE VERDADE, desmarca a pessoa e guarda a hora;
--   3. trava em profiles: ninguem desmarca a pessoa direto pela API (so o gatilho acima); marcar de novo pode.
-- O app (core.js) mostra a tela "crie uma senha nova" para quem esta marcado e nao abre antes da troca.
-- O minimo de 10 caracteres no servidor e uma configuracao do painel (Authentication); o app tambem confere.
-- Pode rodar de novo: nao marca de novo quem ja trocou. Desfazer: no fim do arquivo (comentado).

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO: este script e do banco unificado da AE Agropecuaria';
  end if;
end $$;

-- 1. colunas (ao criar a coluna, todos os perfis que ja existem ficam marcados)
alter table public.profiles add column if not exists precisa_trocar_senha boolean not null default true;
alter table public.profiles add column if not exists senha_trocada_em timestamptz;
comment on column public.profiles.precisa_trocar_senha is 'true = na proxima entrada com internet o app pede uma senha nova (10+ caracteres). Desmarca sozinho quando a senha muda (gatilho em auth.users).';

-- 2. senha trocada de verdade: desmarca
create or replace function public.senha_foi_trocada()
returns trigger language plpgsql security definer set search_path = public as $f$
begin
  perform set_config('ae.senha_trocada', 'sim', true);
  update public.profiles set precisa_trocar_senha = false, senha_trocada_em = now() where id = new.id;
  return new;
end
$f$;
revoke all on function public.senha_foi_trocada() from public, anon, authenticated;

drop trigger if exists trg_senha_foi_trocada on auth.users;
create trigger trg_senha_foi_trocada
  after update of encrypted_password on auth.users
  for each row when (old.encrypted_password is distinct from new.encrypted_password)
  execute function public.senha_foi_trocada();

-- 3. desmarcar so pelo gatilho da senha (pela API, mesmo o administrador so consegue marcar)
create or replace function public.trava_desmarcar_troca_de_senha()
returns trigger language plpgsql set search_path = public as $f$
begin
  if old.precisa_trocar_senha and not new.precisa_trocar_senha
     and coalesce(current_setting('ae.senha_trocada', true), '') <> 'sim'
     and current_user in ('authenticated', 'anon') then
    new.precisa_trocar_senha := true;
    new.senha_trocada_em := old.senha_trocada_em;
  end if;
  return new;
end
$f$;
drop trigger if exists trg_trava_desmarcar_troca_de_senha on public.profiles;
create trigger trg_trava_desmarcar_troca_de_senha
  before update of precisa_trocar_senha on public.profiles
  for each row execute function public.trava_desmarcar_troca_de_senha();

-- Conferencia
select 'perfis marcados para trocar a senha' as item, count(*) filter (where precisa_trocar_senha)::text || ' de ' || count(*)::text as valor,
       'OK: cada um troca na proxima entrada com internet' as situacao
from public.profiles
union all
select 'gatilho em auth.users', count(*)::text,
       case when count(*) = 1 then 'OK: senha trocada desmarca a pessoa' else 'FALTA o gatilho' end
from pg_trigger where tgrelid = 'auth.users'::regclass and tgname = 'trg_senha_foi_trocada'
union all
select 'trava em profiles', count(*)::text,
       case when count(*) = 1 then 'OK: pela API ninguem desmarca sem trocar a senha' else 'FALTA a trava' end
from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname = 'trg_trava_desmarcar_troca_de_senha';

-- DESFAZER (so se precisar):
-- drop trigger if exists trg_senha_foi_trocada on auth.users;
-- drop trigger if exists trg_trava_desmarcar_troca_de_senha on public.profiles;
-- drop function if exists public.senha_foi_trocada();
-- drop function if exists public.trava_desmarcar_troca_de_senha();
-- alter table public.profiles drop column if exists precisa_trocar_senha;
-- alter table public.profiles drop column if exists senha_trocada_em;
