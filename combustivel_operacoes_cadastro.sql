-- ===================================================================
-- Cadastra as operações de campo do Combustível — lista que o Eduardo
-- passou, todas com frente = 'geral' (servem pra todas as atividades).
-- "nome" é único na tabela, então rodar de novo não duplica (só ignora
-- quem já existe).
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='operacoes_combustivel') then
    raise exception 'operacoes_combustivel nao existe - rode o combustivel_unificado_01_schema.sql primeiro';
  end if;
end $$;

insert into operacoes_combustivel (nome, frente, ativo) values
  ('Sulcação', 'geral', true),
  ('Pulverização', 'geral', true),
  ('Quebra-Lombo', 'geral', true),
  ('Corte de Sequeira', 'geral', true),
  ('Deslocamento', 'geral', true),
  ('Catação Herbicida', 'geral', true),
  ('Grade Pesada', 'geral', true),
  ('Grade Niveladora', 'geral', true),
  ('Grade Intermediária', 'geral', true),
  ('Arado de Aiveca', 'geral', true),
  ('Eliminador de Soqueira', 'geral', true),
  ('Subsolador', 'geral', true),
  ('Terraciador', 'geral', true),
  ('Adubador', 'geral', true),
  ('Esparramar Calcário', 'geral', true),
  ('Esparramar Gesso', 'geral', true),
  ('Esparramar Esterco', 'geral', true),
  ('Plantio', 'geral', true),
  ('Colheita', 'geral', true),
  ('Prestador de Serviço', 'geral', true),
  ('Bazuca', 'geral', true),
  ('Calda Pronta', 'geral', true),
  ('Irrigação', 'geral', true),
  ('Salgar Cocho', 'geral', true),
  ('Trato Confinamento', 'geral', true),
  ('Carregar Insumo', 'geral', true),
  ('Transporte', 'geral', true),
  ('Compactação Silo', 'geral', true),
  ('Roçadeira', 'geral', true),
  ('Outros', 'geral', true)
on conflict (nome) do nothing;

select 1::numeric as ordem, 'operações cadastradas' as item, count(*)::text as valor,
       'esperado: 30 (menos as que já existiam)' as situacao
  from operacoes_combustivel where frente='geral';
