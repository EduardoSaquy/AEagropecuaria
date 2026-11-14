-- notas_fiscais_01.sql (14/11/2026)
-- Nota fiscal no Contas a Pagar e a Receber do AE Matriz: o app le o XML da NF-e, preenche a conta e guarda o XML
-- (e o PDF da DANFE, se enviado) num bucket privado do Supabase Storage. Uma nota so pode ser lancada uma vez
-- (chave de acesso unica). Quem ve e lanca e o mesmo das contas (permissao contas, ou dono).
-- O app funciona antes deste script (o campo da nota so aparece depois). Pode rodar de novo. Desfazer no fim.

do $$
begin
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO: este script e do projeto unificado do AE Agropecuaria';
  end if;
  if not exists (select 1 from pg_proc where proname='segundo_fator_ok' and pronamespace='public'::regnamespace) then
    raise exception 'Falta a funcao segundo_fator_ok (seguranca_04). Nada foi feito.';
  end if;
end $$;

create table if not exists public.notas_fiscais (
  id              bigserial primary key,
  chave           text not null unique check (chave ~ '^[0-9]{44}$'),
  modelo          text,
  numero          text,
  serie           text,
  emissao         date,
  tipo_operacao   text check (tipo_operacao in ('entrada','saida')),
  emitente_nome   text,
  emitente_doc    text,
  destinatario_nome text,
  destinatario_doc  text,
  valor_total     numeric(14,2),
  xml_path        text,
  pdf_path        text,
  criado_por_id   uuid default auth.uid(),
  criado_em       timestamptz not null default now()
);
comment on table public.notas_fiscais is 'NF-e ligada a contas a pagar e a receber (AE Matriz). Chave de acesso unica: a mesma nota nao entra duas vezes.';

alter table public.titulos add column if not exists nota_fiscal_id bigint references public.notas_fiscais(id) on delete set null;
create index if not exists titulos_nota_fiscal_idx on public.titulos(nota_fiscal_id) where nota_fiscal_id is not null;

alter table public.notas_fiscais enable row level security;
revoke all on public.notas_fiscais from anon, public;
grant select, insert, update, delete on public.notas_fiscais to authenticated;
grant usage, select on sequence public.notas_fiscais_id_seq to authenticated;

drop policy if exists "ve notas" on public.notas_fiscais;
drop policy if exists "cria notas" on public.notas_fiscais;
drop policy if exists "altera notas" on public.notas_fiscais;
drop policy if exists "apaga notas" on public.notas_fiscais;
drop policy if exists exige_segundo_fator on public.notas_fiscais;
create policy "ve notas" on public.notas_fiscais for select to authenticated
  using ((select public.is_dono()) or (select public.tem_permissao('contas','visualizar')));
create policy "cria notas" on public.notas_fiscais for insert to authenticated
  with check ((select public.is_dono()) or (select public.tem_permissao('contas','editar')));
create policy "altera notas" on public.notas_fiscais for update to authenticated
  using ((select public.is_dono()) or (select public.tem_permissao('contas','editar')))
  with check ((select public.is_dono()) or (select public.tem_permissao('contas','editar')));
-- apagar: quem pode excluir, ou quem lancou (o app desfaz a nota quando a conta nao chega a ser gravada)
create policy "apaga notas" on public.notas_fiscais for delete to authenticated
  using ((select public.pode_excluir()) or ((select public.tem_permissao('contas','editar')) and criado_por_id = (select auth.uid())));
create policy exige_segundo_fator on public.notas_fiscais as restrictive for all to authenticated
  using ((select public.segundo_fator_ok())) with check ((select public.segundo_fator_ok()));

do $$
begin
  if exists (select 1 from pg_proc where proname='registrar_alteracao' and pronamespace='public'::regnamespace)
     and not exists (select 1 from pg_trigger where tgname='trg_registrar_alteracao' and tgrelid='public.notas_fiscais'::regclass) then
    create trigger trg_registrar_alteracao after insert or update or delete on public.notas_fiscais
      for each row execute function public.registrar_alteracao();
  end if;
end $$;

-- Arquivos: bucket privado, ate 5 MB, so XML e PDF
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('notas-fiscais', 'notas-fiscais', false, 5242880, array['application/xml','text/xml','application/pdf'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "nf ler" on storage.objects;
drop policy if exists "nf enviar" on storage.objects;
drop policy if exists "nf apagar" on storage.objects;
drop policy if exists "nf segundo fator" on storage.objects;
create policy "nf ler" on storage.objects for select to authenticated
  using (bucket_id = 'notas-fiscais' and ((select public.is_dono()) or (select public.tem_permissao('contas','visualizar'))));
create policy "nf enviar" on storage.objects for insert to authenticated
  with check (bucket_id = 'notas-fiscais' and ((select public.is_dono()) or (select public.tem_permissao('contas','editar'))));
create policy "nf apagar" on storage.objects for delete to authenticated
  using (bucket_id = 'notas-fiscais' and ((select public.pode_excluir())
         or ((select public.tem_permissao('contas','editar')) and owner_id = (select auth.uid())::text)));
create policy "nf segundo fator" on storage.objects as restrictive for all to authenticated
  using (bucket_id <> 'notas-fiscais' or (select public.segundo_fator_ok()))
  with check (bucket_id <> 'notas-fiscais' or (select public.segundo_fator_ok()));

select 'tabela notas_fiscais' as item,
       case when to_regclass('public.notas_fiscais') is not null then 'existe' else 'falta' end as valor,
       case when to_regclass('public.notas_fiscais') is not null then 'OK' else 'FALTA' end as situacao
union all
select 'coluna titulos.nota_fiscal_id', count(*)::text, case when count(*)=1 then 'OK' else 'FALTA' end
  from information_schema.columns where table_schema='public' and table_name='titulos' and column_name='nota_fiscal_id'
union all
select 'regras da tabela (5)', count(*)::text, case when count(*)=5 then 'OK' else 'CONFERIR' end
  from pg_policies where schemaname='public' and tablename='notas_fiscais'
union all
select 'bucket privado notas-fiscais', coalesce((select public::text from storage.buckets where id='notas-fiscais'),'falta'),
       case when exists (select 1 from storage.buckets where id='notas-fiscais' and public=false) then 'OK' else 'FALTA' end
union all
select 'regras dos arquivos (4)', count(*)::text, case when count(*)=4 then 'OK' else 'CONFERIR' end
  from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'nf %'
union all
select 'anon sem acesso a tabela', count(*)::text, case when count(*)=0 then 'OK' else 'ABERTA' end
  from information_schema.role_table_grants where table_schema='public' and table_name='notas_fiscais' and grantee='anon';

-- Para desfazer (apaga as notas e os arquivos ficam no bucket):
-- drop policy if exists "nf ler" on storage.objects; drop policy if exists "nf enviar" on storage.objects;
-- drop policy if exists "nf apagar" on storage.objects; drop policy if exists "nf segundo fator" on storage.objects;
-- alter table public.titulos drop column if exists nota_fiscal_id;
-- drop table if exists public.notas_fiscais;
