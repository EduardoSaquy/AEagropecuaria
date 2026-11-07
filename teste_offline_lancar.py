"""
AE Pecuaria: os funcionarios conseguem lancar SEM INTERNET (pedido do Eduardo, 07/11/2026: "preciso que os funcionarios
consigam lancar com o app off-line").

A fila de lancamentos ja existia (o que se lanca sem sinal fica no aparelho e sobe sozinho), mas o app so abria com os
lotes, dietas, ingredientes e animais se a internet respondesse: sem sinal na abertura as listas dos formularios ficavam
vazias. Agora cada carga que termina bem guarda uma copia desses cadastros no aparelho (separada por usuario) e o app abre
com ela. Prova:
  - a carga guarda a copia (cadastros + historico pequeno de reproducao), so com os campos que o app usa dos perfis;
  - abrindo SEM internet (aparelho sem rede, e rede "de mentira" que falha): lotes/dietas/animais na tela, aviso
    "Sem internet", formularios com as opcoes, e nada de aviso vermelho nem de "carregando";
  - lancar sem internet (leitura de cocho, saida de racao): vai para a fila, aparece "N pendente(s)", sobrevive a
    fechar e abrir o app sem sinal;
  - a copia traz o historico de reproducao que as regras consultam (partos da vaca, inseminacoes);
  - o sinal volta: a fila sobe sozinha, cada lancamento entra UMA vez (com a chave), os dados se atualizam, o aviso some
    e a copia e renovada; com uma janela de lancamento aberta nada e redesenhado por baixo de quem digita;
  - sinal fraco (rede que nao responde): a copia aparece na hora, a tela atualiza quando a rede responde sem apagar o que
    a pessoa digitou; passados 25 s vira "Sem internet"; "Tentar agora" avisa se ainda nao tem sinal;
  - copia de outro usuario nao e usada; sem copia e sem rede continua o aviso vermelho de antes; Sair apaga a copia;
  - aparelho sem espaco guarda so o que os lancamentos precisam.
"""
import json
import sys
from datetime import date, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
APP = "file://" + str(REPO / "AEpecuaria.html")
CHAVE = "aepecuaria_dados_offline_v1"
FILA = "aepecuaria_fila_offline_v1"
HOJE = date.today()
dia = lambda n: (HOJE - timedelta(days=n)).isoformat()

ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin", "ativo": True, "permissoes": {},
         "email": "eduardo@exemplo.com", "telefone": "11999990000"}


def monta_db(nome_lote="Curral 1"):
    return {
        "lotes": [
            {"id": 1, "nome": nome_lote, "destino": "confinamento", "numero_animais": 60, "data_inicio": dia(80), "data_fim": None, "dieta_id": 1, "sexo": "macho"},
            {"id": 2, "nome": "Vacas 07/08", "destino": "cria", "numero_animais": 40, "data_inicio": dia(200), "data_fim": None, "dieta_id": 1, "sexo": "femea"},
        ],
        "dietas": [{"id": 1, "nome": "Terminacao", "tipo": "confinamento", "itens": [{"ingredienteId": 1, "pct": 100}], "consumo_direto": True}],
        "ingredientes": [{"id": 1, "nome": "Milho", "unidade": "kg", "preco_kg": 1.2, "estoque_kg": 5000}],
        "animais": [
            {"id": 1, "numero": "100", "lote_id": 2, "sexo": "femea", "raca": "nelore", "status": "ativo"},
            {"id": 2, "numero": "101", "lote_id": 2, "sexo": "femea", "raca": "nelore", "status": "ativo"},
        ],
        "partos": [{"id": 1, "data": dia(120), "lote_id": 2, "numero_mae": "100", "sexo_bezerro": "macho", "raca_bezerro": "nelore", "tipo": "nascimento"}],
        "reproducao_custos": [{"id": 1, "data": dia(60), "lote_id": 2, "numero_vaca": "100", "item": "IATF", "custo": 80, "qual_inseminacao": "1ª"}],
        "pesagens": [], "diagnosticos_gestacionais": [], "desmamas": [], "saidas_racao": [], "leituras_cocho": [], "pasto": [],
        "producoes_racao": [], "abates": [], "precos_arroba": [], "movimentos": [], "manejos": [], "fazendas": [],
        "fazenda_atividades": [], "centros_custo": [], "lancamentos_financeiros": [], "config_financeiro": [], "funcionarios": [],
        "pesagens_animais": [], "protocolos_inseminacao": [], "profiles": [ADMIN],
    }


# Segura as consultas dos cadastros ate o teste abrir o portao (rede lenta). So o range() das 5 tabelas da 1a etapa.
PORTAO = """(() => {
  window.__PORTAO__ = new Promise(r => { window.__ABRIR__ = r; });
  const c0 = window.supabase.createClient;
  window.supabase.createClient = function (...a) {
    const cli = c0.apply(this, a);
    const from0 = cli.from;
    cli.from = (t) => {
      const q = from0(t);
      if (['ingredientes', 'dietas', 'lotes', 'animais', 'profiles'].includes(t)) {
        const r0 = q.range.bind(q);
        q.range = (de, ate) => window.__PORTAO__.then(() => r0(de, ate));
      }
      return q;
    };
    return cli;
  };
})()"""
# Conta quantas cargas o app pediu
CONTA_CARGAS = "() => { window.__LOADS__ = 0; const o = loadAll; loadAll = function (...a) { window.__LOADS__++; return o.apply(this, a); }; }"

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def abre(ctx, db=None, portao=False, relogio=False, espera="completo"):
    page = ctx.new_page()
    page.avisos = []
    page.erros = []
    page.nativos = []
    page.on("console", lambda m: page.avisos.append(m.text[len("[aviso] "):]) if m.text.startswith("[aviso] ") else None)
    page.on("pageerror", lambda e: page.erros.append(str(e)) if "ServiceWorker" not in str(e) else None)
    page.on("dialog", lambda d: (page.nativos.append((d.type, d.message)), d.accept()))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    if relogio:
        page.clock.install()
    page.add_init_script(STUB)
    if portao:
        page.add_init_script(PORTAO)
    page.add_init_script(f"window.__DB__ = {json.dumps(db or monta_db())}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto(APP)
    if espera == "completo":
        page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico && state.lotes.length > 0", timeout=30000)
    elif espera == "tela":
        page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados", timeout=30000)
    page.wait_for_timeout(200)
    return page


def copia(page):
    return page.evaluate(f"() => JSON.parse(localStorage.getItem('{CHAVE}') || 'null')")


def fila(page):
    return page.evaluate(f"() => JSON.parse(localStorage.getItem('{FILA}') || '[]')")


def sem_internet(ctx, page, ligado=True, aparelho=True):
    """aparelho=True: o navegador sabe que esta sem rede; False: rede 'de mentira' (wifi sem internet), toda consulta falha."""
    ctx.set_offline(bool(ligado and aparelho))
    page.evaluate("(v) => { if (v) localStorage.setItem('__sem_rede', '1'); else localStorage.removeItem('__sem_rede'); }", bool(ligado))


def corpo(page):
    return page.inner_text("body")


def abre_modal(page, tipo):
    r = page.evaluate("(t) => { const r = openNewModal(t); render(); return r; }", tipo)
    page.wait_for_timeout(150)
    return r


def lanca_cocho(page):
    abre_modal(page, "cocho")
    page.select_option("#f-lote", "1")
    page.click('[data-save="cocho"]')
    page.wait_for_timeout(500)


def lanca_racao(page):
    abre_modal(page, "saidaRacao")
    page.select_option("#f-lote", "1")
    page.select_option("#f-dieta", "1")
    page.fill("#f-qtdracao", "500")
    page.click('[data-save="saidaRacao"]')
    page.wait_for_timeout(500)


with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    ctx = browser.new_context(viewport={"width": 1280, "height": 800})

    # ------------------------------------------------------------------ 1. a carga guarda a copia
    print("== a carga com internet guarda a copia no aparelho")
    p = abre(ctx)
    c = copia(p)
    conf(c is not None and c["uid"] == "u1" and c.get("salvoEm"), "a copia existe, e e do usuario logado", str(c)[:120])
    e = (c or {}).get("essenciais") or {}
    conf(len(e.get("lot", [])) == 2 and len(e.get("diet", [])) == 1 and len(e.get("ing", [])) == 1 and len(e.get("anim", [])) == 2,
         "tem lotes, dietas, ingredientes e animais", str({k: len(v) for k, v in e.items()}))
    h = (c or {}).get("historico") or {}
    conf(len(h.get("prt", [])) == 1 and len(h.get("rc", [])) == 1, "tem o historico pequeno de reproducao (partos, inseminacoes)", str({k: len(v) for k, v in h.items()}))
    bruto = p.evaluate(f"() => localStorage.getItem('{CHAVE}')")
    conf("eduardo@exemplo.com" not in bruto and "11999990000" not in bruto and '"nome":"Eduardo"' in bruto,
         "dos perfis guarda so o que o app usa (sem e-mail nem telefone)")
    conf(p.evaluate("() => state.semSinal === false && state.dadosDoAparelho === null") and "Sem internet" not in corpo(p), "com internet nao aparece nenhum aviso")
    p.close()

    # ------------------------------------------------------------------ 2. abrir sem internet
    print("== abrindo o app SEM internet (aparelho sem rede)")
    p = abre(ctx)
    sem_internet(ctx, p, True, True)
    p.reload()
    p.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados", timeout=30000)
    p.wait_for_timeout(300)
    est = p.evaluate("() => ({l: state.lotes.length, d: state.dietas.length, i: state.ingredientes.length, a: state.animais.length, s: state.semSinal, e: state.erroCarga, h: state.carregandoHistorico})")
    conf(est == {"l": 2, "d": 1, "i": 1, "a": 2, "s": True, "e": "", "h": False}, "lotes, dietas, ingredientes e animais estao na tela", str(est))
    txt = corpo(p)
    conf("Sem internet" in txt and "Pode lançar normalmente" in txt, "aviso 'Sem internet' explica que pode lancar")
    conf("Os dados não carregaram" not in txt and "Carregando os dados" not in txt, "sem aviso vermelho e sem 'carregando'")
    conf("Estoque, custos e resultados só aparecem completos com internet" in txt, "avisa que estoque, custo e resultado precisam de internet")
    conf(p.evaluate("() => state.perfil && state.perfil.nome") == "Eduardo", "o perfil guardado abre o app (nao cai no login)")

    # ------------------------------------------------------------------ 3. lancar sem internet
    print("== lancando sem internet")
    p.avisos.clear()
    r = abre_modal(p, "cocho")
    opcoes = p.evaluate("() => [...document.querySelectorAll('#f-lote option')].map(o => o.textContent.trim())")
    conf(r is not False and "Curral 1" in opcoes, "a leitura de cocho abre com os currais (do aparelho)", str(opcoes))
    p.locator('[data-close="1"]').first.click()
    lanca_cocho(p)
    f = fila(p)
    conf(len(f) == 1 and f[0]["type"] == "cocho" and "Curral 1" in f[0]["label"] and f[0]["campos"].get("_chave"),
         "a leitura de cocho foi para a fila, com a chave", str(f)[:200])
    conf(any("Sem conexão" in a and "salvo neste aparelho" in a for a in p.avisos), "o aviso diz que ficou guardado no aparelho", str(p.avisos))
    lanca_racao(p)
    f = fila(p)
    conf(len(f) == 2 and f[1]["type"] == "saidaRacao" and f[1]["campos"].get("_dietaSnapshot"), "a saida de racao foi para a fila, com a dieta de agora", str(f)[:240])
    conf("2 pendente(s)" in corpo(p), "o topo mostra '2 pendente(s)'")
    conf(p.evaluate("() => state.modal === null"), "a janela fechou depois de guardar")
    sem = p.evaluate("() => window.__ESCRITAS__.length")
    conf(sem == 0, "nada foi gravado no servidor sem internet", str(sem))

    # ------------------------------------------------------------------ 4. historico na copia
    print("== a copia traz o historico que as regras consultam")
    ciclo = p.evaluate("() => { const c = cicloReprodutivoVaca('100', hojeStr()); return {crias: c.crias, ia: c.inseminacoesDesdeParto.length, proxima: c.proxima}; }")
    conf(ciclo == {"crias": 1, "ia": 1, "proxima": 2}, "a vaca 100 tem 1 cria e 1 inseminacao desde o parto: a proxima e a 2a (a regra das 3 IATF funciona)", str(ciclo))

    # ------------------------------------------------------------------ 5. fechar e abrir sem sinal
    print("== fechar o app e abrir de novo, ainda sem sinal")
    p.reload()
    p.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados", timeout=30000)
    p.wait_for_timeout(300)
    conf(len(fila(p)) == 2 and "2 pendente(s)" in corpo(p) and p.evaluate("() => state.lotes.length") == 2, "os 2 lancamentos continuam pendentes e os dados continuam na tela")

    # ------------------------------------------------------------------ 6. tentar agora sem sinal
    print("== 'Tentar agora' sem sinal")
    p.avisos.clear()
    p.click(".aviso-sem-sinal [data-recarregar-dados]")
    p.wait_for_timeout(500)
    conf(any("Ainda sem internet" in a for a in p.avisos) and p.evaluate("() => state.semSinal"), "avisa que ainda nao tem sinal e nao perde nada", str(p.avisos))

    # ------------------------------------------------------------------ 7. o sinal volta
    print("== o sinal volta")
    # janela aberta: o app nao recarrega por baixo de quem digita
    p.evaluate(CONTA_CARGAS)
    abre_modal(p, "cocho")
    p.fill("#f-obs", "texto que nao pode sumir")
    sem_internet(ctx, p, False)
    p.evaluate("() => aoVoltarSinal()")
    p.wait_for_timeout(1500)
    conf(p.evaluate("() => window.__LOADS__") == 0, "com a janela aberta o app nao pede carga nova", str(p.evaluate("() => window.__LOADS__")))
    conf(len(fila(p)) == 0, "mas a fila sobe")
    conf(p.input_value("#f-obs") == "texto que nao pode sumir", "com a janela aberta o que foi digitado continua la")
    conf(p.evaluate("() => state.semSinal"), "e a tela segue em 'sem internet' ate a janela fechar")
    p.locator('[data-close="1"]').first.click()
    p.evaluate("() => aoVoltarSinal()")
    p.wait_for_function("() => state.semSinal === false && !state.dadosDoAparelho && !state.carregandoHistorico", timeout=15000)
    f = fila(p)
    conf(len(f) == 0, "a fila subiu inteira", str(f)[:200])
    db_estado = p.evaluate("() => ({cocho: window.__DB__.leituras_cocho, saidas: window.__DB__.saidas_racao, movs: window.__DB__.movimentos})")
    conf(len(db_estado["cocho"]) == 1 and db_estado["cocho"][0].get("client_uuid"), "a leitura de cocho entrou UMA vez, com a chave", str(db_estado["cocho"]))
    conf(len(db_estado["saidas"]) == 1 and len(db_estado["movs"]) == 1, "a saida de racao entrou UMA vez, com a baixa do milho", str(db_estado)[:240])
    conf("Sem internet" not in corpo(p) and "pendente" not in corpo(p), "o aviso e o contador de pendencias sumiram")
    nova = copia(p)
    conf(nova and nova["salvoEm"] > c["salvoEm"], "a copia foi renovada com os dados novos")
    p.close()

    # ------------------------------------------------------------------ 8. rede de mentira (wifi sem internet)
    print("== wifi sem internet (o navegador acha que tem rede, mas toda consulta falha)")
    p = abre(ctx)
    sem_internet(ctx, p, True, False)
    p.reload()
    p.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && state.semSinal", timeout=30000)
    est = p.evaluate("() => ({l: state.lotes.length, s: state.semSinal, e: state.erroCarga})")
    conf(est == {"l": 2, "s": True, "e": ""}, "abre com a copia e avisa 'sem internet'", str(est))
    lanca_cocho(p)
    conf(len(fila(p)) == 1, "e o lancamento tambem vai para a fila")
    # nao deixa de funcionar depois de uma carga que falha no meio: as listas nao sao apagadas
    p.evaluate("async () => { await loadAll(); }")
    conf(p.evaluate("() => state.lotes.length") == 2 and p.evaluate("() => state.semSinal"), "uma nova tentativa sem sinal nao apaga as listas")
    sem_internet(ctx, p, False)
    p.evaluate("() => aoVoltarSinal()")
    p.wait_for_function("() => state.semSinal === false && !state.carregandoHistorico", timeout=15000)
    conf(len(fila(p)) == 0 and p.evaluate("() => window.__DB__.leituras_cocho.length") == 1, "voltando o sinal sobe a fila")
    p.close()

    # ------------------------------------------------------------------ 9. sinal fraco: a copia aparece na hora
    print("== sinal fraco: a copia aparece na hora e a tela atualiza quando a rede responde")
    p = abre(ctx, db=monta_db("Curral 1 NOVO"), portao=True, espera="tela")
    est = p.evaluate("() => ({l: state.lotes.map(x => x.nome), c: !!state.dadosDoAparelho, s: state.semSinal, e: state.erroCarga})")
    conf(est["l"][0] == "Curral 1" and est["c"] and not est["s"] and est["e"] == "", "com a rede parada mostra os lotes do aparelho", str(est))
    conf("Mostrando os dados guardados neste aparelho" in corpo(p), "e diz que sao os dados do aparelho")
    r = abre_modal(p, "cocho")
    conf(r is not False and p.locator("#f-lote option").count() >= 2, "ja da para abrir o lancamento")
    p.fill("#f-obs", "digitando enquanto a rede nao responde")
    p.evaluate("() => window.__ABRIR__()")
    p.wait_for_function("() => state.dadosDoAparelho === null && !state.carregandoHistorico", timeout=15000)
    conf(p.evaluate("() => state.lotes[0].nome") == "Curral 1 NOVO", "quando a rede responde os dados novos entram")
    conf(p.input_value("#f-obs") == "digitando enquanto a rede nao responde", "e o que foi digitado na janela aberta nao se perde")
    p.locator('[data-close="1"]').first.click()
    conf("Mostrando os dados guardados" not in corpo(p), "fechada a janela, o aviso de dados do aparelho some")
    p.close()

    # ------------------------------------------------------------------ 10. rede que nunca responde: 25 s
    print("== rede que nunca responde")
    p = abre(ctx, portao=True, relogio=True, espera="tela")
    p.evaluate(CONTA_CARGAS)
    p.clock.fast_forward(26000)
    p.wait_for_timeout(300)
    est = p.evaluate("() => ({s: state.semSinal, e: state.erroCarga, l: state.lotes.length})")
    conf(est == {"s": True, "e": "", "l": 2}, "passados 25 s fica 'sem internet' com os dados do aparelho (nada de aviso vermelho)", str(est))
    conf("Sem internet" in corpo(p), "o aviso aparece")
    p.clock.fast_forward(35000)
    p.wait_for_timeout(300)
    conf(p.evaluate("() => window.__LOADS__") >= 1, "e o app tenta de novo sozinho (sem empilhar uma tentativa sobre a outra)", str(p.evaluate("() => window.__LOADS__")))
    p.close()

    # ------------------------------------------------------------------ 11. copia de outro usuario / sem copia
    print("== copia de outro usuario e abrir sem copia")
    p = abre(ctx)
    p.evaluate(f"() => {{ const d = JSON.parse(localStorage.getItem('{CHAVE}')); d.uid = 'u2'; localStorage.setItem('{CHAVE}', JSON.stringify(d)); }}")
    sem_internet(ctx, p, True, False)
    p.reload()
    p.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados", timeout=30000)
    p.wait_for_timeout(300)
    est = p.evaluate("() => ({l: state.lotes.length, s: state.semSinal, e: state.erroCarga})")
    conf(est["l"] == 0 and not est["s"] and "lotes" in est["e"], "a copia de outro usuario NAO e usada: aparece o aviso vermelho de antes", str(est))
    conf("Os dados não carregaram" in corpo(p), "e o aviso vermelho com 'tente de novo' aparece")
    sem_internet(ctx, p, False)
    p.close()

    # ------------------------------------------------------------------ 12. Sair apaga a copia
    print("== Sair apaga a copia")
    p = abre(ctx)
    conf(copia(p) is not None, "(com internet a copia volta a existir)")
    p.evaluate("() => fazerLogout()")
    p.wait_for_timeout(300)
    conf(copia(p) is None, "depois de Sair a copia nao fica no aparelho")
    p.close()

    # ------------------------------------------------------------------ 13. aparelho sem espaco
    print("== aparelho sem espaco")
    ctx2 = browser.new_context(viewport={"width": 1280, "height": 800})
    p = ctx2.new_page()
    p.on("pageerror", lambda e: None)
    p.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    p.add_init_script(STUB)
    p.add_init_script(f"""(() => {{
      const set0 = Storage.prototype.setItem;
      Storage.prototype.setItem = function (k, v) {{
        if (k === '{CHAVE}' && v.includes('"historico":{{')) throw new DOMException('cheio', 'QuotaExceededError');
        return set0.call(this, k, v);
      }};
    }})()""")
    p.add_init_script(f"window.__DB__ = {json.dumps(monta_db())}; window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    p.goto(APP)
    p.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico && state.lotes.length > 0", timeout=30000)
    p.wait_for_timeout(300)
    c2 = copia(p)
    conf(c2 is not None and len(c2["essenciais"]["lot"]) == 2 and c2.get("historico") is None, "sem espaco para o historico guarda so os cadastros", str(c2)[:100])
    ctx2.close()

    ctx.close()
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
