-- ============================================================
-- SO LEITURA -- Eduardo quer importar a produtividade histórica de
-- cana (2023/2024/2025) por FAZENDA (Palhadão, Palmito, Mata Verde),
-- só com o total -- não tem o detalhe por talhão daquela época
-- ("colheita é feita na fazenda como um todo"). Vamos diluir o
-- ton/ha de cada ano igualmente sobre os talhões de cana cadastrados
-- HOJE em cada fazenda (toneladas_talhao = area_ha_do_talhao ×
-- ton/ha_do_ano) -- preciso ver o cadastro atual antes de montar os
-- inserts. Não muda nada.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

select 1::numeric as ordem, f.nome || ' (fazenda id ' || f.id || ')' as item,
       t.nome || ' (talhao id ' || t.id || ')' as valor,
       coalesce(t.area_ha::text, '(sem area)') || ' ha -- cultura=' || coalesce(c.nome,'NENHUMA')
         || case when not t.ativo then ' -- INATIVO' else '' end as situacao
  from fazendas f
  join talhoes_areas t on t.fazenda_id = f.id
  left join culturas c on c.id = t.cultura_id
 where f.nome in ('Palhadão','Palmito','Mata Verde')
   and coalesce(c.frente,'') = 'cana'
 order by f.nome, t.nome;
