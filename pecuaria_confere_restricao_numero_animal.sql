-- ============================================================
-- SO LEITURA -- Eduardo confirmou que no rebanho real pode haver o
-- mesmo numero de brinco em animais de sexos diferentes. O app
-- (AEpecuaria.html) trata "numero" como unico na fazenda inteira
-- (animalCadastrado() busca so por numero, upsertAnimal() funde no
-- cadastro existente em vez de criar um novo) -- se isso colidir com
-- um numero ja usado por um animal de sexo diferente, o cadastro dele
-- e sobrescrito (sexo e lote trocados) em vez de criar um animal novo.
-- Preciso saber se o BANCO tambem tem uma restricao de unico em
-- numero (o que bloquearia um segundo cadastro de vez, dando erro em
-- vez de fundir) antes de decidir a correcao certa. Nao muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, item, valor, situacao from (
  select 'restricoes/indices em animais.numero' as item,
         indexname as valor,
         indexdef as situacao
    from pg_indexes
   where schemaname='public' and tablename='animais'
  union all
  select 'numeros repetidos hoje (animais ativos, mesmo numero, sexos diferentes)',
         numero,
         string_agg(sexo || ' (id ' || id || ', lote ' || coalesce(lote_id::text,'nenhum') || ')', ' | ' order by id)
    from animais
   group by numero
  having count(distinct coalesce(sexo,'?')) > 1
) x;

select 2::numeric as ordem, 'total de animais cadastrados hoje' as item,
       count(*)::text as valor, 'informativo' as situacao
  from animais;
