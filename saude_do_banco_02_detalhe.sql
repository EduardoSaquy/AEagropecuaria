-- ============================================================
-- SAUDE DO BANCO, PARTE 2: o detalhe do que a saude_do_banco_01 apontou
--
-- SO LEITURA. NAO ALTERA NADA. Cole inteiro no editor do Supabase e rode.
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- Abre os 4 itens que a parte 1 marcou ATENCAO:
--   A4  lancamentos em centro de custo do lado errado (receita em centro de SAIDA,
--       despesa em centro de ENTRADA): resumo por centro e a lista;
--   A8  mesmo fornecedor, valor e dia repetidos: separa por ORIGEM (importacao do ERP,
--       acerto de 21/10, lancado a mao) e por documento, mostra o que sobraria se ficasse
--       um so de cada, e os maiores casos de cada classe. Repetido NAO quer dizer
--       duplicado: parcelas iguais no mesmo dia, o mesmo documento dividido em centros e
--       as divisoes do app aparecem aqui, cada uma na sua classe;
--   B2  conta a pagar/receber cujas partes do rateio nao fecham o valor;
--   D   lotes ativos sem pesagem ha 60 dias e pesagens com peso implausivel (com a pesagem
--       de antes e a de depois do mesmo lote, para ver qual era o numero certo).
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
end
$trava$;

with
l as (
  select f.id, f.tipo, f.atividade, f.valor, f.erp_id, f.criado_por, f.centro_custo_id,
         coalesce(f.data, f.vencimento) as quando,
         coalesce(nullif(btrim(f.fornecedor), ''), f.descricao, '') as quem,
         btrim(regexp_replace(regexp_replace(translate(upper(coalesce(nullif(btrim(f.fornecedor), ''), f.descricao, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'AAAAAEEEEIIIIOOOOOUUUUC'), '[^A-Z ]', ' ', 'g'), '\s+', ' ', 'g')) as forn_norm,
         case when f.erp_id is not null then 'importacao'
              when f.criado_por like 'ERP (acerto%' then 'acerto'
              else 'a mao' end as origem,
         coalesce(f.observacao like 'Dividido entre atividades%', false) as dividido,
         substring(f.observacao from '^ERP [0-9]+') as documento
    from lancamentos_financeiros f
),

-- ---------- A4: centro de custo do lado errado ----------
a4 as (
  select l.id, l.tipo, l.atividade, l.valor, l.quando, l.quem, l.origem, c.nome as centro, c.tipo as centro_tipo
    from l join centros_custo c on c.id = l.centro_custo_id
   where (l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada')
      or (l.tipo = 'receita' and c.tipo = 'saida')
),
a4_resumo as (
  select tipo, centro, centro_tipo, count(*) as n, sum(valor) as soma from a4 group by tipo, centro, centro_tipo
),
a4_lista as (
  select a4.*, row_number() over (order by valor desc, id) as rk from a4
),

-- ---------- A8: repetidos, por origem e documento ----------
g as (
  select tipo, forn_norm, valor, quando,
         count(*) as n,
         array_agg(id order by id) as ids,
         min(quem) as quem,
         string_agg(distinct origem, ' + ' order by origem) as origens,
         count(distinct centro_custo_id) as centros,
         count(distinct atividade) as ativs,
         count(documento) as com_doc,
         count(distinct documento) as docs,
         bool_and(dividido) as todos_divididos
    from l
   where quando is not null and forn_norm <> '' and valor >= 50
   group by tipo, forn_norm, valor, quando
  having count(*) > 1
),
gc as (
  select g.*,
         valor * (n - 1) as sobra,
         case when todos_divididos then 'dividido pelo app (certo)'
              else origens || case when com_doc = n and docs = 1 then ' | mesmo documento do ERP'
                                   when com_doc = 0 then ' | sem documento'
                                   else ' | documentos diferentes' end
         end as classe
    from g
),
gc_resumo as (
  select classe, count(*) as grupos, sum(n) as linhas, sum(sobra) as sobra from gc group by classe
),
gc_lista as (
  select gc.*, row_number() over (partition by classe order by sobra desc, ids[1]) as rk from gc
),

-- ---------- B2: rateio da conta que nao fecha ----------
b2 as (
  select t.id, t.descricao, t.valor, t.vencimento, t.situacao, p.soma, p.n,
         (select coalesce(sum(b.valor), 0) from titulo_baixas b where b.titulo_id = t.id) as baixado
    from titulos t
    join (select titulo_id, sum(valor) as soma, count(*) as n from titulo_rateios group by titulo_id) p
      on p.titulo_id = t.id
   where abs(t.valor - p.soma) > 0.05
),

-- ---------- D: pecuaria ----------
d2 as (
  select lo.id, lo.nome, lo.numero_animais, lo.data_inicio,
         (select max(p.data) from pesagens p where p.lote_id = lo.id) as ultima
    from lotes lo
   where lo.data_fim is null and coalesce(lo.numero_animais, 0) > 0
     and not exists (select 1 from pesagens p where p.lote_id = lo.id and p.data >= current_date - 60)
),
d3 as (
  select x.*, lo.nome as lote
    from (select p.id, p.lote_id, p.data, p.peso_medio_kg,
                 lag(p.peso_medio_kg) over w as antes, lead(p.peso_medio_kg) over w as depois
            from pesagens p window w as (partition by p.lote_id order by p.data, p.id)) x
    left join lotes lo on lo.id = x.lote_id
   where x.peso_medio_kg < 20 or x.peso_medio_kg > 1000
),

saida as (
  -- A4
  select 'A4' as chave, 0 as o1, 0::numeric as o2,
         'A4) resumo: ' || tipo || ' em centro de ' || upper(centro_tipo) || ' | ' || centro as item,
         n::text || ' lancamentos' as valor,
         'R$ ' || round(soma, 2)::text as situacao
    from a4_resumo
  union all
  select 'A4', 1, -valor, '   #' || id || ' ' || to_char(quando, 'DD/MM/YYYY') || ' ' || left(quem, 34),
         'R$ ' || round(valor, 2)::text,
         tipo || ' | ' || atividade || ' | ' || origem || ' | ' || left(centro, 40)
    from a4_lista where rk <= 30
  -- A8
  union all
  select 'A8', 0, -sobra, 'A8) resumo: ' || classe,
         grupos::text || ' grupos, ' || linhas::text || ' linhas',
         'sobraria R$ ' || round(sobra, 2)::text || ' se ficasse um so de cada'
    from gc_resumo
  union all
  select 'A8', 1, -sobra, '   #' || array_to_string(ids[1:4], ',') || ' ' || to_char(quando, 'DD/MM/YYYY') || ' ' || left(quem, 30),
         'R$ ' || round(valor, 2)::text || ' x ' || n::text,
         classe || ' | ' || centros::text || ' centro(s) | ' || ativs::text || ' atividade(s)'
    from gc_lista where rk <= 6
  -- B2
  union all
  select 'B2', 0, 0, 'B2) conta #' || id || ' ' || to_char(vencimento, 'DD/MM/YYYY') || ' ' || left(descricao, 40),
         'R$ ' || round(valor, 2)::text,
         situacao || ' | partes somam R$ ' || round(soma, 2)::text || ' em ' || n::text || ' parte(s) | diferenca R$ '
         || round(valor - soma, 2)::text || ' | baixado R$ ' || round(baixado, 2)::text
    from b2
  union all
  select 'B2', 1, r.id, '   parte: ' || r.atividade || ' | ' || left(c.nome, 40) || ' | competencia ' || r.competencia,
         'R$ ' || round(r.valor, 2)::text, 'conta #' || r.titulo_id
    from titulo_rateios r join centros_custo c on c.id = r.centro_custo_id
   where r.titulo_id in (select id from b2)
  -- D2
  union all
  select 'D2', 0, coalesce(current_date - ultima, 99999), 'D2) lote #' || id || ' ' || left(nome, 40),
         coalesce(numero_animais, 0)::text || ' animais',
         'inicio ' || coalesce(to_char(data_inicio, 'DD/MM/YYYY'), '?') || ' | '
         || case when ultima is null then 'nunca foi pesado'
                 else 'ultima pesagem ' || to_char(ultima, 'DD/MM/YYYY') || ' (ha ' || (current_date - ultima)::text || ' dias)' end
    from d2
  -- D3
  union all
  select 'D3', 0, id, 'D3) pesagem #' || id || ' ' || to_char(data, 'DD/MM/YYYY') || ' | lote ' || coalesce(left(lote, 40), '?'),
         peso_medio_kg::text || ' kg',
         'antes ' || coalesce(antes::text, '-') || ' kg | depois ' || coalesce(depois::text, '-') || ' kg'
    from d3
)
select item, valor, situacao from saida order by chave, o1, o2, item;
