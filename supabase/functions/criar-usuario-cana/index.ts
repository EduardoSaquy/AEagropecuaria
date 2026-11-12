// Edge Function: criar-usuario-cana  (versao 5, 12/11/2026: senha com 10+ caracteres e acao redefinir_senha)
// versao 4 (12/11/2026): exige o codigo de duas etapas de quem tem celular cadastrado
//
// Cria uma conta (login + senha) e o perfil correspondente em `profiles`,
// no projeto Supabase do AE Cana. Só pode ser chamada por quem já está
// logado como admin — a verificação é feita aqui dentro, usando a
// service_role key, que nunca fica exposta no app (client-side).
//
// Espelha supabase/functions/criar-usuario-combustivel, adaptada para o
// projeto próprio do AE Cana.
//
// Chamada esperada (do app, autenticado):
//   POST /functions/v1/criar-usuario-cana
//   Authorization: Bearer <access_token do admin logado>
//   Body: { usuario: "joao.silva", senha: "******", nome: "João Silva", papel: "operador", permissoes: {...} }
//   Senha provisoria para quem esqueceu: { acao: "redefinir_senha", usuario_id: "<uuid>", senha: "******" }
//   (troca a senha e marca profiles.precisa_trocar_senha: a pessoa cria a dela no proximo acesso)

import { createClient } from 'npm:@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const DOMINIO_LOGIN = 'aeagropecuaria.local'
// Tem que bater com a restricao profiles_papel_check do banco. 'consultor'
// faltava aqui e existe la desde a unificacao (unificacao_04): criar um
// consultor por esta funcao devolvia um OPERADOR, calado - ver o motivo
// logo abaixo.
const PAPEIS_VALIDOS = ['admin', 'proprietario', 'gestor', 'encarregado', 'colaborador', 'consultor', 'operador']
const MIN_SENHA = 10

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Nivel da sessao que chamou: 'aal2' = entrou com senha + codigo de duas
// etapas. O token ja foi validado por getUser() antes de ler isto.
function aalDoToken(jwt: string): string {
  try {
    const parte = jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    const json = JSON.parse(atob(parte + '='.repeat((4 - (parte.length % 4)) % 4)))
    return String(json.aal || 'aal1')
  } catch {
    return 'aal1'
  }
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

    // Duas etapas (12/11/2026, seguranca_04): admin com celular cadastrado so
    // cria usuario com a sessao confirmada pelo codigo. Sem isto, com a senha
    // roubada do admin dava para criar um usuario novo, sem codigo, e entrar
    // por ele. Quem nao tem celular cadastrado segue como antes.
    if (aalDoToken(jwt) !== 'aal2') {
      let fatores: Array<{ status?: string }> = chamador.user.factors || []
      try {
        const r = await admin.auth.admin.mfa.listFactors({ userId: chamador.user.id })
        if (!r.error && r.data?.factors) fatores = r.data.factors
      } catch (_) { /* fica com os fatores que vieram no usuario */ }
      if (fatores.some((f) => f.status === 'verified')) {
        return resposta({ error: 'Confirme o código de duas etapas antes de criar usuários: saia e entre de novo no app.' }, 403)
      }
    }

    const corpo = await req.json()

    // Senha provisoria para quem esqueceu (12/11/2026): os logins usam e-mail inventado, nao ha recuperacao por e-mail.
    if (corpo.acao === 'redefinir_senha') {
      const alvo = String(corpo.usuario_id || '')
      if (!alvo || !corpo.senha) return resposta({ error: 'Pessoa e senha são obrigatórias' }, 400)
      if (String(corpo.senha).length < MIN_SENHA) {
        return resposta({ error: `A senha precisa ter pelo menos ${MIN_SENHA} caracteres` }, 400)
      }
      const { data: perfilAlvo } = await admin.from('profiles').select('id').eq('id', alvo).maybeSingle()
      if (!perfilAlvo) return resposta({ error: 'Pessoa não encontrada' }, 404)
      const { error: erroSenha } = await admin.auth.admin.updateUserById(alvo, { password: String(corpo.senha) })
      if (erroSenha) return resposta({ error: erroSenha.message }, 400)
      // depois de trocar (o gatilho do banco desmarca quem troca a senha): marca de novo, a senha e provisoria
      await admin.from('profiles').update({ precisa_trocar_senha: true }).eq('id', alvo)
      return resposta({ ok: true })
    }

    const { usuario, senha, nome, papel, permissoes } = corpo
    if (!usuario || !senha || !nome) {
      return resposta({ error: 'Usuário, senha e nome são obrigatórios' }, 400)
    }
    if (String(senha).length < MIN_SENHA) {
      return resposta({ error: `A senha precisa ter pelo menos ${MIN_SENHA} caracteres` }, 400)
    }
    // Papel desconhecido vira ERRO, e nao mais 'operador' silencioso.
    //
    // O padrao calado e pior que a recusa: quem escolhia um papel que a
    // funcao nao conhecia recebia a conta criada com sucesso, com o papel
    // trocado, e so descobria quando a pessoa reclamasse de nao conseguir
    // ver alguma tela. Papel em branco continua caindo em 'operador', que e
    // o menos privilegiado e o padrao certo para quem nao escolheu.
    if (papel && !PAPEIS_VALIDOS.includes(papel)) {
      return resposta({ error: `Papel inválido: "${papel}". Válidos: ${PAPEIS_VALIDOS.join(', ')}.` }, 400)
    }
    const papelFinal = papel || 'operador'

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
