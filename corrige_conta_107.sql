-- ============================================================
-- CONTA A PAGAR #107 (BATERIA PARA O TRATOR BH180, R$ 1.100,00): tira a parte repetida do rateio
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
--
-- O QUE ACHOU A saude_do_banco_02: a conta vale R$ 1.100,00, mas tem DUAS partes de rateio
-- exatamente iguais (cana | MANUTENCAO DA FROTA..., competencia 2026-10, R$ 1.100,00 cada),
-- somando R$ 2.200,00. Quando a conta fosse paga, o lancamento sairia com o dobro.
--
-- O QUE FAZ (tudo ou nada): so mexe se a conta #107 estiver como o relatorio descreveu:
--   . existe, nao esta cancelada, nada foi pago (valor baixado = 0), valor R$ 1.100,00;
--   . tem exatamente 2 partes, e as duas sao identicas (atividade, centro, fazenda, competencia,
--     valor, talhao, observacao);
-- guarda copia da parte que sai em zz_backup_conta107_2026_11_06 (fechada: so o dono do banco le),
-- apaga a de maior id (fica a mais antiga) e confere que a soma das partes fechou em R$ 1.100,00.
-- Se qualquer coisa nao bater, para e diz o que viu; nada e alterado.
-- Rodar de novo recusa (a copia ja existe).
--
-- PARA DESFAZER (se precisar):
--   insert into titulo_rateios (titulo_id, fazenda_id, atividade, centro_custo_id, competencia, valor, talhao_id, observacao)
--   select titulo_id, fazenda_id, atividade, centro_custo_id, competencia, valor, talhao_id, observacao
--     from zz_backup_conta107_2026_11_06;
-- ============================================================
do $conta107$
declare
  t record;
  n int;
  distintas int;
  soma numeric;
  sai bigint;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.zz_backup_conta107_2026_11_06') is not null then
    raise exception 'Este script ja rodou (a copia zz_backup_conta107_2026_11_06 existe). Nao mexo em nada.';
  end if;

  select * into t from titulos where id = 107;
  if not found then
    raise exception 'A conta #107 nao existe. Nao mexo em nada.';
  end if;
  if t.cancelado then
    raise exception 'A conta #107 esta cancelada. Nao mexo em nada.';
  end if;
  if coalesce(t.valor_baixado, 0) <> 0 then
    raise exception 'A conta #107 ja tem pagamento (R$ %). Nao mexo em nada.', t.valor_baixado;
  end if;
  if t.valor <> 1100 then
    raise exception 'A conta #107 vale R$ %, nao R$ 1.100,00. Nao mexo em nada.', t.valor;
  end if;

  select count(*), count(distinct (atividade, centro_custo_id, fazenda_id, competencia, valor, talhao_id, observacao)),
         coalesce(sum(valor), 0)
    into n, distintas, soma
    from titulo_rateios where titulo_id = 107;
  if n <> 2 then
    raise exception 'A conta #107 tem % parte(s) de rateio, nao 2. Nao mexo em nada.', n;
  end if;
  if distintas <> 1 then
    raise exception 'As 2 partes da conta #107 nao sao identicas. Nao mexo em nada.';
  end if;
  if soma <> 2200 then
    raise exception 'As partes da conta #107 somam R$ %, nao R$ 2.200,00. Nao mexo em nada.', soma;
  end if;

  select max(id) into sai from titulo_rateios where titulo_id = 107;

  create table zz_backup_conta107_2026_11_06 as select * from titulo_rateios where id = sai;
  alter table zz_backup_conta107_2026_11_06 enable row level security;
  revoke all on zz_backup_conta107_2026_11_06 from anon, authenticated;

  delete from titulo_rateios where id = sai;

  select count(*), coalesce(sum(valor), 0) into n, soma from titulo_rateios where titulo_id = 107;
  if n <> 1 or soma <> 1100 then
    raise exception 'Depois de apagar, a conta #107 ficou com % parte(s) somando R$ %. Desfeito.', n, soma;
  end if;
end
$conta107$;

select 'conta #107' as item,
       (select count(*) from titulo_rateios where titulo_id = 107)::text || ' parte(s)' as valor,
       'somam R$ ' || (select sum(valor) from titulo_rateios where titulo_id = 107)::text
         || ' | conta vale R$ ' || (select valor from titulos where id = 107)::text as situacao;
