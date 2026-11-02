-- ============================================================
-- Pecuaria - bois 001, 002 e 003 (confinamento) viram 1000, 2000 e
-- 3000 (Eduardo, 02/11/2026). Com a regra "zero a esquerda nao
-- conta", 001 e 1 seriam o mesmo numero, mas sao animais diferentes:
-- os bezerros 1, 2 e 3 (nome Alice, Bezerros Invernada) ficam como
-- estao. Mesmo padrao do 512000. Leva junto as pesagens de cada boi.
-- Depois disso rode de novo pecuaria_numero_sem_zero_a_esquerda.sql.
-- Para sem gravar nada se 1000/2000/3000 ja forem de outro macho.
-- Repetivel.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

do $$
declare v_ocupado text; r record; n_ani int := 0; n_pes int := 0; n int;
begin
  select string_agg(numero, ', ') into v_ocupado from animais
   where sexo = 'macho' and trim(numero) in ('1000','2000','3000');
  if v_ocupado is not null and exists (select 1 from animais where sexo='macho' and trim(numero) in ('001','002','003')) then
    raise exception 'Nada foi gravado: ja existe macho com o numero %. Escolha outro numero.', v_ocupado;
  end if;
  for r in select * from (values ('001','1000'), ('002','2000'), ('003','3000')) as t(velho, novo) loop
    update animais set numero = r.novo where sexo = 'macho' and trim(numero) = r.velho;
    get diagnostics n = row_count; n_ani := n_ani + n;
    update pesagens_animais set numero_animal = r.novo where trim(numero_animal) = r.velho;
    get diagnostics n = row_count; n_pes := n_pes + n;
  end loop;
  raise notice 'bois renumerados %, pesagens levadas junto %', n_ani, n_pes;
end $$;

-- CONFERENCIA (uma consulta so)
select item, valor, situacao from (
  select 1 as ordem, 'boi ' || a.numero as item,
         coalesce(l.nome,'sem lote') || ' | ' || (select count(*) from pesagens_animais p where trim(p.numero_animal) = a.numero) || ' pesagem(ns)' as valor,
         'OK' as situacao
    from animais a left join lotes l on l.id = a.lote_id
   where a.sexo = 'macho' and a.numero in ('1000','2000','3000')
  union all
  select 2, 'machos ainda com 001/002/003', count(*)::text,
         case when count(*) = 0 then 'OK, pode rodar o SQL dos zeros' else 'DIFERENTE' end
    from animais where sexo = 'macho' and trim(numero) in ('001','002','003')
  union all
  select 3, 'pesagens ainda com 001/002/003', count(*)::text,
         case when count(*) = 0 then 'OK' else 'DIFERENTE' end
    from pesagens_animais where trim(numero_animal) in ('001','002','003')
) z
order by ordem, item;
