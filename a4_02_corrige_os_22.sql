-- ============================================================
-- A4: CORRIGE OS 22 LANCAMENTOS DE RECEITA QUE ESTAO EM CENTRO DE CUSTO DE SAIDA
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- O QUE ESTA ERRADO
--   22 lancamentos de RECEITA (R$ 339.094,22, importados do ERP, 2023) estao em tres centros de custo que
--   sao de SAIDA. Pela consulta a4_01 (que o Eduardo rodou):
--     18 lancamentos, R$ 299.890,29  no centro de saida "AJUSTE DE SALDO BANCARIO"
--      3 lancamentos, R$  37.203,93  no centro de saida "OUTRAS MOVIMENTACOES DE CAIXA"
--      1 lancamento,  R$   2.000,00  no centro de saida "MANUTENCAO E PRESTADORES DE SERVICO NA CASA-SEDE"
--   Nao existe centro de ENTRADA com esses nomes (o banco nao deixa dois centros com o mesmo nome).
--
-- O QUE ESTE SCRIPT FAZ (tudo ou nada, num bloco so)
--   1. confere que sao exatamente esses 22, com esses valores, nesses centros. Se algo for diferente,
--      RECUSA e diz o que achou: nao mexe em nada;
--   2. guarda uma copia dos 22 lancamentos e dos 3 centros (tabelas zz_backup_a4_..., fechadas a quem esta logado) e confere que
--      a copia saiu completa;
--   3. cria 3 centros de ENTRADA irmaos, com o mesmo nome mais " (ENTRADA)", copiando o grupo e a classe do centro
--      de saida (se um deles ja existir de uma rodada anterior, reaproveita);
--   4. passa cada lancamento para o centro irmao. SO O CENTRO MUDA: valor, data, atividade, tipo e o rateio
--      ficam como estao, entao nenhum total do app muda (o grupo do centro e o mesmo, entao o bloco do fluxo
--      de caixa da aba Empresa tambem nao).
--   Rodar de novo e seguro: se os 22 ja estiverem nos centros de entrada, so avisa "JA FEITO". Se o conserto foi feito e depois
--   desfeito, pode rodar de novo: a copia da rodada anterior e trocada por uma nova (so se ela bater com o estado de hoje).
--   A conferencia no fim tem que mostrar tudo OK.
--
-- PARA DESFAZER: ver o fim do arquivo (devolve os 22 aos centros de antes e apaga os centros novos, se vazios).
-- ============================================================

do $a4$
declare
  v_ajuste bigint[] := array[22959,22960,22961,22962,22963,22964,22965,22966,22967,22969,22970,22971,22973,22975,22976,22977,22978,22982];
  v_outras bigint[] := array[22922,22972,22980];
  v_casa   bigint[] := array[22931];
  v_todos  bigint[];
  c_velhos bigint[] := array[139, 120, 186];    -- centros de SAIDA onde estao hoje (ajuste, outras, casa-sede)
  v_novos  bigint[] := array[null, null, null]::bigint[];
  v_n int; v_soma numeric; v_i int; v_nome text; v_id bigint; v_tipo text; v_linhas int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  v_todos := v_ajuste || v_outras || v_casa;

  -- ja feito?
  select count(*) into v_n
    from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
   where l.id = any(v_todos) and l.tipo = 'receita' and c.tipo = 'entrada';
  if v_n = 22 then
    raise notice 'JA FEITO: os 22 lancamentos ja estao em centros de entrada. Nada a fazer.';
    return;
  end if;

  -- 1) confere que e exatamente o que a consulta mostrou
  select count(*), coalesce(sum(valor), 0) into v_n, v_soma
    from lancamentos_financeiros where id = any(v_todos) and tipo = 'receita';
  if v_n <> 22 or v_soma <> 339094.22 then
    raise exception 'RECUSADO: esperava 22 receitas somando R$ 339094,22 e achei % somando R$ %. Nao mexi em nada. Me mande esta mensagem.', v_n, v_soma;
  end if;
  for v_i in 1..3 loop
    select count(*), coalesce(sum(valor), 0) into v_n, v_soma
      from lancamentos_financeiros
     where centro_custo_id = c_velhos[v_i]
       and id = any(case v_i when 1 then v_ajuste when 2 then v_outras else v_casa end);
    if v_n <> (case v_i when 1 then 18 when 2 then 3 else 1 end)
       or v_soma <> (case v_i when 1 then 299890.29 when 2 then 37203.93 else 2000.00 end) then
      raise exception 'RECUSADO: o grupo % (centro #%) devia ter % lancamentos e R$ % e tem % e R$ %. Nao mexi em nada. Me mande esta mensagem.',
        v_i, c_velhos[v_i], case v_i when 1 then 18 when 2 then 3 else 1 end,
        case v_i when 1 then 299890.29 when 2 then 37203.93 else 2000.00 end, v_n, v_soma;
    end if;
    select nome, tipo into v_nome, v_tipo from centros_custo where id = c_velhos[v_i];
    if v_tipo is distinct from 'saida'
       or upper(coalesce(v_nome, '')) not like (case v_i when 1 then 'AJUSTE DE SALDO%' when 2 then 'OUTRAS MOVIMENTA%' else 'MANUTEN%CASA-SEDE%' end) then
      raise exception 'RECUSADO: o centro #% e "%" (%), nao o esperado. Nao mexi em nada. Me mande esta mensagem.', c_velhos[v_i], v_nome, v_tipo;
    end if;
  end loop;

  -- 2) copia de seguranca (fechada: so quem tem acesso ao banco le)
  -- Se ja existe copia de uma rodada anterior (por exemplo, o conserto foi feito e depois DESFEITO), so a reaproveito se
  -- ela bater com o estado de hoje; ai a troco por uma nova. Se nao bater, RECUSA: ela pode ser a unica copia do que existia antes.
  if to_regclass('public.zz_backup_a4_lanc_2026_11_09') is not null or to_regclass('public.zz_backup_a4_centros_2026_11_09') is not null then
    if to_regclass('public.zz_backup_a4_lanc_2026_11_09') is null or to_regclass('public.zz_backup_a4_centros_2026_11_09') is null then
      raise exception 'RECUSADO: so uma das duas copias de seguranca de uma rodada anterior existe. Nao mexi em nada. Me mande esta mensagem.';
    end if;
    execute 'select count(*) from lancamentos_financeiros l join zz_backup_a4_lanc_2026_11_09 b
              on b.id = l.id and b.centro_custo_id = l.centro_custo_id and b.valor = l.valor and b.tipo = l.tipo' into v_n;
    execute 'select count(*) from centros_custo c join zz_backup_a4_centros_2026_11_09 b on b.id = c.id and b.nome = c.nome and b.tipo = c.tipo' into v_linhas;
    if v_n <> 22 or v_linhas <> 3 then
      raise exception 'RECUSADO: ja existe copia de seguranca de uma rodada anterior e ela nao bate com o estado de hoje (% de 22 lancamentos e % de 3 centros iguais). Nao mexi em nada. Me mande esta mensagem.', v_n, v_linhas;
    end if;
    execute 'drop table zz_backup_a4_lanc_2026_11_09, zz_backup_a4_centros_2026_11_09';
    raise notice 'Copia de seguranca da rodada anterior (desfeita) trocada por uma nova.';
  end if;
  execute 'create table zz_backup_a4_lanc_2026_11_09 as select * from lancamentos_financeiros where id = any($1)' using v_todos;
  execute 'create table zz_backup_a4_centros_2026_11_09 as select * from centros_custo where id = any($1)' using c_velhos;
  execute 'select count(*) from zz_backup_a4_lanc_2026_11_09' into v_n;
  execute 'select count(*) from zz_backup_a4_centros_2026_11_09' into v_linhas;
  if v_n <> 22 or v_linhas <> 3 then
    raise exception 'ERRO: a copia de seguranca saiu com % lancamentos e % centros (era para ser 22 e 3). Desfeito (tudo ou nada). Me mande esta mensagem.', v_n, v_linhas;
  end if;
  execute 'alter table zz_backup_a4_lanc_2026_11_09 enable row level security';
  execute 'alter table zz_backup_a4_centros_2026_11_09 enable row level security';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on zz_backup_a4_lanc_2026_11_09, zz_backup_a4_centros_2026_11_09 from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on zz_backup_a4_lanc_2026_11_09, zz_backup_a4_centros_2026_11_09 from authenticated';
  end if;

  -- 3) os tres centros de entrada irmaos
  for v_i in 1..3 loop
    select nome || ' (ENTRADA)' into v_nome from centros_custo where id = c_velhos[v_i];
    select id, tipo into v_id, v_tipo from centros_custo where lower(nome) = lower(v_nome);
    if v_id is null then
      insert into centros_custo (nome, tipo, subcategoria, classe, ativo)
        select v_nome, 'entrada', subcategoria, classe, true from centros_custo where id = c_velhos[v_i]
        returning id into v_id;
    elsif v_tipo is distinct from 'entrada' then
      raise exception 'RECUSADO: ja existe um centro "%" que nao e de entrada. Nao fiz nada. Me mande esta mensagem.', v_nome;
    end if;
    v_novos[v_i] := v_id;
  end loop;

  -- 4) so o centro muda
  for v_i in 1..3 loop
    update lancamentos_financeiros set centro_custo_id = v_novos[v_i]
     where centro_custo_id = c_velhos[v_i]
       and id = any(case v_i when 1 then v_ajuste when 2 then v_outras else v_casa end);
    get diagnostics v_linhas = row_count;
    if v_linhas <> (case v_i when 1 then 18 when 2 then 3 else 1 end) then
      raise exception 'ERRO: mudei % lancamentos no grupo % em vez de %. Desfeito (tudo ou nada). Me mande esta mensagem.',
        v_linhas, v_i, case v_i when 1 then 18 when 2 then 3 else 1 end;
    end if;
  end loop;
  raise notice 'Feito: 22 lancamentos passaram para os centros de entrada %, % e %.', v_novos[1], v_novos[2], v_novos[3];
end
$a4$;

-- CONFERENCIA: tudo tem que dizer OK
select item, valor, situacao from (
  select 1 as ord, 'os 22 estao em centro de entrada' as item,
         (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
           where l.id = any(array[22959,22960,22961,22962,22963,22964,22965,22966,22967,22969,22970,22971,22973,22975,22976,22977,22978,22982,22922,22972,22980,22931])
             and c.tipo = 'entrada')::text as valor,
         case when (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id
                     where l.id = any(array[22959,22960,22961,22962,22963,22964,22965,22966,22967,22969,22970,22971,22973,22975,22976,22977,22978,22982,22922,22972,22980,22931])
                       and c.tipo = 'entrada') = 22 then 'OK' else 'ATENCAO' end as situacao
  union all
  select 2, 'valor dos 22 (nao muda: R$ 339.094,22)',
         (select coalesce(sum(valor), 0) from lancamentos_financeiros
           where id = any(array[22959,22960,22961,22962,22963,22964,22965,22966,22967,22969,22970,22971,22973,22975,22976,22977,22978,22982,22922,22972,22980,22931]))::text,
         case when (select coalesce(sum(valor), 0) from lancamentos_financeiros
                     where id = any(array[22959,22960,22961,22962,22963,22964,22965,22966,22967,22969,22970,22971,22973,22975,22976,22977,22978,22982,22922,22972,22980,22931])) = 339094.22
              then 'OK' else 'ATENCAO' end
  union all
  select 3, 'receitas que ainda estao em centro de saida (em todo o banco)',
         (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id where l.tipo = 'receita' and c.tipo = 'saida')::text,
         case when (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id where l.tipo = 'receita' and c.tipo = 'saida') = 0
              then 'OK' else 'ATENCAO' end
  union all
  select 4, 'despesas ou investimentos que estao em centro de entrada (em todo o banco)',
         (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id where l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada')::text,
         case when (select count(*) from lancamentos_financeiros l join centros_custo c on c.id = l.centro_custo_id where l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada') = 0
              then 'OK' else 'ATENCAO' end
  union all
  select 5, 'centros de entrada novos "(ENTRADA)"',
         (select count(*) from centros_custo where tipo = 'entrada' and nome like '% (ENTRADA)')::text,
         case when (select count(*) from centros_custo where tipo = 'entrada' and nome like '% (ENTRADA)') = 3 then 'OK' else 'ATENCAO' end
  union all
  select 6, 'lancamentos em atividade geral sem as partes do rateio (tem que ser 0)',
         (select count(*) from lancamentos_financeiros l where l.atividade = 'geral' and abs(l.valor) >= 1
             and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id))::text,
         case when (select count(*) from lancamentos_financeiros l where l.atividade = 'geral' and abs(l.valor) >= 1
                       and not exists (select 1 from lancamento_rateios r where r.lancamento_id = l.id)) = 0 then 'OK' else 'ATENCAO' end
) t
order by ord;

-- ============================================================
-- PARA DESFAZER (copie so este trecho e rode, se um dia precisar):
--
--   update lancamentos_financeiros l set centro_custo_id = b.centro_custo_id
--     from zz_backup_a4_lanc_2026_11_09 b where l.id = b.id;
--   delete from centros_custo c
--    where c.tipo = 'entrada'
--      and lower(c.nome) in (select lower(nome) || ' (entrada)' from zz_backup_a4_centros_2026_11_09)
--      and not exists (select 1 from lancamentos_financeiros l where l.centro_custo_id = c.id);
--
-- Depois de confirmar que esta tudo certo, as duas copias podem ser apagadas:
--   drop table zz_backup_a4_lanc_2026_11_09, zz_backup_a4_centros_2026_11_09;
-- ============================================================
