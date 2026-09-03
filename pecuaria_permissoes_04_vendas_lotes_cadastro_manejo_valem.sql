-- ===================================================================
-- AE Pecuária — Vendas / Lotes (visão geral) / Cadastro / Manejo passam
-- a valer sozinhas no banco (RLS), não só como aba visível
-- ===================================================================
-- Achado na varredura de segurança: essas 4 chaves da tela de
-- permissões (AEpecuaria.html > Administração > Usuários) só
-- controlavam se a aba aparecia no app -- nenhuma policy de escrita
-- conhecia elas. Conceder só "Vendas" (sem também dar
-- Confinamento/Pasto/Cria + Resultados) deixava a aba visível mas
-- travada: o app deixava tentar, o banco recusava. Confirmado contra a
-- policy real do banco em 01/09/2026 (duas consultas rodadas pelo
-- Eduardo). Decisão dele: fazer essas 4 chaves valerem de verdade, cada
-- uma sozinha, em vez de tirar as opções da tela.
--
-- O que cada "Editar" passa a liberar sozinho (sem precisar de mais
-- nada), espelhando o lado do app (AEpecuaria.html, já ajustado numa
-- correção anterior):
--   Vendas    -> registrar/editar/excluir venda (abate) e a receita
--                 dela em lancamentos_financeiros, sem precisar de
--                 Confinamento/Pasto/Cria + Resultados junto
--   Lotes/Cadastro (visão geral / Cadastro) -> criar e editar lote e
--                 animal, sem precisar ser Admin/Consultor nem ter
--                 Confinamento/Pasto/Cria
--   Manejo    -> qualquer ação de manejo (pesagem, protocolo,
--                 inseminação, diagnóstico, desmama) em qualquer lote,
--                 sem precisar da permissão do módulo do tipo do lote
--
-- Cada tabela abaixo mantém a condição ANTIGA por inteiro (só some
-- OR tem_permissao(...) novo) -- ninguém que já tinha acesso perde.
-- Excluir continua do jeito que já era (pode_excluir(), só
-- admin/proprietário, ou a mesma condição de editar onde já era assim
-- antes) -- essa correção não mexe em quem pode excluir.
-- ===================================================================

do $$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;
end $$;

-- ============================== abates ==============================
-- (venda por abate) -- Vendas: Editar libera insert/update/delete
-- sozinho; Vendas: Visualizar libera o select sozinho.
drop policy if exists "select abates" on abates;
create policy "select abates" on abates for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
  or tem_permissao('vendas','visualizar')
);

drop policy if exists "inserir abates" on abates;
create policy "inserir abates" on abates for insert with check (
  tem_permissao('vendas','editar')
  or ((tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')) and tem_permissao('pec_resultados','editar'))
);

drop policy if exists "atualizar abates" on abates;
create policy "atualizar abates" on abates for update using (
  tem_permissao('vendas','editar')
  or ((tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')) and tem_permissao('pec_resultados','editar'))
) with check (
  tem_permissao('vendas','editar')
  or ((tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')) and tem_permissao('pec_resultados','editar'))
);

drop policy if exists "excluir abates" on abates;
create policy "excluir abates" on abates for delete using (
  tem_permissao('vendas','editar')
  or ((tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')) and tem_permissao('pec_resultados','editar'))
);

-- ==================== lancamentos_financeiros ====================
-- só a fatia da receita de venda da Pecuária (atividade='pecuaria') --
-- não mexe em nada do Matriz nem de Cana/Cereais.
drop policy if exists "ve lancamentos" on lancamentos_financeiros;
create policy "ve lancamentos" on lancamentos_financeiros for select using (
  is_admin() or tem_permissao('matriz_financeiro','visualizar')
  or ((atividade = 'pecuaria') and (tem_permissao('pec_financeiro','visualizar') or tem_permissao('pec_resultados','visualizar') or tem_permissao('vendas','visualizar')))
);

drop policy if exists "lanca" on lancamentos_financeiros;
create policy "lanca" on lancamentos_financeiros for insert with check (
  is_admin() or tem_permissao('matriz_financeiro','editar')
  or ((atividade = 'pecuaria') and (tem_permissao('pec_resultados','editar') or tem_permissao('vendas','editar')))
);

drop policy if exists "edita lancamentos" on lancamentos_financeiros;
create policy "edita lancamentos" on lancamentos_financeiros for update using (
  is_admin() or tem_permissao('matriz_financeiro','editar')
  or ((atividade = 'pecuaria') and (tem_permissao('pec_resultados','editar') or tem_permissao('vendas','editar')))
) with check (
  is_admin() or tem_permissao('matriz_financeiro','editar')
  or ((atividade = 'pecuaria') and (tem_permissao('pec_resultados','editar') or tem_permissao('vendas','editar')))
);
-- "so dono exclui" (delete) nao muda.

-- ============================== lotes ==============================
-- Lotes (visão geral) e Cadastro: Editar criam/editam lote sozinhos.
-- Manejo: Editar e Vendas: Editar também precisam editar lotes (mudar
-- contagem de animal ao mover de lote no Manejo, e zerar/encerrar lote
-- vendido em Vendas) -- só no update, nenhum dos dois cria lote novo.
drop policy if exists "select lotes" on lotes;
create policy "select lotes" on lotes for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
  or tem_permissao('lotesGeral','visualizar') or tem_permissao('cadastro','visualizar')
  or tem_permissao('manejo','visualizar') or tem_permissao('vendas','visualizar')
);

drop policy if exists "inserir lotes" on lotes;
create policy "inserir lotes" on lotes for insert with check (
  eh_consultor() or tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
);

drop policy if exists "atualizar lotes" on lotes;
create policy "atualizar lotes" on lotes for update using (
  eh_consultor() or tem_permissao(
    case destino when 'cria' then 'cria' when 'pasto' then 'pasto' else 'confinamento' end, 'editar')
  or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
  or tem_permissao('manejo','editar') or tem_permissao('vendas','editar')
) with check (
  eh_consultor() or tem_permissao(
    case destino when 'cria' then 'cria' when 'pasto' then 'pasto' else 'confinamento' end, 'editar')
  or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
  or tem_permissao('manejo','editar') or tem_permissao('vendas','editar')
);
-- "so dono exclui" (delete) nao muda.

-- ============================= animais =============================
-- Lotes/Cadastro: Editar numeram animal sozinhos; Manejo: Editar
-- também (o cadastro de animal é atualizado como efeito colateral de
-- toda ação de manejo).
drop policy if exists "select animais" on animais;
create policy "select animais" on animais for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
  or tem_permissao('lotesGeral','visualizar') or tem_permissao('cadastro','visualizar') or tem_permissao('manejo','visualizar')
);

drop policy if exists "inserir animais" on animais;
create policy "inserir animais" on animais for insert with check (
  eh_consultor() or tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar') or tem_permissao('manejo','editar')
);

drop policy if exists "atualizar animais" on animais;
create policy "atualizar animais" on animais for update using (
  eh_consultor() or tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar') or tem_permissao('manejo','editar')
) with check (
  eh_consultor() or tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar') or tem_permissao('manejo','editar')
);
-- "so dono exclui" (delete) nao muda.

-- ============================= manejos ==============================
drop policy if exists "select manejos" on manejos;
create policy "select manejos" on manejos for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
  or tem_permissao('manejo','visualizar')
);

drop policy if exists "inserir manejos" on manejos;
create policy "inserir manejos" on manejos for insert with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
);

drop policy if exists "atualizar manejos" on manejos;
create policy "atualizar manejos" on manejos for update using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
) with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
);
-- "so dono exclui" (delete) nao muda.

-- ============================= pesagens =============================
-- Manejo: Editar (pesagem dentro de uma sessão de manejo) e
-- Lotes/Cadastro: Editar (peso inicial ao criar lote, ou recalculo de
-- peso médio ao somar animais num lote existente) também gravam aqui.
drop policy if exists "select pesagens" on pesagens;
create policy "select pesagens" on pesagens for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
  or tem_permissao('manejo','visualizar') or tem_permissao('lotesGeral','visualizar') or tem_permissao('cadastro','visualizar')
);

drop policy if exists "inserir pesagens" on pesagens;
create policy "inserir pesagens" on pesagens for insert with check (
  eh_consultor() or tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar') or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
);

drop policy if exists "atualizar pesagens" on pesagens;
create policy "atualizar pesagens" on pesagens for update using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar') or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
) with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar') or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
);

drop policy if exists "excluir pesagens" on pesagens;
create policy "excluir pesagens" on pesagens for delete using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar') or tem_permissao('lotesGeral','editar') or tem_permissao('cadastro','editar')
);

-- ========================= pesagens_animais =========================
drop policy if exists "select pesagens_animais" on pesagens_animais;
create policy "select pesagens_animais" on pesagens_animais for select using (
  tem_permissao('confinamento','visualizar') or tem_permissao('pasto','visualizar') or tem_permissao('cria','visualizar')
  or tem_permissao('manejo','visualizar')
);

drop policy if exists "inserir pesagens_animais" on pesagens_animais;
create policy "inserir pesagens_animais" on pesagens_animais for insert with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
);

drop policy if exists "atualizar pesagens_animais" on pesagens_animais;
create policy "atualizar pesagens_animais" on pesagens_animais for update using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
) with check (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
);

drop policy if exists "excluir pesagens_animais" on pesagens_animais;
create policy "excluir pesagens_animais" on pesagens_animais for delete using (
  tem_permissao('confinamento','editar') or tem_permissao('pasto','editar') or tem_permissao('cria','editar')
  or tem_permissao('manejo','editar')
);

-- ==== reproducao_custos / diagnosticos_gestacionais / partos /
-- ==== desmamas / protocolos_inseminacao (ações de Manejo ligadas a Cria)
do $rls$
declare
  t text;
  sel  text := 'tem_permissao(''cria'',''visualizar'') or tem_permissao(''manejo'',''visualizar'')';
  rw   text := 'tem_permissao(''cria'',''editar'') or tem_permissao(''manejo'',''editar'')';
begin
  foreach t in array array['reproducao_custos','diagnosticos_gestacionais','partos','desmamas','protocolos_inseminacao'] loop
    execute format('drop policy if exists %I on %I', 'select ' || t, t);
    execute format('create policy %I on %I for select using (%s)', 'select ' || t, t, sel);

    execute format('drop policy if exists %I on %I', 'inserir ' || t, t);
    execute format('create policy %I on %I for insert with check (%s)', 'inserir ' || t, t, rw);

    execute format('drop policy if exists %I on %I', 'atualizar ' || t, t);
    execute format('create policy %I on %I for update using (%s) with check (%s)', 'atualizar ' || t, t, rw, rw);
    -- excluir: partos e desmamas ja sao "so dono exclui" (pode_excluir()),
    -- nao mexe. reproducao_custos/diagnosticos_gestacionais/
    -- protocolos_inseminacao tinham policy de excluir igual a de editar --
    -- so essas tres recebem a mesma troca no delete.
    if t in ('reproducao_custos','diagnosticos_gestacionais','protocolos_inseminacao') then
      execute format('drop policy if exists %I on %I', 'excluir ' || t, t);
      execute format('create policy %I on %I for delete using (%s)', 'excluir ' || t, t, rw);
    end if;
  end loop;
end $rls$;

-- ============================================================
-- conferencia -- uma linha por tabela/comando tocado, item / valor / situacao
-- ============================================================
select 1::numeric as ordem, tablename || ' - ' || policyname as item,
       'comando=' || cmd as valor,
       case
         when tablename='abates' and qual ilike '%''vendas''%' then 'OK'
         when tablename='abates' and with_check ilike '%''vendas''%' then 'OK'
         when tablename='lancamentos_financeiros' and (qual ilike '%''vendas''%' or with_check ilike '%''vendas''%') then 'OK'
         when tablename='lotes' and (qual ilike '%''lotesGeral''%' or with_check ilike '%''lotesGeral''%') then 'OK'
         when tablename='animais' and (qual ilike '%''manejo''%' or with_check ilike '%''manejo''%') then 'OK'
         when tablename='manejos' and (qual ilike '%''manejo''%' or with_check ilike '%''manejo''%') then 'OK'
         when tablename='pesagens' and (qual ilike '%''manejo''%' or with_check ilike '%''manejo''%') then 'OK'
         when tablename='pesagens_animais' and (qual ilike '%''manejo''%' or with_check ilike '%''manejo''%') then 'OK'
         when tablename in ('reproducao_custos','diagnosticos_gestacionais','partos','desmamas','protocolos_inseminacao')
              and (qual ilike '%''manejo''%' or with_check ilike '%''manejo''%') then 'OK'
         when policyname like 'so dono exclui' then 'nao mexeu (esperado)'
         else 'CONFERIR'
       end as situacao
  from pg_policies
 where schemaname='public'
   and tablename in ('abates','lancamentos_financeiros','lotes','animais','manejos',
                      'pesagens','pesagens_animais','reproducao_custos',
                      'diagnosticos_gestacionais','partos','desmamas','protocolos_inseminacao')
 order by 2, 1;
