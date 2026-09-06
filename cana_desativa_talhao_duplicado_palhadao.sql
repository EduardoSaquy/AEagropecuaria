-- ============================================================
-- Cana - desativa o talhao velho e duplicado "TAlhao 1" de Faz. Palhadao
-- (12 ha, nome com grafia diferente do "Talhao 1" real de 30,80 ha
-- cadastrado em cana_talhoes_reais_2025_tres_fazendas.sql -- PR #191).
-- Achado na conferencia que o Eduardo mandou de volta: os dois estavam
-- contando como talhao ativo, inflando a area cadastrada da fazenda em
-- duplicidade. Eduardo confirmou: desativar, nao apagar (preserva
-- historico se algum lancamento antigo apontar pra ele).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

do $$
declare
  v_talhao_id bigint;
  v_qtd       int;
begin
  select t.id into v_talhao_id
    from talhoes_areas t join fazendas f on f.id = t.fazenda_id
   where f.nome ilike 'Faz. Palhad%' and t.nome = 'TAlhao 1';

  if v_talhao_id is null then
    raise notice 'talhao "TAlhao 1" de Palhadao nao encontrado (ja desativado ou nome diferente) - nada a fazer';
    return;
  end if;

  select count(*) into v_qtd from talhoes_areas where id = v_talhao_id and ativo = false;
  if v_qtd = 1 then
    raise notice 'talhao "TAlhao 1" (id %) ja estava desativado - nada a fazer', v_talhao_id;
    return;
  end if;

  update talhoes_areas set ativo = false where id = v_talhao_id;
  raise notice 'talhao "TAlhao 1" (id %) desativado', v_talhao_id;
end $$;

-- ============================================================
-- CONFERENCIA - o talhao tem que aparecer com ativo=false, e mostra
-- quantos lancamentos antigos (se algum) apontam pra ele -- nenhum foi
-- apagado, so o cadastro ficou inativo.
-- ============================================================
with alvo as (
  select t.id
    from talhoes_areas t join fazendas f on f.id = t.fazenda_id
   where f.nome ilike 'Faz. Palhad%' and t.nome = 'TAlhao 1'
)
select 1::numeric as ordem, item, valor, situacao from (
  select 'talhao "TAlhao 1" de Palhadao' as item,
         'id ' || t.id || ', ' || t.area_ha || ' ha' as valor,
         case when t.ativo then 'AINDA ATIVO - confira' else 'desativado, OK' end as situacao
    from talhoes_areas t where t.id = (select id from alvo)
) x
union all
select 2::numeric, item, valor, situacao from (
  select 'referencias antigas a esse talhao (nao apagadas, so informativo)' as item,
         'colheitas_cana: ' || (select count(*) from colheitas_cana c where c.talhao_id = (select id from alvo))::text
           || ' | aplicacoes_cana: ' || (select count(*) from aplicacoes_cana a where a.talhao_id = (select id from alvo))::text
           || ' | plantios_cana: ' || (select count(*) from plantios_cana p where p.talhao_id = (select id from alvo))::text
           || ' | lancamentos_financeiros: ' || (select count(*) from lancamentos_financeiros l where l.talhao_id = (select id from alvo))::text as valor,
         'informativo' as situacao
) x
order by 1;
