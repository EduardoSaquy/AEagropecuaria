-- ============================================================
-- QUEM PODE APAGAR O QUE, HOJE
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- So leitura. Nao altera nada.
--
-- Uma consulta so - o editor do Supabase mostra uma por vez.
--
-- COMO LER
--   regra_hoje       o que a politica de DELETE daquela tabela exige
--   quem_apaga       traduzido
--   risco            se restringir essa tabela quebra alguma rotina do app
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO';
  end if;
end $$;

with maquinaria as (
  -- Tabelas que o app apaga por CONTA PROPRIA, fora de um clique em
  -- Excluir: desfazer um passo que falhou, ou trocar as linhas filhas ao
  -- editar o pai. Restringir estas quebra rotina de quem nao e dono.
  select unnest(array[
    'movimentos',                 -- refeitos ao editar saida de racao e pasto
    'pesagens_animais',           -- desfazer manejo que falhou
    'reproducao_custos',          -- desfazer manejo que falhou
    'diagnosticos_gestacionais',  -- desfazer manejo que falhou
    'protocolos_inseminacao',     -- desfazer manejo que falhou
    'desmamas',                   -- desfazer manejo que falhou
    'pesagens',                   -- desfazer pesagem sem detalhe
    'abates',                     -- desfazer venda pela metade
    'producoes_racao',            -- desfazer producao sem baixa de estoque
    'titulo_rateios',             -- trocados ao editar o titulo
    'funcionario_atividades',     -- trocadas ao editar o funcionario
    'fazenda_atividades'          -- trocadas ao editar a fazenda
  ]) as tabela
)
select
  p.tablename                                   as tabela,
  p.policyname                                  as politica,
  coalesce(p.qual, '(sem condicao)')            as regra_hoje,
  case
    when p.qual is null                         then 'QUALQUER UM logado'
    when p.qual like '%pode_excluir%'           then 'so admin/proprietario'
    when p.qual like '%is_admin%'               then 'so admin (proprietario NAO)'
    when p.qual like '%tem_permissao%'          then 'quem tem a permissao do modulo'
    when p.qual = 'true'                        then 'QUALQUER UM logado'
    else 'outra regra'
  end                                           as quem_apaga,
  case
    when m.tabela is not null
      then 'NAO RESTRINGIR - o app apaga sozinho aqui'
    else 'pode restringir'
  end                                           as risco
from pg_policies p
left join maquinaria m on m.tabela = p.tablename
where p.schemaname = 'public' and p.cmd = 'DELETE'
order by
  case when m.tabela is not null then 0 else 1 end,
  p.tablename;
