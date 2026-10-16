-- ============================================================
-- CONFERE, COM OS DADOS REAIS, O QUE CADA PESSOA ENXERGA NA VIEW
--
-- RODAR NO PROJETO DO LAVOURA/MATRIZ (kmkystqgpvmzrccxvyaz), depois do
-- seguranca_02_view_so_para_quem_tem_permissao.sql. So le: o unico que cria
-- e uma tabela temporaria (some quando a conexao fecha).
--
-- Para cada pessoa ativa o script faz o que o aplicativo faz na hora de ler a
-- view: assume o papel de quem esta logado ("authenticated") com o codigo
-- dela, conta quantas linhas da view ela enxerga e volta a ser quem era.
-- Compara com o que a regra manda (tudo / so pecuaria / nada) e escreve ok
-- ou DIFERENTE na ultima coluna.
--
-- A primeira linha da lista mostra o total da view para o dono do banco,
-- para comparar.
-- ============================================================

drop table if exists pg_temp.como_ve;
create temp table como_ve (
  nome text, papel text, deve_ver text,
  linhas_vistas bigint, linhas_pecuaria bigint, linhas_de_outras bigint, situacao text);

do $conf$
declare
  r        record;
  total    bigint;
  pec      bigint;
  vistas   bigint;
  vpec     bigint;
  deve     text;
  viu      text;
begin
  select count(*), count(*) filter (where atividade = 'pecuaria')
    into total, pec
    from public.lancamentos_rateados;
  insert into como_ve values ('(todas as linhas da view)', '-', '-', total, pec, total - pec, '-');

  for r in select id, nome, papel, permissoes from public.profiles where ativo order by nome loop
    deve := case
      when r.papel in ('admin', 'proprietario') then 'tudo'
      when r.permissoes->>'matriz_resultados' in ('visualizar', 'editar')
        or r.permissoes->>'matriz_financeiro' in ('visualizar', 'editar') then 'tudo'
      when exists (select 1
                     from unnest(array['pec_financeiro', 'pec_resultados', 'vendas',
                                       'confinamento', 'pasto', 'cria', 'lotesGeral']) k
                    where r.permissoes->>k in ('visualizar', 'editar')) then 'so pecuaria'
      else 'nada'
    end;

    perform set_config('request.jwt.claims', json_build_object('sub', r.id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', r.id::text, true);
    execute 'set local role authenticated';
    select count(*), count(*) filter (where atividade = 'pecuaria')
      into vistas, vpec
      from public.lancamentos_rateados;
    execute 'reset role';

    viu := case
      when vistas = 0 then 'nada'
      when vistas = total then 'tudo'
      when vistas = vpec and vpec = pec then 'so pecuaria'
      else 'ESTRANHO'
    end;
    insert into como_ve values (r.nome, r.papel, deve, vistas, vpec, vistas - vpec,
                                case when viu = deve then 'ok' else 'DIFERENTE (viu ' || viu || ')' end);
  end loop;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end
$conf$;

select * from como_ve
 order by (nome like '(%') desc, deve_ver, nome;
