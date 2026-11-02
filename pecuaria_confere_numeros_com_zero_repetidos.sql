-- ============================================================
-- Pecuaria - SO LEITURA. Animais que virariam o mesmo numero ao
-- tirar o zero a esquerda (ex.: 002 e 2, machos). Mostra lote,
-- situacao, quando foi cadastrado, quantas pesagens e a ultima,
-- para decidir se e o mesmo animal ou outro.
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

with grupos as (
  select a.id, a.numero, a.sexo, a.status, a.nome, a.raca, a.criado_em, a.criado_por,
         coalesce(nullif(ltrim(trim(a.numero),'0'),''),'0') as base,
         l.nome as lote, l.destino
    from animais a left join lotes l on l.id = a.lote_id
),
repetidos as (
  select sexo, base from grupos
   group by sexo, base
  having count(*) > 1 and bool_or(trim(numero) ~ '^0+[0-9]+$')
)
select g.base || ' (' || coalesce(g.sexo,'sem sexo') || ')' as grupo,
       'numero ' || g.numero as item,
       coalesce(g.lote,'sem lote') || ' (' || coalesce(g.destino,'-') || ') | ' || g.status
         || coalesce(' | nome: ' || g.nome, '')
         || ' | cadastrado em ' || to_char(g.criado_em, 'DD/MM/YYYY') || coalesce(' por ' || g.criado_por, '') as valor,
       (select count(*) from pesagens_animais p where trim(p.numero_animal) = trim(g.numero))::text
         || ' pesagem(ns)'
         || coalesce(', ultima ' || (select max(p.peso_kg)::text from pesagens_animais p where trim(p.numero_animal) = trim(g.numero)
                                       and p.id = (select max(p2.id) from pesagens_animais p2 where trim(p2.numero_animal) = trim(g.numero))) || ' kg', '') as situacao
  from grupos g
  join repetidos r on r.sexo is not distinct from g.sexo and r.base = g.base
 order by g.base::numeric, g.numero;
