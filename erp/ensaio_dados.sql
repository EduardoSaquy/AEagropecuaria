-- Fazendas, culturas e centros do ensaio local. Nao roda no Supabase.
delete from lancamentos_financeiros; delete from talhoes_areas;
delete from centros_custo; delete from culturas; delete from fazendas;
insert into fazendas (nome, estado) values ('Fazenda Invernada','SP'),('Fazenda Santa Alice','SP'),
 ('Fazenda Palhadao','SP'),('Fazenda Palmito','SP'),('Fazenda Mata Verde','SP'),
 ('Fazenda das Tres Marias','SP'),('Fazenda Reunidas','SP');
insert into culturas (nome, frente) values ('Cana','cana'),('Soja','cereais'),('Milho','cereais'),
 ('Sorgo','cereais'),('Milheto','cereais'),('Abacate','cereais');
insert into centros_custo (nome, tipo) values
 ('COMBUSTÍVEIS DA OPERAÇÃO AGROPECUÁRIA','saida'),('Mão de Obra Operacional','saida'),
 ('Manutenção de Máquinas e Frota','saida'),('Serviços Técnicos / Consultoria','saida'),
 ('Despesas com Veículos','saida'),('Despesas com Instalações','saida'),('Vendas','entrada'),
 ('COMPRA DE ANIMAIS PARA ENGORDA','saida'),('Juros e Encargos de Financiamento','saida'),
 ('MANUTENÇÃO DE VEÍCULOS LEVES','saida'),('TRIBUTOS','saida'),('NUTRIÇÃO ANIMAL','saida');
insert into lancamentos_financeiros (tipo,atividade,centro_custo_id,descricao,valor,mes)
 select 'despesa','cana',(select id from centros_custo where nome='TRIBUTOS'),'hist',3785.44,'2026-07'
 from generate_series(1,2760);
