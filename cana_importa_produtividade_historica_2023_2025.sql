-- ===================================================================
-- AE Cana — importa produtividade histórica 2023/2024/2025 por fazenda
-- ===================================================================
-- Eduardo mandou a planilha de produtividade (área colhida, produção
-- em toneladas, ton/ha) por fazenda e ano, pra Palhadão/Palmito/Mata
-- Verde. Hoje só existe 1 talhão de cana cadastrado no sistema
-- (Palhadão, 12 ha) -- Palmito e Mata Verde não têm nenhum. E a
-- colheita, na prática, é feita na fazenda inteira de uma vez, sem
-- divisão por talhão -- e a área colhida MUDA a cada ano (140,09 ha
-- em 2023, 167,39 em 2024, 87,52 em 2025, só em Palhadão), enquanto o
-- app só aceita uma área fixa por talhão.
--
-- Decisão do Eduardo: um "talhão" por fazenda+ano (ex: "Histórico
-- 2023"), cada um com a área colhida daquele ano específico -- assim o
-- TCH que o app calcula (toneladas / área do talhão) bate exatamente
-- com o ton/ha da planilha. Não são talhões de verdade (a fazenda não
-- separa por talhão na colheita) -- servem só pra guardar o histórico
-- de produtividade comparável ano a ano, como já é feito hoje no app
-- pra colheita corrente.
--
-- Confere os 3 IDs de fazenda e o ID da cultura contra o que já foi
-- visto no diagnóstico (cana_confere_talhoes_v2_diagnostico_aberto.sql)
-- antes de inserir -- se mudou, aborta em vez de gravar no lugar errado.
-- ===================================================================

do $$
declare
  v_palhadao int; v_palmito int; v_mataverde int; v_cana int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;

  select id into v_palhadao from fazendas where nome = 'Faz. Palhadão';
  select id into v_palmito from fazendas where nome = 'Faz. Palmito';
  select id into v_mataverde from fazendas where nome = 'Faz. Mata Verde';
  select id into v_cana from culturas where nome = 'Cana-de-açúcar' and frente = 'cana';

  if v_palhadao is null or v_palmito is null or v_mataverde is null or v_cana is null then
    raise exception 'Fazenda ou cultura nao encontrada com o nome esperado -- confira antes de rodar (mudou o cadastro desde o diagnostico?).';
  end if;
  if v_palhadao <> 1 or v_palmito <> 2 or v_mataverde <> 3 or v_cana <> 1 then
    raise exception 'IDs diferentes do diagnostico (palhadao=%, palmito=%, mataverde=%, cana=%) -- ajuste o script antes de rodar, nao insira as cegas.', v_palhadao, v_palmito, v_mataverde, v_cana;
  end if;

  if exists (select 1 from talhoes_areas where nome like 'Histórico %' and fazenda_id in (v_palhadao, v_palmito, v_mataverde)) then
    raise exception 'Ja existe talhao "Historico ..." nessas fazendas -- essa importacao ja foi feita antes. Nao roda de novo (duplicaria).';
  end if;
end $$;

with novos_talhoes as (
  insert into talhoes_areas (fazenda_id, nome, tipo, area_ha, cultura_id, ativo)
  values
    (1,'Histórico 2023','talhao',140.09,1,true),
    (1,'Histórico 2024','talhao',167.39,1,true),
    (1,'Histórico 2025','talhao', 87.52,1,true),
    (2,'Histórico 2023','talhao',112.53,1,true),
    (2,'Histórico 2024','talhao',150.08,1,true),
    (2,'Histórico 2025','talhao',150.93,1,true),
    (3,'Histórico 2023','talhao',104.95,1,true),
    (3,'Histórico 2024','talhao', 33.00,1,true),
    (3,'Histórico 2025','talhao',103.79,1,true)
  returning id, fazenda_id, area_ha
),
producao(fazenda_id, area_ha, data_colheita, toneladas) as (
  values
    (1,140.09,'2023-12-31'::date,14211.47),
    (1,167.39,'2024-12-31'::date,15269.22),
    (1, 87.52,'2025-12-31'::date, 6722.40),
    (2,112.53,'2023-12-31'::date, 9595.06),
    (2,150.08,'2024-12-31'::date,15738.92),
    (2,150.93,'2025-12-31'::date, 9661.20),
    (3,104.95,'2023-12-31'::date, 7028.34),
    (3, 33.00,'2024-12-31'::date, 2432.82),
    (3,103.79,'2025-12-31'::date, 7636.92)
)
insert into colheitas_cana (talhao_id, data, toneladas, observacao)
select nt.id, p.data_colheita, p.toneladas,
       'Importado do histórico de produtividade por fazenda (planilha enviada pelo Eduardo em 03/09/2026) -- colheita agregada da fazenda inteira nesse ano, sem divisão real por talhão (a colheita é feita na fazenda toda de uma vez).'
  from novos_talhoes nt
  join producao p on p.fazenda_id = nt.fazenda_id and p.area_ha = nt.area_ha;

-- ============================================================
-- conferência -- TCH calculado (toneladas/área) tem que bater exato
-- com a coluna "Ton/ha" da planilha
-- ============================================================
select 1::numeric as ordem, f.nome || ' - ' || t.nome as item,
       round(c.toneladas / t.area_ha, 2)::text || ' ton/ha' as valor,
       'area=' || t.area_ha || 'ha, producao=' || c.toneladas || 't' as situacao
  from colheitas_cana c
  join talhoes_areas t on t.id = c.talhao_id
  join fazendas f on f.id = t.fazenda_id
 where t.nome like 'Histórico %'
 order by f.nome, t.nome;
