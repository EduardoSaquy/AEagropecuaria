-- ============================================================
-- SO LEITURA -- a consulta anterior voltou 0 linhas (filtrando fazenda
-- IN ('Palhadão','Palmito','Mata Verde') e cultura.frente='cana').
-- Abrindo sem esses filtros pra achar o que não bateu: nome da
-- fazenda diferente do esperado, cultura com frente diferente de
-- 'cana', ou talhão sem cultura definida. Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, 'fazenda cadastrada' as item,
       id::text as valor, nome as situacao
  from fazendas
union all
select 2::numeric, 'cultura cadastrada',
       id::text, nome || ' -- frente=' || frente
  from culturas
union all
select 3::numeric, f.nome,
       t.nome || ' (talhao id ' || t.id || ')',
       coalesce(t.area_ha::text,'(sem area)') || ' ha -- cultura_id=' || coalesce(t.cultura_id::text,'NENHUMA')
         || case when not t.ativo then ' -- INATIVO' else '' end
  from fazendas f
  join talhoes_areas t on t.fazenda_id = f.id
 order by 1, 2, 3;
