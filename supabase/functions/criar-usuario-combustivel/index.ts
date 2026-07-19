// Edge Function: criar-usuario-combustivel
//
// Cria uma conta (login + senha) e o perfil correspondente em `profiles`,
// no projeto Supabase do AE Combustível. Só pode ser chamada por quem já
// está logado como admin — a verificação é feita aqui dentro, usando a
// service_role key, que nunca fica exposta no app (client-side).
//
// Espelha supabase/functions/criar-usuario (do app da pecuária), adaptada
// para os papéis deste app (admin/gestor/encarregado/operador).
//
// Chamada esperada (do app, autenticado):
//   POST /functions/v1/criar-usuario-combustivel
//   Authorization: Bearer <access_token do admin logado>
//   Body: { usuario: "joao.silva", senha: "******", nome: "João Silva", papel: "operador", permissoes: {...} }

import { createClient } from 'npm:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const DOMINIO_LOGIN = 'aeagropecuaria.local'
const PAPEIS_VALIDOS = ['admin', 'gestor', 'encarregado', 'operador']

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function resposta(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders })
  if (req.method !== 'POST') return resposta({ error: 'Método não permitido' }, 405)

  try {
    const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '')
    if (!jwt) return resposta({ error: 'Não autenticado' }, 401)

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    const { data: chamador, error: erroChamador } = await admin.auth.getUser(jwt)
    if (erroChamador || !chamador?.user) return resposta({ error: 'Sessão inválida' }, 401)

    const { data: perfilChamador, error: erroPerfil } = await admin
      .from('profiles')
      .select('papel, ativo')
      .eq('id', chamador.user.id)
      .single()

    if (erroPerfil || !perfilChamador || perfilChamador.papel !== 'admin' || !perfilChamador.ativo) {
      return resposta({ error: 'Apenas administradores podem criar usuários' }, 403)
    }

    const { usuario, senha, nome, papel, permissoes } = await req.json()
    if (!usuario || !senha || !nome) {
      return resposta({ error: 'Usuário, senha e nome são obrigatórios' }, 400)
    }
    if (String(senha).length < 6) {
      return resposta({ error: 'A senha precisa ter pelo menos 6 caracteres' }, 400)
    }
    const papelFinal = PAPEIS_VALIDOS.includes(papel) ? papel : 'operador'

    const usuarioNormalizado = String(usuario).trim().toLowerCase().replace(/[^a-z0-9._-]/g, '')
    if (!usuarioNormalizado) return resposta({ error: 'Usuário inválido' }, 400)
    const email = `${usuarioNormalizado}@${DOMINIO_LOGIN}`

    const { data: novoUsuario, error: erroCriar } = await admin.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
    })
    if (erroCriar || !novoUsuario?.user) {
      const msg = erroCriar?.message?.includes('already been registered')
        ? 'Já existe um usuário com esse nome de usuário'
        : erroCriar?.message || 'Falha ao criar usuário'
      return resposta({ error: msg }, 400)
    }

    const { error: erroPerfilNovo } = await admin.from('profiles').insert({
      id: novoUsuario.user.id,
      nome,
      usuario: usuarioNormalizado,
      papel: papelFinal,
      permissoes: permissoes || {},
      ativo: true,
    })
    if (erroPerfilNovo) {
      await admin.auth.admin.deleteUser(novoUsuario.user.id)
      return resposta({ error: erroPerfilNovo.message }, 400)
    }

    return resposta({ ok: true, usuario: usuarioNormalizado })
  } catch (e) {
    return resposta({ error: String(e) }, 500)
  }
})
