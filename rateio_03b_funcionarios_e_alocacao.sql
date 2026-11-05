-- ============================================================
-- CONFERENCIA (SO LEITURA): funcionarios cadastrados e a alocacao de cada um
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz). Cole inteiro e rode.
-- Nao altera nada. Devolve UMA tabela.
--
-- Serve para dividir o salario de cada pessoa pela alocacao que a aba
-- Funcionarios guarda (funcionario_atividades: % em cada atividade).
-- Nao mostra CPF, salario nem Pix (essas colunas nao existem nestas tabelas).
-- ============================================================

do $trava$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz).';
  end if;
  if to_regclass('public.funcionarios') is null or to_regclass('public.funcionario_atividades') is null then
    raise exception 'Faltam as tabelas funcionarios/funcionario_atividades.';
  end if;
end
$trava$;

select f.id, f.nome, f.cargo,
       case when f.ativo then 'ativo' else 'inativo' end as situacao,
       coalesce(string_agg(fa.atividade || ' ' || fa.percentual::text || '%', ' / ' order by fa.atividade)
                  filter (where coalesce(fa.percentual, 0) > 0),
                'SEM alocacao cadastrada') as alocacao
  from funcionarios f
  left join funcionario_atividades fa on fa.funcionario_id = f.id
 group by f.id, f.nome, f.cargo, f.ativo
 order by f.ativo desc, f.nome;
