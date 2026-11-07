-- ============================================================
-- COMPRA DE ANIMAIS, passo 3: separa matriz de giro nas compras lancadas a mao
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- O QUE FAZ: 8 compras de animais lancadas a mao estao no centro "INVESTIMENTO EM ANIMAIS", que
-- e o nome da classe e nao diz se e matriz ou giro. O app separa pelo centro de custo; este script
-- passa cada uma para o centro certo, conforme o Eduardo disse:
--   matriz -> COMPRA DE MATRIZES PARA REPRODUCAO:  #490 e #491 (R$ 460.525,00 juntas), #492 (R$ 144.524,71,
--             a descricao do lancamento diz matriz), #494 (R$ 72.000,00), #496 e #497 (R$ 179.600,00 juntas),
--             #508 (R$ 30.400,00)
--   giro   -> COMPRA DE ANIMAIS PARA RECRIA, ENGORDA E ABATE:  #502 (R$ 5.800,00, bezerro macho de corte)
-- So muda o centro de custo: valor, data, fornecedor e atividade ficam como estao.
--
-- TUDO OU NADA: para e diz o que viu se algum lancamento nao estiver como esperado (outro centro, outro
-- valor, outro tipo), ou se nao houver exatamente 1 centro de cada destino. Guarda o centro antigo em
-- zz_backup_classifica_animais_2026_11_06 (fechada: so o dono do banco le). Rodar de novo recusa.
--
-- PARA DESFAZER:
--   update lancamentos_financeiros l set centro_custo_id = b.centro_custo_id
--     from zz_backup_classifica_animais_2026_11_06 b where b.id = l.id;
-- ============================================================
do $classifica$
declare
  c_matriz bigint;
  c_giro bigint;
  n int;
  a record;
  achados int;
  soma numeric;
  atualizadas int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_classifica_animais_2026_11_06') is not null then
    raise exception 'Este script ja rodou (a copia zz_backup_classifica_animais_2026_11_06 existe). Nao mexo em nada.';
  end if;

  select count(*), min(id) into n, c_matriz from centros_custo
   where translate(upper(nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') like 'COMPRA DE MATRIZES%';
  if n <> 1 then
    raise exception 'Achei % centro(s) COMPRA DE MATRIZES (esperava 1). Nao mexo em nada.', n;
  end if;
  select count(*), min(id) into n, c_giro from centros_custo
   where translate(upper(nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') like 'COMPRA DE ANIMAIS%';
  if n <> 1 then
    raise exception 'Achei % centro(s) COMPRA DE ANIMAIS (esperava 1). Nao mexo em nada.', n;
  end if;

  create temp table alvo (ids bigint[], soma numeric, destino text) on commit drop;
  insert into alvo values
    (array[490, 491], 460525.00, 'matriz'),
    (array[492],      144524.71, 'matriz'),
    (array[494],       72000.00, 'matriz'),
    (array[496, 497], 179600.00, 'matriz'),
    (array[508],       30400.00, 'matriz'),
    (array[502],        5800.00, 'giro');

  for a in select * from alvo loop
    select count(*), coalesce(sum(l.valor), 0) into achados, soma
      from lancamentos_financeiros l
      join centros_custo c on c.id = l.centro_custo_id
     where l.id = any (a.ids) and l.tipo = 'investimento'
       and translate(upper(c.nome), 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC') = 'INVESTIMENTO EM ANIMAIS';
    if achados <> array_length(a.ids, 1) or soma <> a.soma then
      raise exception 'Lancamento(s) % nao estao como esperado (achei % no centro INVESTIMENTO EM ANIMAIS, somando R$ %, esperava R$ %). Nao mexo em nada.',
        a.ids, achados, soma, a.soma;
    end if;
  end loop;

  create table zz_backup_classifica_animais_2026_11_06 as
    select id, centro_custo_id from lancamentos_financeiros
     where id in (select unnest(ids) from alvo);
  alter table zz_backup_classifica_animais_2026_11_06 enable row level security;
  revoke all on zz_backup_classifica_animais_2026_11_06 from anon, authenticated;

  update lancamentos_financeiros l
     set centro_custo_id = case when l.id in (select unnest(ids) from alvo where destino = 'matriz') then c_matriz else c_giro end
   where l.id in (select unnest(ids) from alvo);
  get diagnostics atualizadas = row_count;
  if atualizadas <> 8 then
    raise exception 'Atualizei % lancamento(s), esperava 8. Desfeito.', atualizadas;
  end if;
end
$classifica$;

select c.nome as item,
       count(*)::text || ' lancamento(s)' as valor,
       'R$ ' || round(sum(l.valor), 2)::text || ' | ids ' || string_agg(l.id::text, ',' order by l.id) as situacao
  from lancamentos_financeiros l
  join centros_custo c on c.id = l.centro_custo_id
 where l.id in (select id from zz_backup_classifica_animais_2026_11_06)
 group by c.nome
 order by c.nome;
