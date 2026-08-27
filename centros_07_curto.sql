-- centros_07 CURTO - mesma coisa do arquivo grande, sem os comentarios.
-- Rodar depois do centros_05. Nao mexe em lancamento.

do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_name='centros_custo' and column_name='classe') then
    raise exception 'RODE O centros_05 PRIMEIRO';
  end if;
end $$;

with de_para(nome_norm, classe_certa, sub_certa) as (values
  ('MAO DE OBRA OPERACIONAL',          'MAO-DE-OBRA DE OPERACIONAL',                                              'OPERACIONAL | MAO DE OBRA OPERACIONAL'),
  ('MANUTENCAO DE MAQUINAS E FROTA',   'MANUTENCAO DE TRATORES, CAMINHOES, MAQUINAS, EQUIPAMENTOS E IMPLEMENTOS', 'OPERACIONAL | MANUTENCAO GERAL DA FAZENDA'),
  ('SERVICOS TECNICOS / CONSULTORIA',  'SERVICOS TECNICOS PROFISSIONAIS (CONSULTORIAS DE CAMPO)',                 'OPERACIONAL | PRESTACAO DE SERVICOS'),
  ('DESPESAS COM VEICULOS',            'DESPESAS COM VEICULOS - ADMINISTRACAO',                                   'ADM | DESPESAS COM ADMINISTRACAO'),
  ('DESPESAS COM INSTALACOES',         'DESPESAS COM INSTALACOES - ADMINISTRACAO',                                'ADM | DESPESAS COM ADMINISTRACAO'),
  ('JUROS E ENCARGOS DE FINANCIAMENTO','DESPESAS FINANCEIRAS',                                                    'FINANCIAMENTOS | DESPESAS FINANCEIRAS'),
  ('VENDAS',                           'PRODUCAO AGROPECUARIA',                                                   'ATIVIDADES OPERACIONAIS')
)
update centros_custo c
   set classe = d.classe_certa,
       subcategoria = coalesce(c.subcategoria, d.sub_certa),
       updated_at = now()
  from de_para d
 where plano_norm(c.nome) = d.nome_norm
   and c.classe is distinct from d.classe_certa;

update centros_custo c
   set ativo = false, updated_at = now()
 where plano_norm(c.nome) in ('COMPRA DE ANIMAIS PARA ENGORDA','MANUTENCAO DE VEICULOS LEVES')
   and c.ativo
   and not exists (select 1 from lancamentos_financeiros l where l.centro_id = c.id);

select 1 as ordem, 'Centros que ganharam classe do Conag' as item, count(*)::text as valor, 'esperado: 7' as situacao
from centros_custo
where plano_norm(nome) in ('MAO DE OBRA OPERACIONAL','MANUTENCAO DE MAQUINAS E FROTA','SERVICOS TECNICOS / CONSULTORIA',
                           'DESPESAS COM VEICULOS','DESPESAS COM INSTALACOES','VENDAS','JUROS E ENCARGOS DE FINANCIAMENTO')
  and plano_norm(classe) <> plano_norm(nome)
union all
select 2, 'Lancamentos que passam a cair em classe do Conag', count(*)::text, 'esperado: 1.375'
from lancamentos_financeiros l join centros_custo c on c.id = l.centro_id
where plano_norm(c.nome) in ('MAO DE OBRA OPERACIONAL','MANUTENCAO DE MAQUINAS E FROTA','SERVICOS TECNICOS / CONSULTORIA',
                             'DESPESAS COM VEICULOS','DESPESAS COM INSTALACOES','VENDAS','JUROS E ENCARGOS DE FINANCIAMENTO')
union all
select 3, 'Centros vazios desativados', count(*)::text, 'esperado: 2'
from centros_custo where not ativo
  and plano_norm(nome) in ('COMPRA DE ANIMAIS PARA ENGORDA','MANUTENCAO DE VEICULOS LEVES')
union all
select 4, 'Centros ativos', count(*)::text, 'eram 64'
from centros_custo where ativo
union all
select 5, 'Lancamentos', count(*)::text, 'NAO pode ter mudado'
from lancamentos_financeiros
union all
select 6, 'Total lancado', round(sum(valor),2)::text, 'NAO pode ter mudado'
from lancamentos_financeiros
order by ordem;
