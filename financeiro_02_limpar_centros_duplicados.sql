-- ============================================================
-- LIMPAR CENTROS DE CUSTO GLOBAIS DUPLICADOS
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Sao dois comandos.
--
-- POR QUE: o indice que impede dois centros globais com o mesmo nome nao
-- pode ser criado enquanto a duplicata existir. E a duplicata so passou
-- despercebida porque a restricao unica atual e por (fazenda_id, nome), e
-- no Postgres nulos sao considerados sempre diferentes entre si - entao
-- dois centros globais de mesmo nome nunca foram barrados.
--
-- SEGURANCA: so apaga duplicata que nao esta em uso em lugar nenhum. Se
-- alguma estiver sendo usada, o script para e mostra qual, sem apagar nada.
-- Mantem sempre o registro de menor id, que e o mais antigo.
-- ============================================================

do $limpacentros$
declare
  d record;
  n_removidos int := 0;
  tem_lancamentos boolean;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  tem_lancamentos := exists (select 1 from information_schema.tables
                             where table_schema = 'public' and table_name = 'lancamentos_financeiros');

  -- Percorre os globais duplicados, menos o de menor id de cada nome.
  for d in
    select id, nome from (
      select id, nome,
             row_number() over (partition by nome order by id) as ordem
      from centros_custo
      where fazenda_id is null
    ) t
    where ordem > 1
  loop
    -- Recusa apagar qualquer um que esteja em uso.
    if exists (select 1 from despesas_cana  where centro_custo_id = d.id)
       or exists (select 1 from despesas_graos where centro_custo_id = d.id) then
      raise exception 'O centro de custo % (id %) esta em uso e nao pode ser removido automaticamente. Me avise.', d.nome, d.id;
    end if;

    if tem_lancamentos then
      if exists (select 1 from lancamentos_financeiros where centro_custo_id = d.id) then
        raise exception 'O centro de custo % (id %) ja tem lancamento vinculado. Me avise.', d.nome, d.id;
      end if;
    end if;

    delete from centros_custo where id = d.id;
    raise notice 'removido: % (id %)', d.nome, d.id;
    n_removidos := n_removidos + 1;
  end loop;

  raise notice 'Centros duplicados removidos: %', n_removidos;

  -- Agora o indice passa.
  create unique index if not exists uq_centro_custo_global
    on centros_custo (nome) where fazenda_id is null;
end
$limpacentros$;

-- Confirmacao: a primeira coluna tem que vir 0 (nenhum nome global
-- repetido) e a segunda tem que vir 1 (indice criado).
select
  (select count(*) from (
     select nome from centros_custo where fazenda_id is null
     group by nome having count(*) > 1
   ) x) as nomes_globais_repetidos,
  (select count(*) from pg_indexes
     where schemaname = 'public' and indexname = 'uq_centro_custo_global') as indice_criado,
  (select count(*) from centros_custo)                          as centros_total,
  (select count(*) from centros_custo where fazenda_id is null) as centros_globais;
