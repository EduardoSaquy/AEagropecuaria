-- ============================================================
-- Pecuaria - lanca as inseminacoes (IATF) de outubro/2026
--   Novilhas (17/10/2026)          -> lote "Novilhas eradas ( inseminacao)"
--   Vacas mes 09 (19/10/2026)      -> lote "Vacas 09/10"
--   Vacas solteiras (19/10/2026)   -> lote "Vacas Vazia Santa Alice"
-- 239 linhas da planilha.
--
-- Custo por inseminacao: R$ 46,30 = semen R$ 22,70 + protocolo
-- hormonal R$ 23,60 (mao de obra fica na consultoria, nao entra).
-- Raca do touro: nelore (NE). O app nao tem campo para o NOME do
-- touro: ele vai em reproducao_custos.item, junto com a linha da
-- planilha ("IATF 19/10/2026 linha 12 - touro DOURADO"). O item
-- tambem e a chave que impede lancar a mesma linha duas vezes.
--
-- Faz o mesmo que o app faz ao salvar uma inseminacao:
--   - grava em reproducao_custos (lote, data, vaca, raca do touro,
--     qual inseminacao, custo);
--   - vaca ja cadastrada (femea, mesmo numero) vai para o lote da
--     inseminacao; vaca sem cadastro e criada femea/nelore no lote.
--   - nao mexe em lotes.numero_animais (o app tambem nao mexe).
-- "Qual inseminacao": 1a, ou 2a/3a se a mesma vaca ja tiver
-- inseminacao nos 120 dias anteriores.
--
-- Numero com texto (regra de 27/10/2026: numero so com algarismos,
-- o texto vai para o Nome do animal):
--   "N ES"      -> vaca N com "ES" no Nome, se ja existir assim;
--                  se nao existir vaca N nenhuma, cria N com Nome ES;
--                  se existir vaca N SEM "ES" no Nome, ou se o N puro
--                  tambem estiver na planilha, fica PENDENTE.
--   "19 ES"     -> 19099 (renumerada em 27/10/2026).
--   "358 DESC." -> vaca 358 (DESC. e observacao; se criar, Nome descarte).
--   "0,3" etc.  -> PENDENTE (a planilha transformou o brinco em
--                  decimal; precisa do numero real).
--   "S/N"       -> inseminacao lancada sem numero de vaca (conta no
--                  lote e no custo), sem cadastro de animal.
--   numero que nao existe mas existe com zero a esquerda (57 x 057)
--   -> PENDENTE. Numero repetido na planilha -> PENDENTE.
-- Pendente nao grava nada; aparece na conferencia do fim.
--
-- Repetivel: rodar de novo nao duplica (chave = item).
-- ============================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema='public' and table_name='animais' and column_name='nome') then
    raise exception 'Falta a coluna animais.nome - rode antes pecuaria_parto_aborto_obito_nome_animal.sql';
  end if;
end $$;

drop table if exists tmp_iatf;
create temp table tmp_iatf (
  linha int primary key, grupo text, planilha text, touro text, data date,
  lote_id bigint, numero text, sufixo text,
  acao text, motivo text, animal_id bigint, lote_antigo text, nome_novo text,
  qual text, chave text
);

insert into tmp_iatf (linha, grupo, planilha, touro, data) values
  (1, 'V09', '4', 'DOURADO', '2026-10-19'),
  (2, 'V09', '7', 'INDICE SINO', '2026-10-19'),
  (3, 'V09', '9', 'INDICE SINO', '2026-10-19'),
  (4, 'V09', '12', 'DOURADO', '2026-10-19'),
  (5, 'V09', '16', 'DOURADO', '2026-10-19'),
  (6, 'V09', '17', 'INDICE SINO', '2026-10-19'),
  (7, 'V09', '19', 'DOURADO', '2026-10-19'),
  (8, 'V09', '22', 'DOURADO', '2026-10-19'),
  (9, 'V09', '24', 'INDICE SINO', '2026-10-19'),
  (10, 'V09', '26', 'DOURADO', '2026-10-19'),
  (11, 'V09', '29', 'INDICE SINO', '2026-10-19'),
  (12, 'V09', '35', 'INDICE SINO', '2026-10-19'),
  (13, 'V09', '38', 'DOURADO', '2026-10-19'),
  (14, 'V09', '40', 'DOURADO', '2026-10-19'),
  (15, 'V09', '41', 'INDICE SINO', '2026-10-19'),
  (16, 'V09', '46', 'DOURADO', '2026-10-19'),
  (17, 'V09', '47', 'INDICE SINO', '2026-10-19'),
  (18, 'V09', '48', 'INDICE SINO', '2026-10-19'),
  (19, 'V09', '52', 'DOURADO', '2026-10-19'),
  (20, 'V09', '55', 'INDICE SINO', '2026-10-19'),
  (21, 'V09', '57', 'DOURADO', '2026-10-19'),
  (22, 'V09', '59', 'DOURADO', '2026-10-19'),
  (23, 'V09', '60', 'DOURADO', '2026-10-19'),
  (24, 'V09', '76', 'DOURADO', '2026-10-19'),
  (25, 'V09', '80', 'INDICE SINO', '2026-10-19'),
  (26, 'V09', '83', 'INDICE SINO', '2026-10-19'),
  (27, 'V09', '89', 'DOURADO', '2026-10-19'),
  (28, 'V09', '97', 'DOURADO', '2026-10-19'),
  (29, 'V09', '100', 'INDICE SINO', '2026-10-19'),
  (30, 'V09', '101', 'DOURADO', '2026-10-19'),
  (31, 'V09', '109', 'DOURADO', '2026-10-19'),
  (32, 'V09', '110', 'DOURADO', '2026-10-19'),
  (33, 'V09', '122', 'DOURADO', '2026-10-19'),
  (34, 'V09', '173', 'DOURADO', '2026-10-19'),
  (35, 'V09', '198', 'INDICE SINO', '2026-10-19'),
  (36, 'V09', '305', 'DOURADO', '2026-10-19'),
  (37, 'V09', '335', 'DOURADO', '2026-10-19'),
  (38, 'V09', '336', 'INDICE SINO', '2026-10-19'),
  (39, 'V09', '337', 'DOURADO', '2026-10-19'),
  (40, 'V09', '339', 'INDICE SINO', '2026-10-19'),
  (41, 'V09', '340', 'INDICE SINO', '2026-10-19'),
  (42, 'V09', '341', 'INDICE SINO', '2026-10-19'),
  (43, 'V09', '342', 'INDICE SINO', '2026-10-19'),
  (44, 'V09', '343', 'DOURADO', '2026-10-19'),
  (45, 'V09', '344', 'INDICE SINO', '2026-10-19'),
  (46, 'V09', '348', 'DOURADO', '2026-10-19'),
  (47, 'V09', '349', 'INDICE SINO', '2026-10-19'),
  (48, 'V09', '350', 'INDICE SINO', '2026-10-19'),
  (49, 'V09', '352', 'DOURADO', '2026-10-19'),
  (50, 'V09', '353', 'INDICE SINO', '2026-10-19'),
  (51, 'V09', '354', 'INDICE SINO', '2026-10-19'),
  (52, 'V09', '357', 'DOURADO', '2026-10-19'),
  (53, 'V09', '359', 'INDICE SINO', '2026-10-19'),
  (54, 'V09', '360', 'DOURADO', '2026-10-19'),
  (55, 'V09', '362', 'DOURADO', '2026-10-19'),
  (56, 'V09', '364', 'INDICE SINO', '2026-10-19'),
  (57, 'V09', '365', 'INDICE SINO', '2026-10-19'),
  (58, 'V09', '366', 'DOURADO', '2026-10-19'),
  (59, 'V09', '367', 'INDICE SINO', '2026-10-19'),
  (60, 'V09', '371', 'INDICE SINO', '2026-10-19'),
  (61, 'V09', '372', 'DOURADO', '2026-10-19'),
  (62, 'V09', '373', 'DOURADO', '2026-10-19'),
  (63, 'V09', '374', 'INDICE SINO', '2026-10-19'),
  (64, 'V09', '375', 'DOURADO', '2026-10-19'),
  (65, 'V09', '376', 'DOURADO', '2026-10-19'),
  (66, 'V09', '377', 'INDICE SINO', '2026-10-19'),
  (67, 'V09', '378', 'DOURADO', '2026-10-19'),
  (68, 'V09', '380', 'DOURADO', '2026-10-19'),
  (69, 'V09', '381', 'INDICE SINO', '2026-10-19'),
  (70, 'V09', '382', 'INDICE SINO', '2026-10-19'),
  (71, 'V09', '383', 'DOURADO', '2026-10-19'),
  (72, 'V09', '384', 'INDICE SINO', '2026-10-19'),
  (73, 'V09', '385', 'INDICE SINO', '2026-10-19'),
  (74, 'V09', '387', 'DOURADO', '2026-10-19'),
  (75, 'V09', '388', 'INDICE SINO', '2026-10-19'),
  (76, 'V09', '389', 'DOURADO', '2026-10-19'),
  (77, 'V09', '390', 'INDICE SINO', '2026-10-19'),
  (78, 'V09', '394', 'INDICE SINO', '2026-10-19'),
  (79, 'V09', '401', 'INDICE SINO', '2026-10-19'),
  (80, 'V09', '407', 'DOURADO', '2026-10-19'),
  (81, 'V09', '408', 'DOURADO', '2026-10-19'),
  (82, 'V09', '711', 'DOURADO', '2026-10-19'),
  (83, 'V09', '905', 'DOURADO', '2026-10-19'),
  (84, 'V09', '19 ES', 'DOURADO', '2026-10-19'),
  (85, 'V09', '24 ES', 'DOURADO', '2026-10-19'),
  (86, 'V09', '358 DESC.', 'INDICE SINO', '2026-10-19'),
  (87, 'V09', '37 ES', 'DOURADO', '2026-10-19'),
  (88, 'VSA', '0,3', 'MAGNO', '2026-10-19'),
  (89, 'VSA', '49', 'MAGNO', '2026-10-19'),
  (90, 'VSA', '78', 'INDICE SINO', '2026-10-19'),
  (91, 'VSA', '81', 'INDICE SINO', '2026-10-19'),
  (92, 'VSA', '84', 'INDICE SINO', '2026-10-19'),
  (93, 'VSA', '88', 'INDICE SINO', '2026-10-19'),
  (94, 'VSA', '92', 'DOURADO', '2026-10-19'),
  (95, 'VSA', '112', 'MAGNO', '2026-10-19'),
  (96, 'VSA', '118', 'MAGNO', '2026-10-19'),
  (97, 'VSA', '158', 'DOURADO', '2026-10-19'),
  (98, 'VSA', '722', 'MAGNO', '2026-10-19'),
  (99, 'VSA', '746', 'DOURADO', '2026-10-19'),
  (100, 'VSA', '748', 'DOURADO', '2026-10-19'),
  (101, 'VSA', '750', 'MAGNO', '2026-10-19'),
  (102, 'VSA', '753', 'MAGNO', '2026-10-19'),
  (103, 'VSA', '758', 'MAGNO', '2026-10-19'),
  (104, 'VSA', '759', 'MAGNO', '2026-10-19'),
  (105, 'VSA', '761', 'MAGNO', '2026-10-19'),
  (106, 'VSA', '764', 'DOURADO', '2026-10-19'),
  (107, 'VSA', '767', 'MAGNO', '2026-10-19'),
  (108, 'VSA', '768', 'DOURADO', '2026-10-19'),
  (109, 'VSA', '770', 'MAGNO', '2026-10-19'),
  (110, 'VSA', '773', 'MAGNO', '2026-10-19'),
  (111, 'VSA', '774', 'DOURADO', '2026-10-19'),
  (112, 'VSA', '775', 'MAGNO', '2026-10-19'),
  (113, 'VSA', '777', 'DOURADO', '2026-10-19'),
  (114, 'VSA', '779', 'INDICE SINO', '2026-10-19'),
  (115, 'VSA', '780', 'DOURADO', '2026-10-19'),
  (116, 'VSA', '781', 'MAGNO', '2026-10-19'),
  (117, 'VSA', '783', 'MAGNO', '2026-10-19'),
  (118, 'VSA', '785', 'DOURADO', '2026-10-19'),
  (119, 'VSA', '787', 'MAGNO', '2026-10-19'),
  (120, 'VSA', '788', 'MAGNO', '2026-10-19'),
  (121, 'VSA', '789', 'DOURADO', '2026-10-19'),
  (122, 'VSA', '791', 'MAGNO', '2026-10-19'),
  (123, 'VSA', '792', 'INDICE SINO', '2026-10-19'),
  (124, 'VSA', '799', 'DOURADO', '2026-10-19'),
  (125, 'VSA', '800', 'MAGNO', '2026-10-19'),
  (126, 'VSA', '801', 'INDICE SINO', '2026-10-19'),
  (127, 'VSA', '804', 'INDICE SINO', '2026-10-19'),
  (128, 'VSA', '805', 'INDICE SINO', '2026-10-19'),
  (129, 'VSA', '806', 'MAGNO', '2026-10-19'),
  (130, 'VSA', '807', 'MAGNO', '2026-10-19'),
  (131, 'VSA', '808', 'INDICE SINO', '2026-10-19'),
  (132, 'VSA', '818', 'MAGNO', '2026-10-19'),
  (133, 'VSA', '820', 'DOURADO', '2026-10-19'),
  (134, 'VSA', '821', 'INDICE SINO', '2026-10-19'),
  (135, 'VSA', '823', 'DOURADO', '2026-10-19'),
  (136, 'VSA', '828', 'MAGNO', '2026-10-19'),
  (137, 'VSA', '836', 'DOURADO', '2026-10-19'),
  (138, 'VSA', '837', 'DOURADO', '2026-10-19'),
  (139, 'VSA', '840', 'MAGNO', '2026-10-19'),
  (140, 'VSA', '852', 'MAGNO', '2026-10-19'),
  (141, 'VSA', '856', 'DOURADO', '2026-10-19'),
  (142, 'VSA', '857', 'MAGNO', '2026-10-19'),
  (143, 'VSA', '859', 'INDICE SINO', '2026-10-19'),
  (144, 'VSA', '860', 'MAGNO', '2026-10-19'),
  (145, 'VSA', '861', 'INDICE SINO', '2026-10-19'),
  (146, 'VSA', '875', 'MAGNO', '2026-10-19'),
  (147, 'VSA', '881', 'MAGNO', '2026-10-19'),
  (148, 'VSA', '887', 'INDICE SINO', '2026-10-19'),
  (149, 'VSA', '889', 'INDICE SINO', '2026-10-19'),
  (150, 'VSA', '893', 'INDICE SINO', '2026-10-19'),
  (151, 'VSA', '897', 'INDICE SINO', '2026-10-19'),
  (152, 'VSA', '900', 'MAGNO', '2026-10-19'),
  (153, 'VSA', '901', 'MAGNO', '2026-10-19'),
  (154, 'VSA', '0,1 ES', 'MAGNO', '2026-10-19'),
  (155, 'VSA', '0,3 ES', 'INDICE SINO', '2026-10-19'),
  (156, 'VSA', '0,6 ES', 'DOURADO', '2026-10-19'),
  (157, 'VSA', '0,7 ES', 'DOURADO', '2026-10-19'),
  (158, 'VSA', '11 ES', 'DOURADO', '2026-10-19'),
  (159, 'VSA', '15 ES', 'MAGNO', '2026-10-19'),
  (160, 'VSA', '26 ES', 'DOURADO', '2026-10-19'),
  (161, 'VSA', '28 ES', 'MAGNO', '2026-10-19'),
  (162, 'VSA', '33 ES', 'MAGNO', '2026-10-19'),
  (163, 'VSA', '34 ES', 'DOURADO', '2026-10-19'),
  (164, 'VSA', '36 ES', 'DOURADO', '2026-10-19'),
  (165, 'VSA', '40 ES', 'MAGNO', '2026-10-19'),
  (166, 'VSA', '45 ES', 'MAGNO', '2026-10-19'),
  (167, 'VSA', '50 ES', 'MAGNO', '2026-10-19'),
  (168, 'VSA', '50 ES', 'INDICE SINO', '2026-10-19'),
  (169, 'VSA', '53 ES', 'DOURADO', '2026-10-19'),
  (170, 'VSA', '54 ES', 'INDICE SINO', '2026-10-19'),
  (171, 'VSA', '56 ES', 'DOURADO', '2026-10-19'),
  (172, 'VSA', '59 ES', 'INDICE SINO', '2026-10-19'),
  (173, 'VSA', 'S/N', 'DOURADO', '2026-10-19'),
  (174, 'NOV', '77', 'DOURADO', '2026-10-17'),
  (175, 'NOV', '103', 'DOURADO', '2026-10-17'),
  (176, 'NOV', '104', 'DOURADO', '2026-10-17'),
  (177, 'NOV', '124', 'MAGNO', '2026-10-17'),
  (178, 'NOV', '125', 'DOURADO', '2026-10-17'),
  (179, 'NOV', '130', 'MAGNO', '2026-10-17'),
  (180, 'NOV', '135', 'DOURADO', '2026-10-17'),
  (181, 'NOV', '140', 'MAGNO', '2026-10-17'),
  (182, 'NOV', '141', 'MAGNO', '2026-10-17'),
  (183, 'NOV', '142', 'MAGNO', '2026-10-17'),
  (184, 'NOV', '145', 'MAGNO', '2026-10-17'),
  (185, 'NOV', '146', 'MAGNO', '2026-10-17'),
  (186, 'NOV', '149', 'DOURADO', '2026-10-17'),
  (187, 'NOV', '151', 'MAGNO', '2026-10-17'),
  (188, 'NOV', '152', 'DOURADO', '2026-10-17'),
  (189, 'NOV', '154', 'MAGNO', '2026-10-17'),
  (190, 'NOV', '157', 'DOURADO', '2026-10-17'),
  (191, 'NOV', '165', 'MAGNO', '2026-10-17'),
  (192, 'NOV', '168', 'DOURADO', '2026-10-17'),
  (193, 'NOV', '169', 'DOURADO', '2026-10-17'),
  (194, 'NOV', '170', 'MAGNO', '2026-10-17'),
  (195, 'NOV', '176', 'MAGNO', '2026-10-17'),
  (196, 'NOV', '191', 'MAGNO', '2026-10-17'),
  (197, 'NOV', '193', 'MAGNO', '2026-10-17'),
  (198, 'NOV', '194', 'MAGNO', '2026-10-17'),
  (199, 'NOV', '196', 'DOURADO', '2026-10-17'),
  (200, 'NOV', '197', 'MAGNO', '2026-10-17'),
  (201, 'NOV', '204', 'MAGNO', '2026-10-17'),
  (202, 'NOV', '205', 'MAGNO', '2026-10-17'),
  (203, 'NOV', '208', 'MAGNO', '2026-10-17'),
  (204, 'NOV', '209', 'MAGNO', '2026-10-17'),
  (205, 'NOV', '212', 'MAGNO', '2026-10-17'),
  (206, 'NOV', '214', 'MAGNO', '2026-10-17'),
  (207, 'NOV', '219', 'MAGNO', '2026-10-17'),
  (208, 'NOV', '223', 'MAGNO', '2026-10-17'),
  (209, 'NOV', '227', 'DOURADO', '2026-10-17'),
  (210, 'NOV', '229', 'DOURADO', '2026-10-17'),
  (211, 'NOV', '232', 'MAGNO', '2026-10-17'),
  (212, 'NOV', '233', 'DOURADO', '2026-10-17'),
  (213, 'NOV', '236', 'MAGNO', '2026-10-17'),
  (214, 'NOV', '244', 'MAGNO', '2026-10-17'),
  (215, 'NOV', '250', 'MAGNO', '2026-10-17'),
  (216, 'NOV', '251', 'MAGNO', '2026-10-17'),
  (217, 'NOV', '257', 'DOURADO', '2026-10-17'),
  (218, 'NOV', '267', 'MAGNO', '2026-10-17'),
  (219, 'NOV', '278', 'MAGNO', '2026-10-17'),
  (220, 'NOV', '281', 'DOURADO', '2026-10-17'),
  (221, 'NOV', '283', 'MAGNO', '2026-10-17'),
  (222, 'NOV', '284', 'DOURADO', '2026-10-17'),
  (223, 'NOV', '295', 'DOURADO', '2026-10-17'),
  (224, 'NOV', '311', 'DOURADO', '2026-10-17'),
  (225, 'NOV', '317', 'DOURADO', '2026-10-17'),
  (226, 'NOV', '330', 'DOURADO', '2026-10-17'),
  (227, 'NOV', '331', 'DOURADO', '2026-10-17'),
  (228, 'NOV', '361', 'MAGNO', '2026-10-17'),
  (229, 'NOV', '392', 'DOURADO', '2026-10-17'),
  (230, 'NOV', '886', 'DOURADO', '2026-10-17'),
  (231, 'NOV', '907', 'DOURADO', '2026-10-17'),
  (232, 'NOV', '927', 'MAGNO', '2026-10-17'),
  (233, 'NOV', 'S/N', 'MAGNO', '2026-10-17'),
  (234, 'NOV', 'S/N', 'MAGNO', '2026-10-17'),
  (235, 'NOV', 'S/N', 'MAGNO', '2026-10-17'),
  (236, 'NOV', 'S/N', 'MAGNO', '2026-10-17'),
  (237, 'NOV', 'S/N', 'MAGNO', '2026-10-17'),
  (238, 'NOV', 'S/N', 'MAGNO', '2026-10-17'),
  (239, 'NOV', 'S/N', 'DOURADO', '2026-10-17');

do $$
declare
  r record;
  v_lote_v09 bigint; v_lote_vsa bigint; v_lote_nov bigint;
  v_qtd int; v_nomes text;
  v_fem record;
  v_zero text;
  v_semsexo int;
  v_cri int; v_mov int; v_ins int;
begin
  -- Lotes: tem que achar exatamente um de cada
  select count(*), min(id), string_agg(nome, ' / ') into v_qtd, v_lote_v09, v_nomes
    from lotes where lower(trim(nome)) = 'vacas 09/10';
  if v_qtd <> 1 then raise exception 'Lote "Vacas 09/10": achei % (%). Confira o nome.', v_qtd, coalesce(v_nomes,'nenhum'); end if;

  select count(*), min(id), string_agg(nome, ' / ') into v_qtd, v_lote_vsa, v_nomes
    from lotes where lower(nome) like '%vazi%' and lower(nome) like '%alice%';
  if v_qtd <> 1 then
    select string_agg(nome, ' / ') into v_nomes from lotes where lower(nome) like '%vaz%' or lower(nome) like '%alice%' or lower(nome) like '%solt%';
    raise exception 'Lote "Vacas Vazia Santa Alice": achei % com vazi+alice. Lotes parecidos: %', v_qtd, coalesce(v_nomes,'nenhum');
  end if;

  select count(*), min(id), string_agg(nome, ' / ') into v_qtd, v_lote_nov, v_nomes
    from lotes where lower(trim(nome)) like 'novilhas eradas%';
  if v_qtd <> 1 then raise exception 'Lote "Novilhas eradas": achei % (%). Confira o nome.', v_qtd, coalesce(v_nomes,'nenhum'); end if;

  update tmp_iatf set lote_id = case grupo when 'V09' then v_lote_v09 when 'VSA' then v_lote_vsa else v_lote_nov end,
                      chave = 'IATF ' || to_char(data,'DD/MM/YYYY') || ' linha ' || linha || ' - touro ' || touro;

  -- Numero e sufixo de cada linha
  update tmp_iatf set acao = 'sem_numero' where upper(trim(planilha)) in ('S/N','SN','S/ N');
  update tmp_iatf set acao = 'pendente', motivo = 'numero com virgula na planilha: qual e o brinco de verdade?'
   where acao is null and planilha like '%,%';
  update tmp_iatf set numero = trim(planilha) where acao is null and trim(planilha) ~ '^[0-9]+$';
  update tmp_iatf set numero = substring(trim(planilha) from '^([0-9]+)'),
                      sufixo = upper(trim(both ' .' from substring(trim(planilha) from '^[0-9]+\s+(.*)$')))
   where acao is null and numero is null and trim(planilha) ~ '^[0-9]+\s+\S';
  update tmp_iatf set numero = '19099', sufixo = null where upper(trim(planilha)) = '19 ES';
  update tmp_iatf set acao = 'pendente', motivo = 'numero nao reconhecido'
   where acao is null and numero is null;

  -- Resolve o cadastro de cada vaca
  for r in select * from tmp_iatf where acao is null order by linha loop
    select a.id, a.lote_id, a.status, coalesce(a.nome,'') as nome, l.nome as lote_nome into v_fem
      from animais a left join lotes l on l.id = a.lote_id
     where lower(trim(a.numero)) = r.numero and a.sexo = 'femea';

    select string_agg(a.numero || ' (' || coalesce(l.nome,'sem lote') || ')', ', ') into v_zero
      from animais a left join lotes l on l.id = a.lote_id
     where a.sexo = 'femea' and ltrim(trim(a.numero),'0') = ltrim(r.numero,'0')
       and lower(trim(a.numero)) <> r.numero;

    select count(*) into v_semsexo from animais a
     where lower(trim(a.numero)) = r.numero and a.sexo is null;

    if v_fem.id is not null then
      if r.sufixo = 'ES' and upper(v_fem.nome) !~ '(^|[^A-Z])ES([^A-Z]|$)' then
        update tmp_iatf set acao='pendente',
          motivo='ja existe a vaca ' || r.numero || ' sem ES no Nome (lote ' || coalesce(v_fem.lote_nome,'nenhum') || '): e a mesma vaca ou outra?'
         where linha = r.linha;
      elsif v_fem.status <> 'ativo' then
        update tmp_iatf set acao='pendente',
          motivo='a vaca ' || r.numero || ' esta cadastrada como ' || v_fem.status
         where linha = r.linha;
      else
        update tmp_iatf set animal_id = v_fem.id, lote_antigo = v_fem.lote_nome,
          acao = case when v_fem.lote_id is not distinct from r.lote_id then 'ja_no_lote' else 'mover' end
         where linha = r.linha;
      end if;
    elsif r.numero = '19099' then
      update tmp_iatf set acao='pendente', motivo='19 ES deveria ser a 19099, que nao esta cadastrada como femea'
       where linha = r.linha;
    elsif v_zero is not null then
      update tmp_iatf set acao='pendente',
        motivo='nao existe vaca ' || r.numero || ', mas existe ' || v_zero || ': e a mesma?'
       where linha = r.linha;
    elsif v_semsexo > 0 then
      update tmp_iatf set acao='pendente', motivo='existe animal ' || r.numero || ' sem sexo no cadastro'
       where linha = r.linha;
    elsif r.sufixo = 'ES' and exists (select 1 from tmp_iatf t where t.linha <> r.linha and trim(t.planilha) = r.numero) then
      update tmp_iatf set acao='pendente',
        motivo='a planilha tem a ' || r.numero || ' e a ' || r.numero || ' ES: duas vacas com o mesmo brinco, qual numero a ES recebe?'
       where linha = r.linha;
    else
      update tmp_iatf set acao='criar',
        nome_novo = case when r.sufixo is null then null when r.sufixo = 'ES' then 'ES'
                         when r.sufixo like 'DESC%' then 'descarte' else r.sufixo end
       where linha = r.linha;
    end if;
  end loop;

  -- Mesmo numero em mais de uma linha (fora as ja pendentes): nenhuma grava
  update tmp_iatf t set acao='pendente',
    motivo='numero ' || t.numero || ' aparece em mais de uma linha da planilha (linhas ' ||
           (select string_agg(x.linha::text || ' ' || x.planilha || ' ' || x.touro, ', ' order by x.linha)
              from tmp_iatf x where x.numero = t.numero and x.acao <> 'pendente') || ')'
   where t.numero is not null and t.acao <> 'pendente'
     and (select count(*) from tmp_iatf x where x.numero = t.numero and x.acao <> 'pendente') > 1;

  -- Ja lancada a mao no app (mesmo lote, data e vaca, sem esta chave)
  update tmp_iatf t set acao='ja_lancada', motivo='ja existia inseminacao desta vaca neste lote e data'
   where t.acao in ('ja_no_lote','mover','criar')
     and exists (select 1 from reproducao_custos rc
                  where rc.lote_id = t.lote_id and rc.data = t.data
                    and lower(trim(rc.numero_vaca)) = t.numero
                    and coalesce(rc.item,'') <> t.chave);

  -- Cadastro: cria as que faltam
  insert into animais (numero, lote_id, sexo, raca, nome, criado_por)
  select t.numero, t.lote_id, 'femea', 'nelore', t.nome_novo, 'Planilha IATF out/2026'
    from tmp_iatf t
   where t.acao = 'criar'
     and not exists (select 1 from animais a where lower(trim(a.numero)) = t.numero and a.sexo = 'femea');
  get diagnostics v_cri = row_count;

  -- Cadastro: move para o lote da inseminacao
  update animais a set lote_id = t.lote_id, raca = coalesce(a.raca, 'nelore')
    from tmp_iatf t
   where t.acao = 'mover' and a.id = t.animal_id;
  get diagnostics v_mov = row_count;

  update animais a set raca = 'nelore'
    from tmp_iatf t
   where t.acao = 'ja_no_lote' and a.id = t.animal_id and a.raca is null;

  -- Qual inseminacao (1a, 2a, 3a)
  update tmp_iatf t set qual = least(3, 1 + (
      select count(*) from reproducao_custos rc
       where t.numero is not null
         and lower(trim(rc.numero_vaca)) = t.numero
         and rc.data between t.data - 120 and t.data - 1))::text
   where t.acao in ('ja_no_lote','mover','criar','sem_numero');

  -- Inseminacoes
  insert into reproducao_custos (data, lote_id, numero_vaca, raca_touro, qual_inseminacao, custo, item, criado_por)
  select t.data, t.lote_id, t.numero, 'nelore', t.qual, 46.30, t.chave, 'Planilha IATF out/2026'
    from tmp_iatf t
   where t.acao in ('ja_no_lote','mover','criar','sem_numero')
     and not exists (select 1 from reproducao_custos rc where rc.item = t.chave);
  get diagnostics v_ins = row_count;

  raise notice 'inseminacoes gravadas agora %, vacas cadastradas %, vacas movidas de lote %', v_ins, v_cri, v_mov;
end $$;

-- ============================================================
-- CONFERENCIA (uma consulta so)
-- ============================================================
select item, valor, situacao from (
  select 1 as ordem, 0 as sub,
         'inseminacoes da planilha no banco - ' || l.nome as item,
         count(rc.id)::text || ' de ' || (select count(*) from tmp_iatf t2 where t2.lote_id = l.id) ||
           ' | R$ ' || translate(to_char(coalesce(sum(rc.custo),0), 'FM999G990D00'), ',.', '.,') as valor,
         case when count(rc.id) = (select count(*) from tmp_iatf t2 where t2.lote_id = l.id) then 'OK'
              else 'faltam ' || ((select count(*) from tmp_iatf t2 where t2.lote_id = l.id) - count(rc.id)) || ' (pendentes ou ja lancadas abaixo)' end as situacao
    from lotes l
    join (select distinct lote_id from tmp_iatf) x on x.lote_id = l.id
    left join reproducao_custos rc on rc.lote_id = l.id and rc.item like 'IATF %/10/2026 linha % - touro %'
   group by l.id, l.nome
  union all
  select 2, 0, 'TOTAL', count(*)::text || ' de 239 | R$ ' || translate(to_char(coalesce(sum(custo),0), 'FM999G990D00'), ',.', '.,'),
         case when count(*) = 239 then 'OK' else 'faltam ' || (239 - count(*)) end
    from reproducao_custos where item like 'IATF %/10/2026 linha % - touro %'
  union all
  select 3, 0, 'inseminacoes sem numero de vaca (S/N)', count(*)::text, 'OK, contam no lote e no custo, sem cadastro de animal'
    from tmp_iatf where acao = 'sem_numero'
  union all
  select 4, 0, 'vacas cadastradas agora (nao existiam)', count(*)::text,
         coalesce('OK: ' || string_agg(numero || coalesce(' (' || nome_novo || ')',''), ', ' order by linha), 'OK')
    from tmp_iatf where acao = 'criar'
  union all
  select 5, linha, 'vaca ' || numero || ' mudou de lote', coalesce(lote_antigo,'sem lote') || ' -> ' ||
         (select nome from lotes where id = tmp_iatf.lote_id), 'OK, confira se e a mesma vaca'
    from tmp_iatf where acao = 'mover'
  union all
  select 6, 0, 'inseminacoes marcadas como 2a ou 3a', count(*)::text,
         case when count(*) = 0 then 'OK, todas 1a' else 'vacas com inseminacao nos 120 dias anteriores: ' || string_agg(numero || '=' || qual || 'a', ', ') end
    from tmp_iatf where qual in ('2','3')
  union all
  select 7, linha, 'JA LANCADA A MAO - linha ' || linha || ': ' || planilha, touro, motivo
    from tmp_iatf where acao = 'ja_lancada'
  union all
  select 8, linha, 'PENDENTE - linha ' || linha || ': ' || planilha || ' (' ||
         case grupo when 'V09' then 'Vacas 09/10' when 'VSA' then 'Vacas Vazia Santa Alice' else 'Novilhas' end || ')',
         touro, motivo
    from tmp_iatf where acao = 'pendente'
) z
order by ordem, sub;
