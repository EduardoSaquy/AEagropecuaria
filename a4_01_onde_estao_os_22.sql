-- ============================================================
-- A4: ONDE ESTAO OS 22 LANCAMENTOS EM CENTRO DE CUSTO DO LADO ERRADO
--
-- SO LEITURA. NAO ALTERA NADA. Cole inteiro no editor do Supabase e rode.
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
--
-- A saude_do_banco_01 marcou o item A4: lancamentos de RECEITA presos em centro de custo de
-- SAIDA (e o contrario: despesa/investimento em centro de ENTRADA). Eram 22 receitas (R$ 339 mil, abril/2023,
-- importadas do ERP: ajuste de saldo bancario, outras movimentacoes de caixa e uma da casa-sede).
-- O Eduardo quer resolver. Antes de mexer em qualquer coisa, este arquivo mostra tres coisas numa tabela so:
--
--   1) LANCAMENTO  cada lancamento do lado errado: id, data, valor, tipo, atividade, de onde veio, o centro
--                  onde esta hoje (nome, lado, grupo) e o comeco da descricao;
--   2) PAR         para cada centro onde eles estao, o centro do lado CERTO com o mesmo nome (se existir):
--                  e o destino mais provavel, sem precisar escolher nada;
--   3) ENTRADA     todos os centros de ENTRADA ativos e quantas receitas cada um tem hoje: a lista de onde
--                  se pode colocar o que nao tiver par.
--
-- Coluna "valor": dinheiro (lancamento) ou quantidade (par e entrada). Nada daqui entra no repositorio:
-- a descricao pode ter nome de pessoa. Cole o resultado na conversa.
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
errados as (
  select l.id, l.tipo, l.atividade, l.valor, l.data, l.mes, l.erp_id, l.criado_por, l.descricao,
         c.id as centro_id, c.nome as centro, c.tipo as centro_tipo, c.subcategoria
    from lancamentos_financeiros l
    join centros_custo c on c.id = l.centro_custo_id
   where (l.tipo = 'receita' and c.tipo = 'saida')
      or (l.tipo in ('despesa', 'investimento') and c.tipo = 'entrada')
),
norm as (
  -- mesmo nome sem acento, sem diferenca de maiuscula e sem espaco repetido
  select c.id, c.nome, c.tipo, c.subcategoria, coalesce(c.ativo, true) as ativo,
         btrim(regexp_replace(translate(upper(coalesce(c.nome, '')),
           E'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
           'AAAAAEEEEIIIIOOOOOUUUUC'), '\s+', ' ', 'g')) as chave
    from centros_custo c
),
pares as (
  select distinct e.centro_id, e.centro as de_nome, e.centro_tipo as de_tipo, p.id as para_id, p.nome as para_nome, p.tipo as para_tipo
    from errados e
    join norm a on a.id = e.centro_id
    join norm p on p.chave = a.chave and p.id <> a.id and p.tipo <> e.centro_tipo and p.ativo
)
select ordem, item, valor, detalhe from (
  select 1 as ordem, 1 as sub,
         'LANCAMENTO #' || e.id || ' ' || coalesce(e.data::text, e.mes, 'sem data') || ' ' || e.tipo as item,
         e.valor::numeric as valor,
         'atividade ' || e.atividade || ' | veio ' || case when e.erp_id is not null then 'do ERP'
                                                         when e.criado_por like 'ERP (acerto%' then 'do acerto de 21/10'
                                                         else 'lancado a mao' end
         || ' | centro #' || e.centro_id || ' "' || e.centro || '" (' || e.centro_tipo || ')'
         || coalesce(' | ' || e.subcategoria, '')
         || ' | ' || left(coalesce(e.descricao, ''), 45) as detalhe
    from errados e
  union all
  select 2, 1,
         'PAR do centro #' || p.centro_id || ' "' || p.de_nome || '"',
         p.para_id::numeric,
         'centro do lado certo: #' || p.para_id || ' "' || p.para_nome || '" (' || p.para_tipo || ')'
    from pares p
  union all
  select 2, 2,
         'SEM PAR o centro #' || x.centro_id || ' "' || x.centro || '"',
         null::numeric,
         'nao existe centro ativo do outro lado com o mesmo nome: escolher um centro do lado certo (para receita vale a lista ENTRADA)'
    from (select distinct centro_id, centro from errados) x
   where not exists (select 1 from pares p where p.centro_id = x.centro_id)
  union all
  select 3, 1,
         'ENTRADA #' || n.id || ' "' || n.nome || '"',
         (select count(*) from lancamentos_financeiros l where l.centro_custo_id = n.id and l.tipo = 'receita')::numeric,
         'receitas hoje neste centro' || coalesce(' | ' || n.subcategoria, '')
    from norm n
   where n.tipo = 'entrada' and n.ativo
) t
order by ordem, sub, item;
