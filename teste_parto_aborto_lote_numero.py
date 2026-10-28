"""
AE Pecuaria: parto que "nao salvava", lote em branco, numero do animal so
com algarismos, aborto e obito do bezerro (27/10/2026).

Caso do Eduardo: editar o parto lancado como mae "721 abortou" e trocar o
numero para 721 nao gravava. Duas causas, as duas provadas aqui:
  - toque perdido: sair do campo "Numero da mae" redesenha a janela e o
    toque em Salvar sumia (a janela ficava aberta, sem aviso). Mesma coisa
    no Manejo, ao digitar o numero e tocar direto em "Salvar e ir pro
    proximo animal";
  - tela velha: partos vem na 2a etapa da carga (o historico pesado); com
    sinal fraco a lista continuava mostrando o dado antigo depois de salvar.
Pedidos do mesmo dia:
  - lote sempre em branco nos lancamentos, e sem lote nao salva;
  - numero do animal so com algarismos; texto vai no campo Nome do animal;
  - parto pode ser aborto (nao conta como nascido, nao espera desmama, a
    vaca aparece como "Abortou");
  - obito do bezerro antes da desmama (continua nascido, sai da desmama).
"""
import json, sys
from datetime import date
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
HOJE = date.today().isoformat()

def banco(com_colunas_novas=True):
    def parto(**k):
        base = {"lote_id": 6, "criado_por": "Joilson", "raca_bezerro": "angus"}
        base.update(k)
        if com_colunas_novas:
            base.setdefault("tipo", "nascimento"); base.setdefault("data_obito", None); base.setdefault("causa_obito", None)
        return base
    def animal(**k):
        base = {"lote_id": 6, "status": "ativo", "raca": "angus", "sexo": "femea"}
        base.update(k)
        if com_colunas_novas: base.setdefault("nome", None)
        return base
    return {
        "lotes": [
            {"id": 3, "nome": "VACAS INVERNADA", "destino": "cria", "numero_animais": 40, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
            {"id": 6, "nome": "Vacas 09/10", "destino": "cria", "numero_animais": 70, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
            {"id": 8, "nome": "Curral 2", "destino": "confinamento", "numero_animais": 60, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1, "sexo": "macho"},
            {"id": 9, "nome": "Pasto 1", "destino": "pasto", "numero_animais": 30, "data_inicio": "2026-01-01", "data_fim": None, "dieta_id": 1},
        ],
        "dietas": [{"id": 1, "nome": "Dieta Cria", "tipo": "cria", "itens": [], "consumo_direto": True}],
        "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg"}],
        "animais": [
            animal(id=1, numero="721"), animal(id=2, numero="721 abortou"),
            animal(id=3, numero="128"), animal(id=4, numero="512 2S", sexo="macho", lote_id=8),
            animal(id=5, numero="300"),
        ],
        "partos": [
            parto(id=197, data=HOJE, numero_mae="721 abortou", sexo_bezerro="macho"),
            parto(id=198, data="2026-10-20", numero_mae="128", sexo_bezerro="femea"),
            parto(id=199, data="2026-10-10", numero_mae="300", sexo_bezerro="macho"),
        ],
        "desmamas": [{"id": 50, "parto_id": 199, "data": HOJE, "raca": "angus", "peso_kg": 180, "criado_por": "Joilson"}],
        "diagnosticos_gestacionais": [
            {"id": 70, "data": "2026-06-01", "lote_id": 6, "numero_vaca": "300", "resultado": "prenha", "previsao_parto": None},
            {"id": 71, "data": "2026-06-01", "lote_id": 6, "numero_vaca": "721", "resultado": "prenha", "previsao_parto": None},
        ],
        "fazendas": [], "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [],
        "pesagens": [], "manejos": [], "movimentos": [], "saidas_racao": [], "leituras_cocho": [], "pasto": [],
        "producoes_racao": [], "reproducao_custos": [], "abates": [], "precos_arroba": [], "config_financeiro": [],
        "funcionarios": [], "pesagens_animais": [], "protocolos_inseminacao": [],
    }

ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "permissoes": {}, "ativo": True}

# rede lenta: tabela travada nunca responde; coluna faltando: erro do PostgREST
EMBRULHO = """(() => {
  const orig = db.from.bind(db);
  db.from = (t) => {
    if (window.__TRAVAR__ && window.__TRAVAR__[t]) {
      const q = { select(){return q;}, order(){return q;}, eq(){return q;}, range(){ return new Promise(()=>{}); } };
      return q;
    }
    const q = orig(t);
    if (window.__SEM_COLUNA__ && window.__SEM_COLUNA__[t]) {
      const col = window.__SEM_COLUNA__[t];
      const erro = {data:null, error:{message:`Could not find the '${col}' column of '${t}' in the schema cache`}};
      q.update = () => { const r = { eq(){return r;}, select(){return r;}, then(res,rej){ return Promise.resolve(erro).then(res,rej); } }; return r; };
    }
    return q;
  };
})()"""

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

def abrir(pw, db, toque=False):
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    ctx = browser.new_context(has_touch=toque, is_mobile=toque, viewport={"width": 390, "height": 844} if toque else {"width": 1280, "height": 900})
    page = ctx.new_page()
    page.avisos = []; page.erros = []
    page.on("dialog", lambda d: (page.avisos.append(d.message), d.accept()))
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {json.dumps(dict(db, profiles=[ADMIN]))};"
                         f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_timeout(900)
    page.evaluate(EMBRULHO)
    return browser, page

def tela_partos(page):
    page.evaluate("() => { state.modal=null; editDraft=null; state.page='reproducaoGeral'; state.subAbaReproducao='parto'; state.listasExpandidas.parto=true; render(); }")
    page.wait_for_timeout(100)

def toca(page, seletor, toque):
    el = page.locator(seletor)
    el.tap() if toque else el.click()

def parto_db(page, pid):
    return page.evaluate(f"() => window.__DB__.partos.find(p=>p.id==={pid})")

with sync_playwright() as pw:
    # ================= TOQUE PERDIDO (mouse e toque) =================
    for toque in (False, True):
        rotulo = "toque" if toque else "mouse"
        print(f"\n  TOQUE PERDIDO NO SALVAR ({rotulo})")
        browser, page = abrir(pw, banco(), toque)
        tela_partos(page)
        toca(page, '[data-edit-parto="197"]', toque)
        campo = page.locator('#f-numeromae')
        toca(page, '#f-numeromae', toque)
        campo.press("End"); campo.press("Backspace")   # apagar 1 letra de "721 abortou" ja limpa para 721
        conf(campo.input_value() == "721", f"[{rotulo}] apagar uma letra de '721 abortou' deixa so os algarismos: 721", campo.input_value())
        toca(page, '[data-save="parto"]', toque)          # UM toque, logo depois de mexer no numero
        page.wait_for_timeout(600)
        conf(parto_db(page, 197)["numero_mae"] == "721", f"[{rotulo}] um toque em Salvar logo depois de mexer no numero da mae grava", str(parto_db(page, 197)))
        conf(page.evaluate("() => !state.modal"), f"[{rotulo}] e a janela fecha")
        conf(not page.avisos, f"[{rotulo}] sem aviso", str(page.avisos))

        # Manejo: peso primeiro, numero por ultimo, um toque em Salvar
        page.evaluate("() => { state.modal=null; editDraft=null; state.page='manejoInicio'; render(); }")
        page.wait_for_timeout(100)
        page.select_option('#f-lotemanejo', '6'); page.wait_for_timeout(100)
        toca(page, '[data-iniciar-manejo]', toque); page.wait_for_timeout(400)
        conf(page.evaluate("() => !!state.manejoAtivo"), f"[{rotulo}] manejo iniciado com o lote escolhido")
        page.fill('#f-pesomanejo', '310')
        toca(page, '#f-numanimalmanejo', toque)
        page.locator('#f-numanimalmanejo').type('128')
        toca(page, '[data-salvar-animal-manejo]', toque)
        page.wait_for_timeout(700)
        feitos = page.evaluate("() => state.manejoAtivo ? state.manejoAtivo.animaisFeitos.length : -1")
        conf(feitos == 1, f"[{rotulo}] Manejo: um toque em 'Salvar e ir pro proximo' depois de digitar o numero salva o animal", f"feitos={feitos} avisos={page.avisos}")
        conf(not page.erros, f"[{rotulo}] nenhum erro de JavaScript", " | ".join(page.erros[:3]))
        browser.close()

    # ================= TELA ATUALIZA COM O HISTORICO LENTO =================
    print("\n  TELA ATUALIZA DEPOIS DE SALVAR (historico pesado parado)")
    browser, page = abrir(pw, banco())
    tela_partos(page)
    page.evaluate("() => { window.__TRAVAR__ = {movimentos: true, lancamentos_rateados: true}; }")
    page.locator('[data-edit-parto="198"]').click()
    page.select_option('#f-sexobezerro', 'macho')
    page.locator('[data-save="parto"]').click()
    page.wait_for_timeout(700)
    conf(parto_db(page, 198)["sexo_bezerro"] == "macho", "gravou no banco")
    conf(page.evaluate("() => state.carregandoHistorico === true"), "historico pesado ainda carregando (travado de proposito)")
    conf(page.evaluate("() => state.partos.find(p=>p.id===198).sexoBezerro") == "macho", "a lista ja mostra o valor novo sem esperar o historico")
    linha = page.locator('[data-edit-parto="198"]').locator('xpath=ancestor::tr').inner_text()
    conf("Macho" in linha, "e a linha da tabela tambem", linha)
    # parto apagado por outra pessoa enquanto a janela estava aberta: avisa
    page.evaluate("() => { window.__TRAVAR__ = {}; }")
    page.locator('[data-edit-parto="198"]').click()
    page.evaluate("() => { window.__DB__.partos = window.__DB__.partos.filter(p=>p.id!==198); }")
    page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    conf(page.avisos and "nada foi gravado" in page.avisos[0], "update que nao acha a linha avisa em vez de fechar calado", str(page.avisos))
    conf(page.evaluate("() => !!state.modal"), "e a janela continua aberta")
    browser.close()

    # ================= LOTE EM BRANCO =================
    print("\n  LOTE EM BRANCO E OBRIGATORIO")
    browser, page = abrir(pw, banco())
    casos = [('parto','#f-lote'), ('reproducaoCusto','#f-lote'), ('diagnosticoGestacional','#f-lote'), ('saidaRacaoCria','#f-lote'),
             ('saidaRacao','#f-lote'), ('cocho','#f-lote'), ('pasto','#f-lote'), ('venda','#f-lotevenda'), ('animal','#f-loteanimal')]
    for tipo, sel in casos:
        page.evaluate(f"() => {{ state.modal=null; editDraft=null; openNewModal('{tipo}'); render(); }}")
        page.wait_for_timeout(60)
        v = page.locator(sel).input_value() if page.locator(sel).count() else None
        conf(v == "", f"{tipo}: lote abre em branco (nao vem 'VACAS INVERNADA')", f"valor={v!r}")
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('lote'); render(); }")
    page.select_option('#f-modoentrada', 'existente'); page.wait_for_timeout(60)
    conf(page.locator('#f-loteexistente').input_value() == "", "entrada em lote existente: lote abre em branco")
    page.evaluate("() => { state.modal=null; editDraft=null; state.page='manejoInicio'; render(); }")
    page.wait_for_timeout(60)
    conf(page.locator('#f-lotemanejo').input_value() == "", "Manejo: lote abre em branco")
    conf(page.locator('[data-iniciar-manejo]').is_disabled(), "Manejo: 'Iniciar' desligado ate escolher o lote")
    # sem lote nao salva
    page.evaluate("() => { state.page='reproducaoGeral'; state.modal=null; editDraft=null; openNewModal('parto'); render(); }")
    page.fill('#f-numeromae', '128'); page.select_option('#f-sexobezerro', 'femea')
    antes = page.evaluate("() => window.__DB__.partos.length")
    page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "Selecione o lote" in page.avisos[0], "parto sem lote: avisa 'Selecione o lote'", str(page.avisos))
    conf(page.evaluate("() => window.__DB__.partos.length") == antes, "e nao grava")
    # sexo do bezerro tambem comeca em branco e e obrigatorio
    page.select_option('#f-lote', '6'); page.select_option('#f-sexobezerro', ''); page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "sexo do bezerro" in page.avisos[0], "sexo do bezerro comeca em branco e e obrigatorio", str(page.avisos))
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('cocho'); render(); }"); page.avisos.clear()
    page.locator('[data-save="cocho"]').click(); page.wait_for_timeout(200)
    conf(page.avisos and "Selecione o curral" in page.avisos[0], "leitura de cocho sem curral: nao salva", str(page.avisos))
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

    # ================= NUMERO SO COM ALGARISMOS + NOME =================
    print("\n  NUMERO DO ANIMAL SO COM ALGARISMOS E CAMPO NOME")
    browser, page = abrir(pw, banco())
    page.evaluate("() => { state.page='reproducaoGeral'; state.modal=null; editDraft=null; openNewModal('parto'); render(); }")
    page.locator('#f-numeromae').type('721 abortou')
    conf(page.locator('#f-numeromae').input_value() == "721", "digitar '721 abortou' no numero da mae fica 721", page.locator('#f-numeromae').input_value())
    # texto que escapou do filtro (colado por script) nao passa no Salvar
    page.select_option('#f-lote', '6'); page.select_option('#f-sexobezerro', 'macho')
    page.evaluate("() => { document.getElementById('f-numeromae').value = '999 X'; }")
    antes = page.evaluate("() => window.__DB__.partos.length"); page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "algarismos" in page.avisos[0], "numero com texto nao salva e explica", str(page.avisos))
    conf(page.evaluate("() => window.__DB__.partos.length") == antes and not page.evaluate("() => window.__DB__.animais.some(a=>a.numero==='999 X')"),
         "nem o parto nem um animal '999 X' sao criados")
    # numero antigo com texto, sem mexer, continua editavel (troca so o sexo)
    tela_partos(page)
    page.evaluate("() => { window.__DB__.partos.push({id:300, data:'2026-10-01', lote_id:6, numero_mae:'512 2S', sexo_bezerro:'macho', raca_bezerro:'angus', tipo:'nascimento', data_obito:null, causa_obito:null}); }")
    page.evaluate("async () => { await recarregarReproducao(); render(); }")
    page.locator('[data-edit-parto="300"]').click()
    page.select_option('#f-sexobezerro', 'femea'); page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    conf(parto_db(page, 300)["sexo_bezerro"] == "femea" and parto_db(page, 300)["numero_mae"] == "512 2S",
         "parto antigo com numero '512 2S' sem mexer no numero: salva o resto", str(page.avisos))
    # lista de numeros na entrada de animais
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('lote'); render(); }")
    page.select_option('#f-modoentrada', 'existente'); page.wait_for_timeout(60)
    page.select_option('#f-loteexistente', '6')
    page.fill('#f-qtdentrada', '2'); page.fill('#f-pesoentrada', '400')
    page.evaluate("() => { document.getElementById('f-numerosanimais').value = '801, 80a'; }")
    page.avisos.clear(); page.locator('[data-save="lote"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "80a" in page.avisos[0], "lista de numeros com '80a': nao salva e aponta qual", str(page.avisos))
    page.locator('#f-numerosanimais').type('x')
    conf("x" not in page.locator('#f-numerosanimais').input_value(), "lista de numeros nao aceita letra ao digitar")
    # nome do animal
    page.evaluate("() => { state.modal=null; editDraft=null; const a = state.animais.find(x=>x.id===1); editDraft = {...a, _editId:a.id}; state.modal={type:'animal'}; render(); }")
    page.fill('#f-nomeanimal', 'Mocha, marca 2S')
    page.locator('[data-save="animal"]').click(); page.wait_for_timeout(400)
    conf(page.evaluate("() => window.__DB__.animais.find(a=>a.id===1).nome") == "Mocha, marca 2S", "campo Nome grava texto livre")
    page.evaluate("() => { state.page='loteDetalhe'; state.loteDetalheId=6; state.loteDetalheContexto=null; render(); }")
    conf("Mocha, marca 2S" in page.inner_text("body"), "e aparece embaixo do numero no lote")
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

    # antes do SQL: banco sem as colunas novas
    print("\n  ANTES DE RODAR O SQL (banco sem tipo/obito/nome)")
    browser, page = abrir(pw, banco(com_colunas_novas=False))
    page.evaluate("() => { state.page='reproducaoGeral'; state.modal=null; editDraft=null; openNewModal('parto'); render(); }")
    page.select_option('#f-lote', '6'); page.fill('#f-numeromae', '128'); page.select_option('#f-sexobezerro', 'femea')
    page.evaluate("() => { window.__ESCRITAS__.length = 0; }")
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    ins = page.evaluate("() => window.__ESCRITAS__.filter(e=>e.tabela==='partos' && e.op==='insert').map(e=>e.v)")
    conf(len(ins) == 1 and "tipo" not in ins[0], "parto normal grava sem mandar a coluna nova 'tipo'", str(ins))
    page.evaluate("() => { state.modal=null; editDraft=null; const a = state.animais.find(x=>x.id===3); editDraft = {...a, _editId:a.id}; state.modal={type:'animal'}; render(); window.__ESCRITAS__.length = 0; }")
    page.select_option('#f-loteanimal', '3')
    page.locator('[data-save="animal"]').click(); page.wait_for_timeout(300)
    upd = page.evaluate("() => window.__ESCRITAS__.filter(e=>e.tabela==='animais' && e.op==='update').map(e=>e.v)")
    conf(len(upd) == 1 and "nome" not in upd[0], "editar animal sem preencher Nome nao manda a coluna 'nome'", str(upd))
    tela_partos(page)
    page.evaluate("() => { window.__SEM_COLUNA__ = {partos: 'data_obito'}; }")
    page.locator('[data-obito-parto="198"]').click()
    page.avisos.clear(); page.locator('[data-save="obitoBezerro"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "Rode no Supabase" in page.avisos[0], "obito antes do SQL: avisa pra rodar o SQL (nao mostra erro em ingles)", str(page.avisos))
    browser.close()

    # ================= ABORTO =================
    print("\n  ABORTO")
    browser, page = abrir(pw, banco())
    tela_partos(page)
    page.locator('[data-edit-parto="197"]').click()
    page.select_option('#f-tipoparto', 'aborto'); page.wait_for_timeout(80)
    conf(page.locator('#f-sexobezerro').count() == 0, "aborto esconde sexo e raca do bezerro")
    campo = page.locator('#f-numeromae'); campo.click(); campo.press("End"); campo.press("Backspace")
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(500)
    p197 = parto_db(page, 197)
    conf(p197["tipo"] == "aborto" and p197["sexo_bezerro"] is None and p197["numero_mae"] == "721", "parto 197 vira aborto da vaca 721, sem sexo de bezerro", str(p197))
    resumo = page.evaluate("() => { const l = state.lotes.find(x=>x.id===6); return {nasc: state.partos.filter(p=>p.loteId===6 && !partoEhAborto(p)).length, ab: state.partos.filter(p=>p.loteId===6 && partoEhAborto(p)).length}; }")
    texto = page.inner_text("body")
    conf(resumo == {"nasc": 2, "ab": 1}, "aborto sai dos nascidos e conta em Abortos", str(resumo))
    conf("Aborto" in texto, "lista mostra a situacao 'Aborto'")
    conf(page.evaluate("() => !partosSemDesmama(6).some(p=>p.id===197)"), "aborto nao aparece pra desmama")
    conf(page.evaluate("() => situacaoReprodutivaVaca(6, '721').detalheStatus").startswith("Abortou em"), "vaca 721 (prenha no diagnostico) aparece como 'Abortou'")
    # parto que ja tem desmama nao vira aborto
    page.locator('[data-edit-parto="199"]').click()
    page.select_option('#f-tipoparto', 'aborto'); page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "desmama" in page.avisos[0] and parto_db(page, 199)["tipo"] == "nascimento", "parto com desmama nao pode virar aborto", str(page.avisos))
    # novo aborto pelo botao
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('parto'); render(); }")
    page.select_option('#f-lote', '6'); page.select_option('#f-tipoparto', 'aborto'); page.wait_for_timeout(60)
    page.fill('#f-numeromae', '300')
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    novo = page.evaluate("() => window.__DB__.partos[window.__DB__.partos.length-1]")
    conf(novo["tipo"] == "aborto" and novo["numero_mae"] == "300" and novo["sexo_bezerro"] is None, "novo aborto grava tipo 'aborto'", str(novo))
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

    # ================= OBITO DO BEZERRO =================
    print("\n  OBITO DO BEZERRO ANTES DA DESMAMA")
    browser, page = abrir(pw, banco())
    tela_partos(page)
    conf(page.locator('[data-obito-parto="199"]').count() == 0, "bezerro ja desmamado nao tem botao de obito")
    page.locator('[data-obito-parto="198"]').click()
    page.fill('#f-dataobito', '2026-10-19'); page.avisos.clear()
    page.locator('[data-save="obitoBezerro"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "antes do nascimento" in page.avisos[0] and parto_db(page, 198)["data_obito"] is None, "obito antes do nascimento nao salva", str(page.avisos))
    page.fill('#f-dataobito', '2026-10-22'); page.fill('#f-causaobito', 'diarreia')
    page.locator('[data-save="obitoBezerro"]').click(); page.wait_for_timeout(400)
    p198 = parto_db(page, 198)
    conf(p198["data_obito"] == "2026-10-22" and p198["causa_obito"] == "diarreia", "obito grava data e causa", str(p198))
    conf("Bezerro morreu em 22/10/2026" in page.inner_text("body"), "lista mostra 'Bezerro morreu em 22/10/2026'")
    conf(page.evaluate("() => !partosSemDesmama(6).some(p=>p.id===198)"), "bezerro morto sai da lista de desmama")
    taxa = page.evaluate("() => taxasDesmamePorLote().find(r=>r.lote.id===6)")
    conf(taxa["nascidos"] == 3 and taxa["mortos"] == 1 and taxa["desmamados"] == 1, "taxa de desmame: continua nascido, conta em mortos", str({k: taxa[k] for k in ("nascidos","mortos","desmamados")}))
    page.locator('[data-obito-parto="198"]').click()
    page.locator('[data-remover-obito]').click(); page.wait_for_timeout(400)
    conf(parto_db(page, 198)["data_obito"] is None and page.evaluate("() => partosSemDesmama(6).some(p=>p.id===198)"), "Remover obito: volta pra desmama")
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

    # ================= NASCEU MORTO =================
    print("\n  NASCEU MORTO (nascimento com obito no mesmo dia)")
    browser, page = abrir(pw, banco())
    tela_partos(page)
    page.evaluate("() => { state.modal=null; editDraft=null; openNewModal('parto'); render(); }")
    page.select_option('#f-lote', '6'); page.select_option('#f-tipoparto', 'natimorto'); page.wait_for_timeout(60)
    conf(page.locator('#f-sexobezerro').count() == 1, "nasceu morto mantem sexo/raca do bezerro (opcional)")
    page.fill('#f-numeromae', '721'); page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    nm = page.evaluate("() => window.__DB__.partos[window.__DB__.partos.length-1]")
    conf(nm["numero_mae"] == "721" and nm.get("tipo", "nascimento") == "nascimento" and "tipo" not in nm and nm["data_obito"] == nm["data"] and nm["causa_obito"] == "nasceu morto",
         "grava nascimento com obito no dia do parto, causa 'nasceu morto', sem pedir sexo", str(nm) + str(page.avisos))
    nid = nm["id"]
    conf(page.evaluate(f"() => situacaoDoParto(state.partos.find(p=>p.id==={nid})).texto") == "Nasceu morto", "lista mostra 'Nasceu morto'")
    conf(page.evaluate(f"() => !partosSemDesmama(6).some(p=>p.id==={nid})"), "nao aparece pra desmama")
    t = page.evaluate("() => taxasDesmamePorLote().find(r=>r.lote.id===6)")
    conf(t["nascidos"] == 4 and t["mortos"] == 1, "conta como nascido e como morto antes da desmama", str({k: t[k] for k in ("nascidos","mortos")}))
    # editar: abre como 'Nasceu morto'; trocar a data leva o obito junto
    page.locator(f'[data-edit-parto="{nid}"]').click()
    conf(page.locator('#f-tipoparto').input_value() == "natimorto", "editar abre com 'Nasceu morto' marcado")
    page.fill('#f-data', '2026-10-25'); page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    nm = parto_db(page, nid)
    conf(nm["data"] == "2026-10-25" and nm["data_obito"] == "2026-10-25", "trocar a data do parto leva a data do obito junto", str(nm))
    # voltar para 'Nasceu o bezerro' limpa o obito
    page.locator(f'[data-edit-parto="{nid}"]').click()
    page.select_option('#f-tipoparto', 'nascimento'); page.wait_for_timeout(60); page.select_option('#f-sexobezerro', 'macho')
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    nm = parto_db(page, nid)
    conf(nm["data_obito"] is None and nm["causa_obito"] is None and nm["sexo_bezerro"] == "macho", "voltar para 'Nasceu o bezerro' tira o obito", str(nm))
    # obito depois do nascimento nao vira 'nasceu morto' sem remover antes
    page.evaluate("() => { const p = window.__DB__.partos.find(x=>x.id===198); p.data_obito='2026-10-22'; p.causa_obito='diarreia'; }")
    page.evaluate("async () => { await recarregarReproducao(); render(); }")
    page.locator('[data-edit-parto="198"]').click()
    conf(page.locator('#f-tipoparto').input_value() == "nascimento", "parto com obito dias depois abre como 'Nasceu o bezerro'")
    page.select_option('#f-tipoparto', 'natimorto'); page.wait_for_timeout(60); page.avisos.clear()
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(300)
    conf(page.avisos and "Remova o óbito" in page.avisos[0] and parto_db(page, 198)["data_obito"] == "2026-10-22", "e nao vira 'nasceu morto' sem remover o obito antes", str(page.avisos))
    # editar outro campo de um parto com obito posterior nao mexe no obito
    page.select_option('#f-tipoparto', 'nascimento'); page.wait_for_timeout(60); page.select_option('#f-racabezerro', 'nelore')
    page.locator('[data-save="parto"]').click(); page.wait_for_timeout(400)
    p198 = parto_db(page, 198)
    conf(p198["raca_bezerro"] == "nelore" and p198["data_obito"] == "2026-10-22" and p198["causa_obito"] == "diarreia", "editar a raca preserva o obito registrado", str(p198))
    conf(not page.erros, "nenhum erro de JavaScript", " | ".join(page.erros[:3]))
    browser.close()

print(f"\n  {passes} passaram, {falhas} falharam")
sys.exit(1 if falhas else 0)
