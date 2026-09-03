-- ============================================================
-- SO LEITURA -- Eduardo mandou a lista de numeros da pesagem recente
-- (36 numeros, coluna da esquerda das fotos do caderno -- a coluna da
-- direita e peso, nao numero de animal). Antes de corrigir o bug do numero
-- unico (animalCadastrado()/upsertAnimal() fundiam macho e femea que
-- compartilhavam numero -- ver commit eb9032f), preciso saber se algum
-- desses numeros JA EXISTIA como femea antes dessa pesagem -- se
-- existia, o cadastro dela pode ter sido sobrescrito (virado macho,
-- mudou de lote) pelo bug, sem deixar rastro (animais nao tem
-- auditoria). Nao muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

with numeros_pesados(numero) as (
  select unnest(array[
    '164','015','285','402','647','189','171','643','380',
    '453','456','213','457','279','342','037','409',
    '317','313','016','2727','180','193','2978','173','229','210',
    '058','160','247','249','795','2966','119','306','227'
  ])
),
por_numero as (
  select np.numero,
         count(a.id) as qtd_cadastros,
         count(distinct coalesce(a.sexo,'?')) as qtd_sexos_distintos,
         string_agg('id ' || a.id || ' sexo=' || coalesce(a.sexo,'?') || ' lote=' || coalesce(a.lote_id::text,'nenhum'), ' | ' order by a.id) as detalhe
    from (select distinct numero from numeros_pesados) np
    left join animais a on lower(trim(a.numero)) = lower(trim(np.numero))
   group by np.numero
)
select 1::numeric as ordem, numero as item,
       qtd_cadastros::text as valor,
       case
         when qtd_cadastros = 0 then 'nao cadastrado ainda -- OK, sem risco'
         when qtd_sexos_distintos > 1 then 'ATENCAO -- existe em MAIS de um sexo: ' || detalhe
         when qtd_cadastros = 1 then 'ja cadastrado (1x): ' || detalhe
         else 'ja cadastrado (' || qtd_cadastros || 'x, mesmo sexo): ' || detalhe
       end as situacao
  from por_numero
 order by (case when qtd_sexos_distintos > 1 then 0 else 1 end), numero;
