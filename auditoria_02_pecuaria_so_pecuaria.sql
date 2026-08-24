-- ============================================================
-- QUEM TEM PERMISSAO DE PECUARIA SO LE LANCAMENTO DE PECUARIA
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).
-- Cole inteiro e rode. Corrige o auditoria_01.
--
-- ------------------------------------------------------------
-- O ERRO QUE EU INTRODUZI
--
-- No auditoria_01 eu acrescentei pec_financeiro e pec_resultados as
-- politicas de lancamentos_financeiros para destravar a Pecuaria. So que
-- escrevi assim:
--
--   using (is_admin()
--       or tem_permissao('matriz_financeiro','visualizar')
--       or tem_permissao('pec_financeiro','visualizar')   <- sem limite
--       or tem_permissao('pec_resultados','visualizar'))
--
-- lancamentos_financeiros guarda as QUATRO atividades no mesmo lugar:
-- pecuaria, cana, graos e geral. Como a condicao nao olha a atividade da
-- linha, quem tem permissao de pecuaria passou a poder ler a tabela
-- inteira - inclusive o financeiro da cana e dos cereais.
--
-- O app da Pecuaria filtra por atividade na tela, entao nada aparece
-- errado para quem usa o app. Mas RLS nao e a tela: quem chamar a API
-- direto com o proprio login le tudo. Foi exatamente esse raciocinio -
-- "a tela ja filtra" - que produziu o furo.
--
-- Hoje isso alcanca uma pessoa: o Irlei, consultor, com
-- pec_financeiro = visualizar.
--
-- ------------------------------------------------------------
-- A CORRECAO
--
-- A permissao da pecuaria passa a valer SO para linhas de atividade
-- 'pecuaria'. matriz_financeiro continua valendo para todas, que e o
-- proposito dele: e a permissao de quem cuida do consolidado.
-- ============================================================

do $escopo$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;

  drop policy if exists "ve lancamentos"     on lancamentos_financeiros;
  drop policy if exists "lanca"              on lancamentos_financeiros;
  drop policy if exists "edita lancamentos"  on lancamentos_financeiros;
  drop policy if exists "exclui lancamentos" on lancamentos_financeiros;

  -- LEITURA
  create policy "ve lancamentos" on lancamentos_financeiros for select
    using (
      is_admin()
      or tem_permissao('matriz_financeiro','visualizar')
      or (atividade = 'pecuaria' and (
            tem_permissao('pec_financeiro','visualizar')
         or tem_permissao('pec_resultados','visualizar')))
    );

  -- INSERCAO
  -- A venda registrada no AE Pecuaria cria a receita junto com o abate, e
  -- ela e sempre de atividade 'pecuaria'.
  create policy "lanca" on lancamentos_financeiros for insert
    with check (
      is_admin()
      or tem_permissao('matriz_financeiro','editar')
      or (atividade = 'pecuaria' and tem_permissao('pec_resultados','editar'))
    );

  -- ALTERACAO
  -- Precisa valer nos dois lados: a linha ANTES da mudanca (using) e a
  -- linha DEPOIS (with check). Sem o with check limitado, alguem poderia
  -- pegar um lancamento de pecuaria e mudar a atividade dele para cana,
  -- escapando do proprio limite.
  create policy "edita lancamentos" on lancamentos_financeiros for update
    using (
      is_admin()
      or tem_permissao('matriz_financeiro','editar')
      or (atividade = 'pecuaria' and tem_permissao('pec_resultados','editar'))
    )
    with check (
      is_admin()
      or tem_permissao('matriz_financeiro','editar')
      or (atividade = 'pecuaria' and tem_permissao('pec_resultados','editar'))
    );

  -- EXCLUSAO
  create policy "exclui lancamentos" on lancamentos_financeiros for delete
    using (
      is_admin()
      or tem_permissao('matriz_financeiro','editar')
      or (atividade = 'pecuaria' and tem_permissao('pec_resultados','editar'))
    );

  raise notice 'Permissao de pecuaria limitada a atividade pecuaria.';
end
$escopo$;


-- ============================================================
-- CONFERENCIA 1 - AS POLITICAS CITAM A ATIVIDADE
--
-- As quatro linhas tem que mencionar atividade = 'pecuaria' junto das
-- chaves pec_. Se alguma citar pec_ sem citar atividade, sobrou furo.
-- ============================================================
select cmd as comando, policyname as politica,
       case when coalesce(qual,'') || coalesce(with_check,'') like '%pec_%'
             and coalesce(qual,'') || coalesce(with_check,'') like '%pecuaria%'
            then 'limitada a pecuaria'
            when coalesce(qual,'') || coalesce(with_check,'') like '%pec_%'
            then '*** PEC SEM LIMITE DE ATIVIDADE ***'
            else 'nao cita pecuaria' end as situacao
from pg_policies
where schemaname = 'public' and tablename = 'lancamentos_financeiros'
order by cmd, policyname;


-- ============================================================
-- CONFERENCIA 2 - QUEM DE FATO GANHA ACESSO
--
-- Diferente da conferencia do auditoria_01, esta olha o VALOR da
-- permissao e nao so a existencia da chave. Quem aparece aqui e quem
-- realmente enxerga o financeiro da pecuaria - e so o dela.
-- ============================================================
select nome, usuario, papel,
       permissoes ->> 'pec_financeiro'    as pec_financeiro,
       permissoes ->> 'pec_resultados'    as pec_resultados,
       case when coalesce(permissoes ->> 'pec_resultados','nenhum') = 'editar'
            then 'le e lanca (pecuaria)' else 'so le (pecuaria)' end as alcance
from profiles
where ativo
  and papel not in ('admin','proprietario')
  and (   permissoes ->> 'pec_financeiro' in ('visualizar','editar')
       or permissoes ->> 'pec_resultados' in ('visualizar','editar'))
order by nome;
