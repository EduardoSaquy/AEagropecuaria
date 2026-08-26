// ============================================================
// Edge Function: atualizar-permissoes
//
// Publicar no projeto da PECUÁRIA (https://leojfqlbdtlriemdgnyw.supabase.co),
// não no do Lavoura/Matriz. Mesmo padrão da função "criar-usuario" que já
// existe lá (chamada sem sessão logada, usando a service role key por
// dentro pra fazer a escrita de verdade).
//
// O QUE FAZ: recebe {perfilId, papel, permissoes} e atualiza esses três
// campos na linha correspondente de profiles. É o mesmo UPDATE que a
// tela Administração > Usuários > Editar acesso já faz de dentro da
// Pecuária (db.from('profiles').update({papel, ativo, permissoes})) —
// só que aqui via service role, porque quem chama (o AE Matriz) nunca
// tem sessão autenticada neste projeto.
//
// COMO PUBLICAR (via painel do Supabase, sem precisar de CLI):
// 1. No projeto da Pecuária: Edge Functions > Create a new function.
// 2. Nome da função: atualizar-permissoes (tem que ser exatamente esse,
//    é o nome que o AEMatriz.html já está chamando).
// 3. Cole o conteúdo deste arquivo inteiro no editor.
// 4. Deploy.
// 5. Teste: no AE Matriz, abra um funcionário com login vinculado na
//    Pecuária, mexa numa permissão e salve. Se dar erro, a mensagem do
//    alerta mostra o motivo.
//
// SEGURANÇA: esta função aceita a chamada sem exigir sessão logada no
// projeto da Pecuária — mesmo modelo de confiança que "criar-usuario" já
// usa hoje (quem tem a URL/anon key do app já teria acesso de qualquer
// forma, já que ela fica embutida no HTML público). Não abre nada mais
// exposto do que já está.
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { perfilId, papel, permissoes } = await req.json();

    if (!perfilId || typeof perfilId !== 'string') {
      return new Response(JSON.stringify({ error: 'perfilId é obrigatório.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const PAPEIS_VALIDOS = ['admin', 'proprietario', 'colaborador', 'consultor'];
    if (papel && !PAPEIS_VALIDOS.includes(papel)) {
      return new Response(JSON.stringify({ error: 'papel inválido.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const campos: Record<string, unknown> = {};
    if (papel) campos.papel = papel;
    if (permissoes && typeof permissoes === 'object') campos.permissoes = permissoes;

    const { error } = await supabaseAdmin.from('profiles').update(campos).eq('id', perfilId);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e?.message || e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
