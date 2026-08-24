#!/usr/bin/env python3
"""
Gera AECana.html e AECereais.html a partir do AELavoura.html.

POR QUE UM GERADOR, E NAO EDICAO A MAO
--------------------------------------
O AELavoura.html e a versao ATUAL e correta do codigo (unificacao dos
bancos, migracao financeira, correcao da perda de permissoes entre apps).
Os AECana.html/AECereais.html que existem no repositorio sao de 02/08 e
estao 20 dias atrasados: reviver aqueles reintroduziria bugs ja corrigidos.

Editar 2.043 linhas a mao, duas vezes, e onde erro passa batido. Aqui cada
substituicao e verificada: se o trecho esperado nao existir exatamente, o
script PARA e diz qual foi. Nao existe substituicao silenciosa.

Rodar uma vez. Depois disso os dois arquivos sao independentes e podem ser
editados separadamente - e esse o objetivo da separacao.
"""

import re
import sys
from pathlib import Path

BASE = Path(__file__).parent
# AELavoura.html agora e so a pagina de encaminhamento para os dois apps
# novos (quem tem o link antigo salvo nao pode cair em pagina nao
# encontrada). O app completo, que e a fonte deste gerador, ficou guardado
# no arquivo abaixo.
ORIGEM = BASE / "AELavoura_app_completo.html.bak"


class Editor:
    """Substituicoes que se recusam a passar batido."""

    def __init__(self, texto, nome):
        self.texto = texto
        self.nome = nome
        self.trocas = 0

    def troca(self, antigo, novo, quantas=1, rotulo=""):
        achou = self.texto.count(antigo)
        if achou != quantas:
            raise SystemExit(
                f"\n[{self.nome}] FALHOU: {rotulo or antigo[:60]!r}\n"
                f"  esperava {quantas} ocorrencia(s), achou {achou}.\n"
                f"  O AELavoura.html mudou. Conferir antes de gerar."
            )
        self.texto = self.texto.replace(antigo, novo)
        self.trocas += 1
        return self

    def troca_todas(self, antigo, novo, rotulo=""):
        achou = self.texto.count(antigo)
        if achou == 0:
            raise SystemExit(
                f"\n[{self.nome}] FALHOU: {rotulo or antigo[:60]!r} nao encontrado."
            )
        self.texto = self.texto.replace(antigo, novo)
        self.trocas += 1
        return self

    def regex(self, padrao, novo, rotulo="", flags=re.S):
        novo_texto, n = re.subn(padrao, novo, self.texto, flags=flags)
        if n == 0:
            raise SystemExit(f"\n[{self.nome}] FALHOU (regex): {rotulo or padrao[:60]}")
        self.texto = novo_texto
        self.trocas += 1
        return self

    def remove_bloco(self, inicio, fim_marcador, rotulo=""):
        """Remove de `inicio` ate a linha que comeca com `fim_marcador`."""
        i = self.texto.find(inicio)
        if i < 0:
            raise SystemExit(f"\n[{self.nome}] FALHOU: bloco {rotulo!r} nao encontrado.")
        j = self.texto.find(fim_marcador, i)
        if j < 0:
            raise SystemExit(f"\n[{self.nome}] FALHOU: fim do bloco {rotulo!r} nao encontrado.")
        self.texto = self.texto[:i] + self.texto[j:]
        self.trocas += 1
        return self


# ============================================================
# CONFIGURACAO DE CADA APP
# ============================================================
APPS = {
    "cana": dict(
        arquivo="AECana.html",
        titulo="AE Cana",
        frente="cana",              # valor da coluna culturas.frente
        atividade="cana",           # valor de fazenda_atividades.atividade
        sufixo="Cana",              # sufixo das chaves de estado: plantiosCana
        outro_sufixo="Graos",
        perm_cadastros="cana_cadastros",
        perm_operacoes="operacoes",
        icone_grupo="iconPlantio()",
        cache="cana_cache_v2",
        manifest="manifest_cana.json",
        icone="icon-cana-192.png",
        cor="#eb6834",
        unidade="tonelada",
        categorias="CATEGORIAS_INSUMO_CANA",
        operacoes_label="Operações · Cana",
        rotulo_frente="cana",
    ),
    "cereais": dict(
        arquivo="AECereais.html",
        titulo="AE Cereais",
        frente="graos",
        atividade="graos",
        sufixo="Graos",
        outro_sufixo="Cana",
        perm_cadastros="cereais_cadastros",
        perm_operacoes="operacoes_graos",
        icone_grupo="iconGrao()",
        cache="cereais_cache_v2",
        manifest="manifest_cereais.json",
        icone="icon-cereais-192.png",
        cor="#1baf7a",
        unidade="saca",
        categorias="CATEGORIAS_INSUMO_GRAOS",
        operacoes_label="Operações · Cereais",
        rotulo_frente="cereais",
    ),
}

# Cadastros que saem dos dois apps porque foram para o AE Matriz junto com
# o Financeiro. despesas/receitas viraram lancamentos_financeiros; centro de
# custo e cadastro financeiro e passou a ser mantido no Matriz.
CADASTROS_QUE_FORAM_PARA_O_MATRIZ = [
    "despesasCana", "receitasCana",
    "despesasGraos", "receitasGraos",
    "centrosCusto",
]


def recorta_entrada_cadastro(texto, chave, nome_app):
    """Remove uma entrada inteira do objeto CADASTROS, da chave ate a
    proxima chave no mesmo nivel de indentacao."""
    padrao = re.compile(
        r"\n  " + re.escape(chave) + r": \{.*?\n  \},(?=\n)",
        re.S,
    )
    novo, n = padrao.subn("", texto)
    if n != 1:
        raise SystemExit(
            f"\n[{nome_app}] FALHOU: entrada de cadastro {chave!r} "
            f"nao recortada (achou {n})."
        )
    return novo


def gerar(chave_app, cfg, origem):
    ed = Editor(origem, cfg["arquivo"])
    outro = "cereais" if chave_app == "cana" else "cana"
    outro_cfg = APPS[outro]

    # ---------- 1) CADASTROS: tira os da outra frente e os que foram para o Matriz
    for k in CADASTROS_QUE_FORAM_PARA_O_MATRIZ:
        ed.texto = recorta_entrada_cadastro(ed.texto, k, cfg["arquivo"])

    for base in ["plantios", "colheitas", "insumos", "entradasInsumo", "aplicacoes"]:
        ed.texto = recorta_entrada_cadastro(
            ed.texto, base + cfg["outro_sufixo"], cfg["arquivo"]
        )

    # ---------- 2) Fazendas viram somente leitura (cadastro e do Matriz)
    ed.troca(
        "    table:'fazendas', label:'Fazendas', singular:'Fazenda', modulo:'cadastros',",
        "    table:'fazendas', label:'Fazendas', singular:'Fazenda', modulo:'matriz_fazendas',",
        rotulo="fazendas -> matriz_fazendas",
    )

    # ---------- 3) Permissao de cadastros vira a da frente
    ed.troca_todas("modulo:'cadastros'", f"modulo:'{cfg['perm_cadastros']}'",
                   rotulo="modulo cadastros")
    ed.troca_todas("cfg.modulo||'cadastros'", f"cfg.modulo||'{cfg['perm_cadastros']}'",
                   rotulo="fallback de modulo")
    ed.troca_todas("temPermissao('cadastros'", f"temPermissao('{cfg['perm_cadastros']}'",
                   rotulo="temPermissao cadastros")

    # ---------- 4) Chaves de estado das listas por frente
    ed.regex(
        r"const CANA_KEYS = \[[^\]]*\];\nconst GRAOS_KEYS = \[[^\]]*\];",
        "const FRENTE_KEYS = ['plantios{s}','colheitas{s}','insumos{s}',"
        "'entradasInsumo{s}','aplicacoes{s}'];".format(s=cfg["sufixo"]),
        rotulo="CANA_KEYS/GRAOS_KEYS",
    )

    # ---------- 5) OPCOES.FRENTES: so a frente do app
    ed.regex(
        r"  FRENTES: \[[^\]]*\],",
        "  FRENTES: [{{value:'{f}',label:'{l}'}}],".format(
            f=cfg["frente"],
            l="Cana-de-açúcar" if cfg["frente"] == "cana" else "Cereais/Grãos",
        ),
        rotulo="OPCOES.FRENTES",
    )

    # ---------- 6) Constantes da frente, logo depois do cliente Supabase
    ed.troca(
        "/* ===================== HELPERS DE CONVERSÃO ===================== */",
        f"""/* ===================== A FRENTE DESTE APP =====================
 * Este arquivo e o {cfg['titulo']}. Ele foi gerado a partir do
 * AELavoura.html por gerar_apps_lavoura.py e so enxerga uma frente.
 * Cana e Cereais sao operacoes em estados diferentes, com equipes e
 * cadastros proprios; o banco continua sendo um so, e o AE Matriz e
 * quem consolida as tres atividades. */
const FRENTE = '{cfg['frente']}';       // culturas.frente
const ATIVIDADE = '{cfg['atividade']}'; // fazenda_atividades.atividade

/* ===================== HELPERS DE CONVERSÃO ===================== */""",
        rotulo="constantes de frente",
    )

    # ---------- 7) Carga: filtra pela frente na ENTRADA dos dados
    ed.troca(
        """    db.from('profiles').select('*').order('nome'),
  ]);
  CADASTRO_KEYS.forEach((k,i)=>{ state[k] = (results[i].data||[]).map(row=>rowToCadastro(row, CADASTROS[k])); });
  state.perfis = (results[CADASTRO_KEYS.length].data||[]).map(rowToPerfil);
  salvarCacheLocal();""",
        """    db.from('profiles').select('*').order('nome'),
    db.from('fazenda_atividades').select('*'),
  ]);
  CADASTRO_KEYS.forEach((k,i)=>{ state[k] = (results[i].data||[]).map(row=>rowToCadastro(row, CADASTROS[k])); });
  state.perfis = (results[CADASTRO_KEYS.length].data||[]).map(rowToPerfil);
  filtrarPelaFrente((results[CADASTRO_KEYS.length+1].data)||[]);
  salvarCacheLocal();""",
        rotulo="loadAll com fazenda_atividades",
    )

    ed.troca(
        "/* ===================== ESTADO ===================== */",
        """/* Corta tudo que nao e desta frente na ENTRADA dos dados, e nao em cada
 * tela. Assim toda lista, todo seletor e todo calculo ja nascem certos,
 * sem depender de alguem lembrar de filtrar em cada lugar novo. */
function filtrarPelaFrente(fazendaAtividades){
  state.culturas = state.culturas.filter(c => c.frente === FRENTE);
  const idsCultura = new Set(state.culturas.map(c=>c.id));
  state.safras  = state.safras.filter(s  => s.culturaId!=null && idsCultura.has(s.culturaId));
  state.talhoes = state.talhoes.filter(t => t.culturaId!=null && idsCultura.has(t.culturaId));

  // Uma fazenda entra se DECLAROU a atividade ou se ja tem talhao desta
  // frente. A segunda condicao existe para nunca esconder fazenda que tem
  // trabalho de verdade so porque faltou declarar a area no Matriz.
  const daFrente = new Set([
    ...fazendaAtividades.filter(a => a.atividade===ATIVIDADE && Number(a.area_ha||0)>0)
                        .map(a => a.fazenda_id),
    ...state.talhoes.map(t => t.fazendaId),
  ]);
  state.fazendas = state.fazendas.filter(f => daFrente.has(f.id));
}

/* ===================== ESTADO ===================== */""",
        rotulo="filtrarPelaFrente",
    )

    # ---------- 8) Navegacao: so os grupos desta frente, sem Financeiro
    ed.regex(
        r"const GROUPS = \{.*?\n\};",
        """const GROUPS = {{
  cadastros: {{label:'Cadastros', icon:iconFazenda(), pages:[
    {{key:'talhoes', label:'Talhões'}},
    {{key:'fazendas', label:'Fazendas'}},
    {{key:'culturas', label:'Culturas'}},
    {{key:'safras', label:'Safras'}},
  ]}},
  operacoes: {{label:'Operações', icon:{icone}, pages:[
    {{key:'plantios{s}', label:'Plantio'}},
    {{key:'colheitas{s}', label:'Colheita'}},
    {{key:'insumos{s}', label:'Insumos'}},
    {{key:'entradasInsumo{s}', label:'Entradas'}},
    {{key:'estoqueInsumos{s}', label:'Estoque'}},
    {{key:'aplicacoes{s}', label:'Aplicações'}},
  ]}},
  admin: {{label:'Administração', icon:iconAdmin(), pages:[
    {{key:'adminUsuarios', label:'Usuários'}},
  ]}},
}};""".format(s=cfg["sufixo"], icone=cfg["icone_grupo"]),
        rotulo="GROUPS",
    )

    # Financeiro e Resultados sairam para o AE Matriz, entao as regras de
    # visibilidade deles nao existem mais aqui.
    ed.regex(
        r"function grupoVisivel\(key\)\{.*?\n\}",
        """function grupoVisivel(key){{
  if(key==='admin') return souAdmin();
  if(key==='operacoes') return temPermissao('{op}','visualizar');
  return temPermissao('{cad}','visualizar');
}}""".format(op=cfg["perm_operacoes"], cad=cfg["perm_cadastros"]),
        rotulo="grupoVisivel",
    )

    # ---------- 9) Paginas que sobraram
    ed.regex(
        r"function paginaCustom\(page\)\{.*?\n\}",
        """function paginaCustom(page){{
  if(page==='adminUsuarios') return PageAdminUsuarios();
  if(page==='estoqueInsumos{s}') return PageEstoqueInsumos('{s}');
  return PageCadastro(page);
}}""".format(s=cfg["sufixo"]),
        rotulo="paginaCustom",
    )

    ed.regex(
        r"function Header\(\)\{.*?\n\}\nfunction headerHtml",
        """function Header(){{
  if(state.page==='adminUsuarios'){{
    return headerHtml('Administração','Usuários','Contas de acesso desta operação e o que cada uma pode ver e editar.');
  }}
  if(state.page==='estoqueInsumos{s}'){{
    return headerHtml('{oplabel}','Estoque','Saldo atual de cada insumo (entradas menos aplicações), preço médio ponderado e alerta de estoque baixo.');
  }}
  const cfg = CADASTROS[state.page];
  const eyebrow = (cfg.modulo==='{op}') ? '{oplabel}' : 'Cadastro';
  return headerHtml(eyebrow, cfg.label, cfg.desc);
}}
function headerHtml""".format(
            s=cfg["sufixo"], op=cfg["perm_operacoes"], oplabel=cfg["operacoes_label"]
        ),
        rotulo="Header",
    )

    # ---------- 10) Permissoes oferecidas na tela de Usuarios deste app
    ed.regex(
        r"const MODULOS_PERMISSAO = \[.*?\n\];",
        """const MODULOS_PERMISSAO = [
  ['{cad}','Cadastros (Talhões, Culturas, Safras)'],
  ['{op}','Operações (Plantio, Tratos, Colheita, Insumos)'],
];""".format(cad=cfg["perm_cadastros"], op=cfg["perm_operacoes"]),
        rotulo="MODULOS_PERMISSAO",
    )

    # ---------- 11) Telas que foram para o AE Matriz
    for fn in ["PageCustoProducao", "PageDespesas", "PageReceitas",
               "PageResultado", "resultadoFrente", "blocoResultado",
               "despesasGeraisSemTalhao", "custoDespesasTalhao",
               "FrenteToggle", "donutChart", "despesaPorCentroCusto",
               "donutSlicePath", "polarXY", "corCentroCusto", "mesLabel"]:
        ed.texto = remove_funcao(ed.texto, fn, cfg["arquivo"])

    ed.troca("  despesaFrenteAtual: 'cana',\n", "", rotulo="estado despesaFrenteAtual")
    ed.troca("  receitaFrenteAtual: 'cana',\n", "", rotulo="estado receitaFrenteAtual")
    ed.regex(r"\n *const *DONUT_PALETTE *= *\[[^\]]*\];", "", rotulo="DONUT_PALETTE")
    ed.regex(r"\n *const *LIMITE_PCT_OUTROS *= *\d+;", "", rotulo="LIMITE_PCT_OUTROS")
    ed.regex(r"\n *const *MESES_PT *= *\[[^\]]*\];", "", rotulo="MESES_PT")

    # ---------- 11b) Eventos e comentarios orfaos das telas removidas
    ed.troca(
        """  document.querySelectorAll('[data-despesa-frente]').forEach(el=>{
    el.onclick = ()=>{ state.despesaFrenteAtual = el.dataset.despesaFrente; state.despesaFiltroMes=''; state.despesaFiltroCentro=''; render(); };
  });
  document.querySelectorAll('[data-receita-frente]').forEach(el=>{
    el.onclick = ()=>{ state.receitaFrenteAtual = el.dataset.receitaFrente; render(); };
  });
""",
        "",
        rotulo="handlers do seletor de frente",
    )
    # Comentario grande que descrevia a tela de Despesas, que agora vive no
    # AE Matriz. Deixar o texto antigo aqui e pior que nao ter comentario:
    # descreve um app que este arquivo nao e mais.
    ed.regex(
        r"\n/\* =+ FINANCEIRO: DESPESAS.*?\*/\n",
        "\n",
        rotulo="comentario de Despesas",
    )
    ed.regex(
        r" \* Cadastros de base \(fazendas, culturas, talhoes, safras\).*?lavoura_migracao_graos\.sql\)\. \*/",
        (" * Cadastros de base (fazendas, culturas, talhoes, safras) sao tabelas\n"
         " * compartilhadas com os outros apps, mas este arquivo so enxerga a\n"
         f" * frente '{cfg['frente']}' - o corte e feito em filtrarPelaFrente(), na\n"
         " * entrada dos dados. Fazenda e cadastro do AE Matriz; aqui ela aparece\n"
         " * para consulta e para agrupar os talhoes. Centro de custo saiu junto\n"
         " * com o Financeiro para o Matriz. */"),
        rotulo="comentario de CADASTROS",
    )

    # ---------- 11a) Talhao sem cultura nao pode mais ser criado
    #
    # A frente de um talhao vem da cultura dele. Sem cultura, ele nao
    # pertence a nenhuma das duas frentes e some dos DOIS apps: da para
    # cadastrar, salvar, e ele nao aparecer na lista - existindo no banco,
    # invisivel em todas as telas. Enquanto era um app so isso era um estado
    # aceitavel; com a separacao, deixou de ser.
    ed.troca(
        "      {key:'culturaId', label:'Cultura', type:'fk', refEntity:'culturas', "
        "filter:c=>c.frente==='cana'||c.frente==='graos'},",
        "      {key:'culturaId', label:'Cultura', type:'fk', refEntity:'culturas', required:true},",
        rotulo="cultura obrigatoria no talhao")

    # Os demais filtros de cultura tambem nao precisam mais citar as duas
    # frentes: state.culturas ja chega cortado por filtrarPelaFrente().
    ed.troca_todas(", required:true, filter:c=>c.frente==='cana'||c.frente==='graos'}",
                   ", required:true}", rotulo="filtro de cultura na safra")

    # ---------- 11b) Fazenda e so consulta aqui
    #
    # O cadastro de fazenda foi centralizado no AE Matriz. Aqui a tela existe
    # para consultar e para agrupar os talhoes - mas continuava oferecendo
    # Novo, Editar e Excluir. Fazenda criada por aqui nem aparecia na lista
    # depois de salvar (nao tem atividade nem talhao desta frente ainda), e o
    # Excluir apagava uma fazenda compartilhada com os outros dois apps.
    ed.troca(
        "    table:'fazendas', label:'Fazendas', singular:'Fazenda', modulo:'matriz_fazendas',",
        "    table:'fazendas', label:'Fazendas', singular:'Fazenda', modulo:'matriz_fazendas',\n"
        "    somenteLeitura:true,",
        rotulo="fazendas somente leitura")
    ed.troca(
        "  const podeEditar = temPermissao(cfg.modulo||'{cad}','editar') "
        "|| (cfg.moduloEditarAlt && temPermissao(cfg.moduloEditarAlt,'editar'));".format(
            cad=cfg["perm_cadastros"]),
        "  const podeEditar = !cfg.somenteLeitura\n"
        "    && (temPermissao(cfg.modulo||'{cad}','editar')\n"
        "        || (cfg.moduloEditarAlt && temPermissao(cfg.moduloEditarAlt,'editar')));".format(
            cad=cfg["perm_cadastros"]),
        rotulo="PageCadastro respeita somenteLeitura")
    ed.troca(
        "    desc:'Unidades produtivas da empresa, com estado e área total.',",
        "    desc:'As fazendas desta operação e os talhões de cada uma. "
        "O cadastro de fazenda é feito no AE Matriz.',",
        rotulo="descricao de fazendas")

    # ---------- 11c) PWA: manifest, icone e service worker corretos
    #
    # Os dois apps herdaram do AELavoura o manifest e o icone dele, entao
    # "adicionar a tela de inicio" instalava um app so, chamado AE Lavoura,
    # que abria a pagina de encaminhamento em vez do app.
    ed.troca('<link rel="manifest" href="manifest_lavoura.json">',
             f'<link rel="manifest" href="{cfg["manifest"]}">', rotulo="manifest")
    ed.troca_todas('href="icon-lavoura-192.png"', f'href="{cfg["icone"]}"',
                   rotulo="icone")
    # Um service worker so para todos os apps: cinco disputavam o mesmo
    # escopo e cada um apagava o cache dos outros - ver o cabecalho do sw.js.
    ed.troca("navigator.serviceWorker.register('sw_lavoura.js')",
             "navigator.serviceWorker.register('sw.js')", rotulo="service worker")

    # ---------- 11d) Cache local: filtrar tambem o que vem do localStorage
    #
    # carregarCacheLocal() pinta a tela ANTES de loadAll() rodar, e nao
    # passava por filtrarPelaFrente(). No AE Cana isso vazava de verdade: a
    # chave era a mesma do AE Cana antigo, servido na mesma URL, que lia as
    # culturas todas sem filtro nenhum. Quem ja usou o app antigo abria o
    # novo vendo cultura e talhao de cereais - e, se a rede falhasse, ficava
    # nesse estado, que e justamente o proposito do cache.
    #
    # A chave tambem muda de v1 para v2, para nao reaproveitar o que o app
    # antigo deixou gravado.
    ed.troca(
        """    const snapshot = JSON.parse(raw);
    Object.keys(snapshot).forEach(k=>{ if(CADASTROS[k]) state[k] = snapshot[k]; });""",
        """    const snapshot = JSON.parse(raw);
    Object.keys(snapshot).forEach(k=>{ if(CADASTROS[k]) state[k] = snapshot[k]; });
    // O cache tambem tem que passar pelo corte por frente: ele e pintado na
    // tela antes de loadAll() rodar. Sem fazendaAtividades gravada, o corte
    // usa so os talhoes - que ja bastam, porque toda fazenda desta frente
    // tem talhao dela.
    filtrarPelaFrente(snapshot.__fazendaAtividades || []);""",
        rotulo="cache passa pelo filtro")

    ed.troca(
        """    const snapshot = {};
    CADASTRO_KEYS.forEach(k=>{ snapshot[k] = state[k]; });""",
        """    const snapshot = {};
    CADASTRO_KEYS.forEach(k=>{ snapshot[k] = state[k]; });
    // Guarda tambem as atividades das fazendas: sem elas o corte por frente
    // na abertura offline nao teria como saber quais fazendas sao desta
    // frente, e cairia so nos talhoes.
    snapshot.__fazendaAtividades = state.fazendaAtividades || [];""",
        rotulo="cache guarda fazenda_atividades")

    ed.troca(
        "  filtrarPelaFrente((results[CADASTRO_KEYS.length+1].data)||[]);",
        """  state.fazendaAtividades = (results[CADASTRO_KEYS.length+1].data) || [];
  filtrarPelaFrente(state.fazendaAtividades);""",
        rotulo="guarda fazendaAtividades no state")

    # ---------- 11e) Textos que ainda falavam das duas frentes
    #
    # O gerador reescreveu a estrutura e deixou a prosa para tras. Sao os
    # textos que a pessoa le na tela, entao contradizem o que ela ve.
    ed.troca(
        "    desc:'Talhões de lavoura desta fazenda — de cana ou de grãos, "
        "conforme a Cultura escolhida.',",
        "    desc:'Talhões de {rotulo} desta fazenda. A Cultura define a safra "
        "e o histórico de cada um.',".format(rotulo=cfg["rotulo_frente"]),
        rotulo="descricao de talhoes")

    ed.regex(
        r'<p class="hint">Administrador tem acesso total.*?enxerga\.</p>',
        '<p class="hint">Administrador e proprietário têm acesso total. '
        'Cada módulo abaixo é independente: dá para liberar só os cadastros, '
        'só as operações, ou os dois. <strong>Visualizar</strong> deixa ver '
        'sem mexer; <strong>Editar</strong> deixa criar, alterar e excluir. '
        'Financeiro e resultados ficam no AE Matriz, com permissão própria '
        'de lá.</p>',
        rotulo="texto do modal de permissoes")

    ed.troca(
        "Vale para o AE Cana antigo também (mesma conta, mesmo banco).",
        "A mesma conta vale para todos os apps da AE Agropecuária.",
        rotulo="hint do novo usuario")

    ed.troca(
        "\'Defina a Cultura deste talhão em Cadastros > Talhões (Cana ou Grãos) "
        "para ver o histórico.\'",
        "\'Defina a Cultura deste talhão em Cadastros > Talhões para ver o histórico.\'",
        rotulo="texto do historico do talhao")

    ed.troca(
        "        Seu login foi reconhecido, mas ainda não há um perfil de acesso "
        "liberado para esta conta.",
        "        Seu login foi reconhecido, mas ainda não há acesso liberado para "
        "esta conta no {t}.".format(t=cfg["titulo"]),
        rotulo="texto de aguardando liberacao")

    # ---------- 11f) Codigo morto que sobrou da separacao
    #
    # Funcoes que so eram chamadas pelas telas de Financeiro e Resultados, e
    # que referenciam estado da OUTRA frente - que nao existe mais neste
    # arquivo. Nenhuma e alcancavel hoje, mas sao a proxima armadilha para
    # quem for mexer aqui: parecem funcionar e estouram na primeira chamada.
    for fn in ["custoInsumosTalhao", "talhaoEmProducao", "areaTotalEmProducao",
               "producaoTotalTalhao", "culturaDoTalhaoNome", "paginaVisivel"]:
        ed.texto = remove_funcao(ed.texto, fn, cfg["arquivo"])

    ed.regex(r"\n  despesaFiltroMes: \'\',\n  despesaFiltroCentro: \'\',"
             r"\n  despesaGruposAbertos: \{\},", "", rotulo="estado do financeiro")
    ed.regex(r"\n  FRENTES_GERAL: \[[^\]]*\],", "", rotulo="FRENTES_GERAL")
    ed.regex(r"\n *const *FRENTE_KEYS *= *\[[^\]]*\];", "", rotulo="FRENTE_KEYS")
    ed.remove_bloco(
        "  const despesaMesEl = document.querySelector('[data-despesa-filtro-mes]');",
        "  document.querySelectorAll('[data-del-cadastro]')",
        rotulo="handlers do filtro de despesa")

    # ---------- 12) Identidade do app
    ed.troca("<title>AE Lavoura</title>", f"<title>{cfg['titulo']}</title>",
             rotulo="title")
    ed.troca_todas('class="brand-name">AE Lavoura<',
                   f'class="brand-name">{cfg["titulo"]}<', rotulo="brand-name")
    ed.troca("const CACHE_LOCAL_KEY = 'lavoura_cache_cadastros_v1';",
             f"const CACHE_LOCAL_KEY = '{cfg['cache']}';", rotulo="cache local")

    return ed


def remove_funcao(texto, nome, nome_app):
    """Remove `function NOME(...){...}` casando chaves. Se a funcao nao
    existir, e erro: significa que o AELavoura.html mudou."""
    marcador = f"\nfunction {nome}("
    i = texto.find(marcador)
    if i < 0:
        raise SystemExit(f"\n[{nome_app}] FALHOU: funcao {nome!r} nao encontrada.")
    j = texto.find("{", i)
    nivel, k = 0, j
    while k < len(texto):
        if texto[k] == "{":
            nivel += 1
        elif texto[k] == "}":
            nivel -= 1
            if nivel == 0:
                break
        k += 1
    return texto[:i] + texto[k + 1:]


def main():
    if not ORIGEM.exists():
        raise SystemExit(f"Nao achei {ORIGEM}")
    origem = ORIGEM.read_text(encoding="utf-8")
    print(f"origem: {ORIGEM.name}, {len(origem.splitlines())} linhas\n")

    for chave, cfg in APPS.items():
        ed = gerar(chave, cfg, origem)
        destino = BASE / cfg["arquivo"]
        destino.write_text(ed.texto, encoding="utf-8")
        print(f"  {cfg['arquivo']:16} {len(ed.texto.splitlines()):5} linhas  "
              f"({ed.trocas} transformacoes)")


if __name__ == "__main__":
    main()
