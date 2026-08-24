-- ============================================================
-- REGISTRO DE QUEM MUDOU O QUE
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Pode rodar mais de uma vez sem problema.
--
-- ------------------------------------------------------------
-- POR QUE ISSO EXISTE
--
-- Hoje, se um valor aparece diferente do esperado, nao ha como saber quem
-- mudou, quando, nem qual era o valor anterior.
--
-- Tres dos bugs desta auditoria so foram diagnosticados porque as tabelas
-- antigas ainda existiam para comparacao - custos_fixos, despesas_cana,
-- receitas. Elas sao legado e um dia saem. Na proxima vez pode nao haver
-- com o que comparar, e a investigacao vira adivinhacao.
--
-- ------------------------------------------------------------
-- COMO FUNCIONA
--
-- Um gatilho no banco grava, a cada insercao, alteracao ou exclusao: a
-- linha antes, a linha depois, quem fez e quando. Roda no Postgres, entao:
--
--   - o app nao precisa saber que existe, e nenhuma tela muda
--   - vale para QUALQUER caminho, inclusive alteracao feita no SQL Editor
--   - nao da para burlar pela tela
--
-- Em UPDATE que nao muda nada (salvar sem alterar campo) nada e gravado -
-- senao o registro encheria de linha sem informacao.
--
-- ------------------------------------------------------------
-- ONDE ELE ENTRA, E POR QUE SO NESSAS
--
--   lancamentos_financeiros   o dinheiro. Toda a auditoria girou em torno
--                             de valores que mudavam sem explicacao
--   abates                    a venda, que gera receita e baixa animal
--   profiles                  quem pode o que. Mudanca de permissao e de
--                             papel precisa deixar rastro
--   centros_custo             o plano de contas, que acabou de ser
--                             reconstruido e nao deve mudar sem registro
--
-- Tabelas de operacao diaria (saidas_racao, pesagens, aplicacoes) ficam de
-- fora de proposito: sao muitas linhas por dia, e um erro ali aparece no
-- proprio relatorio operacional. Registrar tudo encheria a tabela e faria
-- o registro deixar de ser consultavel, que e o oposto do objetivo.
--
-- ------------------------------------------------------------
-- QUANTO OCUPA
--
-- Uma linha por alteracao, com duas copias da linha em jsonb. Nos volumes
-- desta operacao - 2.759 lancamentos, alterados de vez em quando - sao
-- alguns megabytes por ano. Se um dia incomodar, da para apagar registro
-- antigo: a ultima consulta deste arquivo mostra o tamanho.
-- ============================================================

-- ------------------------------------------------------------
-- 1) A TABELA
-- ------------------------------------------------------------
create table if not exists log_alteracoes (
  id           bigint generated always as identity primary key,
  tabela       text        not null,
  registro_id  text        not null,   -- text porque profiles usa uuid
  operacao     text        not null check (operacao in ('INSERT','UPDATE','DELETE')),
  antes        jsonb,                  -- nulo no INSERT
  depois       jsonb,                  -- nulo no DELETE
  -- Guarda o NOME junto com o id: se o perfil for apagado depois, o
  -- registro continua dizendo quem foi. Um log que perde o autor com o
  -- tempo nao serve para investigar o passado, que e justamente o uso.
  quem_id      uuid,
  quem_nome    text,
  quando       timestamptz not null default now()
);

create index if not exists idx_log_tabela_registro on log_alteracoes (tabela, registro_id, quando desc);
create index if not exists idx_log_quando          on log_alteracoes (quando desc);
create index if not exists idx_log_quem            on log_alteracoes (quem_id, quando desc);

alter table log_alteracoes enable row level security;

-- Ninguem grava pela API: quem escreve e o gatilho, que roda como dono da
-- funcao. Sem politica de INSERT, UPDATE ou DELETE, o registro nao pode ser
-- adulterado nem apagado por quem usa o app - inclusive por um admin.
drop policy if exists "le o registro" on log_alteracoes;
create policy "le o registro" on log_alteracoes for select using (is_admin());


-- ------------------------------------------------------------
-- 2) O GATILHO
-- ------------------------------------------------------------
create or replace function registrar_alteracao()
returns trigger
language plpgsql
security definer
set search_path = public
as $reg$
declare
  v_antes  jsonb;
  v_depois jsonb;
  v_id     text;
  v_uid    uuid;
  v_nome   text;
begin
  v_antes  := case when TG_OP = 'INSERT' then null else to_jsonb(OLD) end;
  v_depois := case when TG_OP = 'DELETE' then null else to_jsonb(NEW) end;

  -- UPDATE que nao mudou nada nao vira linha: salvar sem alterar campo e
  -- comum, e registrar isso encheria a tabela de ruido.
  if TG_OP = 'UPDATE' and v_antes = v_depois then
    return NEW;
  end if;

  v_id := case when TG_OP = 'DELETE' then (to_jsonb(OLD) ->> 'id')
                                     else (to_jsonb(NEW) ->> 'id') end;

  v_uid := auth.uid();
  if v_uid is not null then
    select nome into v_nome from profiles where id = v_uid;
  end if;

  insert into log_alteracoes (tabela, registro_id, operacao, antes, depois, quem_id, quem_nome)
  values (TG_TABLE_NAME, coalesce(v_id, '?'), TG_OP, v_antes, v_depois, v_uid,
          coalesce(v_nome, case when v_uid is null then 'SQL Editor / sem login' else 'perfil removido' end));

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end
$reg$;


-- ------------------------------------------------------------
-- 3) LIGAR NAS TABELAS
-- ------------------------------------------------------------
do $ligar$
declare
  t text;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  foreach t in array array['lancamentos_financeiros','abates','profiles','centros_custo']
  loop
    if to_regclass('public.' || t) is null then
      raise notice 'Tabela % nao existe, pulando.', t;
      continue;
    end if;
    execute format('drop trigger if exists trg_registrar_alteracao on public.%I', t);
    execute format(
      'create trigger trg_registrar_alteracao after insert or update or delete on public.%I '
      'for each row execute function registrar_alteracao()', t);
    raise notice 'Registro ligado em %', t;
  end loop;
end
$ligar$;


-- ============================================================
-- CONFERENCIA 1 - OS GATILHOS ESTAO NO LUGAR
-- Tem que aparecer as quatro tabelas.
-- ============================================================
select c.relname as tabela, t.tgname as gatilho,
       case when t.tgenabled = 'O' then 'ativo' else 'DESLIGADO' end as situacao
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where not t.tgisinternal and t.tgname = 'trg_registrar_alteracao'
order by c.relname;


-- ============================================================
-- CONFERENCIA 2 - COMO CONSULTAR DEPOIS
--
-- Esta e a consulta que voce vai querer no dia que um numero nao fizer
-- sentido. Ela mostra o que mudou de VERDADE em cada alteracao, campo a
-- campo, ignorando o que ficou igual.
--
-- Hoje deve voltar vazia: o registro comeca agora.
-- ============================================================
select
  l.quando,
  l.quem_nome as quem,
  l.tabela,
  l.registro_id,
  l.operacao,
  campo.chave                as campo,
  l.antes  ->> campo.chave   as de,
  l.depois ->> campo.chave   as para
from log_alteracoes l
cross join lateral jsonb_object_keys(coalesce(l.depois, l.antes)) as campo(chave)
where l.operacao = 'UPDATE'
  and (l.antes ->> campo.chave) is distinct from (l.depois ->> campo.chave)
order by l.quando desc, l.registro_id, campo.chave
limit 100;


-- ============================================================
-- CONFERENCIA 3 - TAMANHO DO REGISTRO
--
-- Acompanhe de vez em quando. Se um dia incomodar:
--   delete from log_alteracoes where quando < now() - interval '2 years';
-- ============================================================
select count(*) as alteracoes_registradas,
       pg_size_pretty(pg_total_relation_size('log_alteracoes')) as espaco,
       min(quando) as mais_antiga,
       max(quando) as mais_recente
from log_alteracoes;
