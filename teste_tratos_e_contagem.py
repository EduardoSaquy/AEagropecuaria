"""
Tratos do dia por lote e contagem de estoque (14/11/2026, AE Pecuaria).
Pedido do Eduardo depois de achar ~30% dos tratos da Sequestro sem lancar:
(1) o lote informa quantos tratos recebe por dia e a Saida de Racao mostra
quantos foram lancados hoje e os dias dos ultimos 7 com trato faltando;
(4) contagem de estoque: digita o que foi contado e o app lanca um ajuste
por ingrediente, numa gravacao so. Dados inventados.
"""
import json, sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
RUIDO = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")

passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

ADMIN = {"id": "u1", "nome": "Chefe", "usuario": "chefe", "papel": "admin", "ativo": True, "permissoes": {}}
OPERADOR = {"id": "u2", "nome": "Peao", "usuario": "peao", "papel": "operador", "ativo": True,
            "permissoes": {"confinamento": "editar", "insumos": "visualizar"}}

# Datas relativas ao dia de hoje do navegador (o app usa hojeStr()).
MONTA = r"""
(() => {
  const d = n => { const x = new Date(); x.setHours(12); x.setDate(x.getDate()+n);
    return `${x.getFullYear()}-${String(x.getMonth()+1).padStart(2,'0')}-${String(x.getDate()).padStart(2,'0')}`; };
  window.__D = d;
  const vazias = ["fazendas","animais","abates","producoes_racao","leituras_cocho","manejos","reproducao_custos",
    "diagnosticos_gestacionais","partos","desmamas","custos_fixos","precos_arroba","titulos","alertas","pesagens",
    "pesagens_animais","protocolos_inseminacao","lancamentos_financeiros","centros_custo"];
  const db = {}; vazias.forEach(t => db[t] = []);
  db.dietas = [{id:1, nome:"Dieta X", tipo:"confinamento", itens:[], consumo_direto:false}];
  db.lotes = [
    {id:1, nome:"Curral A", destino:"confinamento", sexo:"macho", numero_animais:100, data_inicio:d(-30), data_fim:null, tratos_por_dia:4},
    {id:2, nome:"Curral B", destino:"confinamento", sexo:"macho", numero_animais:80, data_inicio:d(-30), data_fim:null, tratos_por_dia:3},
    {id:3, nome:"Curral C", destino:"confinamento", sexo:"macho", numero_animais:50, data_inicio:d(-30), data_fim:null, tratos_por_dia:null},
    {id:4, nome:"Recria 1", destino:"pasto", sexo:"macho", numero_animais:60, data_inicio:d(-2), data_fim:null, tratos_por_dia:1},
    {id:5, nome:"Curral Velho", destino:"confinamento", sexo:"macho", numero_animais:0, data_inicio:d(-60), data_fim:d(-20), tratos_por_dia:4},
    {id:6, nome:"Vacas", destino:"cria", sexo:"femea", numero_animais:40, data_inicio:d(-30), data_fim:null, tratos_por_dia:null},
  ];
  const sr = []; let id = 1;
  const poe = (lote, dia, n) => { for (let i=0;i<n;i++) sr.push({id:id++, data:d(dia), lote_id:lote, dieta_id:1, quantidade_kg:500}); };
  poe(1, 0, 2); poe(1, -1, 4); poe(1, -2, 3); /* -3: nada */ poe(1, -4, 4); poe(1, -5, 4); poe(1, -6, 4); poe(1, -7, 4);
  for (let k=0;k>=-7;k--) poe(2, k, 3);
  db.saidas_racao = sr;
  db.pasto = [{id:1, data:d(-1), lote_id:4, dieta_id:1, quantidade:100}];
  db.ingredientes = [
    {id:1, nome:"Milho", unidade:"kg", preco_kg:1, estoque_min:0},
    {id:2, nome:"Nucleo BI", unidade:"kg", preco_kg:7, estoque_min:0},
    {id:3, nome:"Ureia", unidade:"kg", preco_kg:4, estoque_min:0},
  ];
  db.movimentos = [
    {id:1, data:d(-10), ingrediente_id:1, tipo:"entrada", quantidade:1000, preco_kg:1, ajuste:false},
    {id:2, data:d(-5), ingrediente_id:1, tipo:"saida", quantidade:300, ajuste:false},
    {id:3, data:d(0), ingrediente_id:1, tipo:"saida", quantidade:100, ajuste:false},
    {id:4, data:d(-10), ingrediente_id:2, tipo:"entrada", quantidade:500, preco_kg:7, ajuste:false},
    {id:5, data:d(-10), ingrediente_id:3, tipo:"entrada", quantidade:50, preco_kg:4, ajuste:false},
  ];
  window.__DB__ = Object.assign(window.__DB__ || {}, db);
})();
"""

def abrir(browser, perfil, fila=None, w=1280):
    page = browser.new_page(viewport={"width": w, "height": 900})
    st = {"erros": [], "avisos": [], "dialogos": []}
    page.on("pageerror", lambda e: st["erros"].append(str(e)))
    page.on("console", lambda m: st["avisos"].append(m.text) if m.text.startswith("[aviso]") else None)
    def dlg(d):
        st["dialogos"].append(d.message); d.accept()
    page.on("dialog", dlg)
    page.route("**/fonts.googleapis.com/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(f"window.__DB__ = {{profiles: {json.dumps([perfil])}}}; window.__SESSAO__ = {{user:{{id:'{perfil['id']}'}}, access_token:'x'}};")
    page.add_init_script(MONTA)
    if fila is not None:
        page.add_init_script(f"localStorage.setItem('aepecuaria_fila_offline_v1', JSON.stringify({fila}));")
    page.goto((REPO / "AEpecuaria.html").as_uri())
    page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico", timeout=15000)
    return page, st

def ir(page, pagina):
    page.evaluate(f"() => {{ state.modal=null; state.page='{pagina}'; render(); }}"); page.wait_for_timeout(200)

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")

    # ================= TRATOS DO DIA =================
    print("\n  TRATOS DO DIA")
    fila = "[{queueId:'q1', type:'saidaRacao', label:'x', criadoEm:'', campos:{loteId:1, data:window.__D(0), dietaId:1, quantidadeKg:500}}]"
    page, st = abrir(browser, ADMIN, fila=fila)
    conf(not [e for e in st["erros"] if not any(r in e for r in RUIDO)], "abre sem erro de JavaScript", " | ".join(st["erros"][:3]))
    ir(page, "racao")
    card = page.locator(".tratos-dia")
    conf(card.count() == 1, "Saida de Racao do Confinamento mostra o cartao Tratos de hoje")
    a = page.locator('[data-trato-lote="1"]')
    conf(a.count() == 1 and "3 de 4" in a.inner_text(), "Curral A: 2 lancados + 1 na fila sem internet = 3 de 4 hoje", a.inner_text() if a.count() else "")
    conf("falta 1" in a.inner_text(), "diz quantos faltam hoje")
    dias = a.locator("[data-trato-dias-faltando]")
    conf(dias.get_attribute("data-trato-dias-faltando") == "2", "ultimos 7 dias: 2 dias com trato faltando (3 de 4 e 0 de 4)", dias.inner_text())
    dm = lambda n: page.evaluate(f"() => window.__D({n}).split('-').reverse().slice(0,2).join('/')")
    t = dias.inner_text()
    conf(f"{dm(-2)} (3 de 4)" in t and f"{dm(-3)} (0 de 4)" in t, "mostra cada dia e quantos foram lancados", t)
    b = page.locator('[data-trato-lote="2"]')
    conf(b.count() == 1 and "3 de 3" in b.inner_text() and "todos os tratos" in b.inner_text(), "Curral B completo hoje e na semana", b.inner_text() if b.count() else "")
    conf(page.locator('[data-trato-lote="3"]').count() == 0, "lote sem tratos por dia nao entra na conferencia")
    conf(page.locator('[data-trato-lote="5"]').count() == 0, "lote encerrado nao entra na conferencia")
    conf("pill-warn" in (a.locator(".pill").get_attribute("class") or "") and "pill-ok" in (b.locator(".pill").get_attribute("class") or ""),
         "hoje incompleto em amarelo, completo em verde")
    ir(page, "pasto")
    r = page.locator('[data-trato-lote="4"]')
    conf(r.count() == 1 and "0 de 1" in r.inner_text(), "Recria: conta a saida de racao da Recria (0 de 1 hoje)", r.inner_text() if r.count() else "")
    conf(r.locator("[data-trato-dias-faltando]").get_attribute("data-trato-dias-faltando") == "1",
         "lote que comecou ha 2 dias: so confere desde o inicio (1 dia faltando)", r.inner_text())
    ir(page, "racaoCria")
    conf(page.locator(".tratos-dica").count() == 0 and page.locator(".tratos-dia").count() == 0,
         "Cria sem lote com tratos por dia: nada aparece (la nao ha trato diario)")
    page.evaluate("() => { state.lotes.forEach(l => { if (l.destino==='confinamento') l.tratosPorDia = null; }); state.page='racao'; render(); }"); page.wait_for_timeout(150)
    conf(page.locator(".tratos-dica").count() == 1 and page.locator(".tratos-dia").count() == 0,
         "Confinamento sem lote com tratos por dia: so a dica de onde informar")
    page.goto(page.url); page.wait_for_function("() => typeof state !== 'undefined' && state.carregouDados && !state.carregandoHistorico", timeout=15000)
    page.evaluate("() => { state.carregandoHistorico = true; state.page='racao'; render(); }"); page.wait_for_timeout(150)
    conf("Carregando os lançamentos" in page.locator(".tratos-dia").inner_text() and page.locator("[data-trato-lote]").count() == 0,
         "historico ainda carregando: nao mostra numero (seria falso)")
    page.evaluate("() => { state.carregandoHistorico = false; render(); }")
    for w in (390, 320):
        page.set_viewport_size({"width": w, "height": 844}); ir(page, "racao")
        larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
        conf(larg <= 0, f"Saida de Racao com o cartao sem rolar de lado em {w} px", f"passa {larg} px")
    page.set_viewport_size({"width": 1280, "height": 900})

    # lote: campo tratos por dia
    print("\n  LOTE: tratos por dia")
    def editar(i):
        page.evaluate(f"() => {{ const l = state.lotes.find(x=>x.id==={i}); editDraft = {{...l, dataFim: l.dataFim||'', _editId: l.id}}; state.modal={{type:'lote'}}; render(); }}")
        page.wait_for_timeout(150)
    def salvar(): page.locator('[data-save="lote"]').click(); page.wait_for_timeout(500)
    lote_db = lambda i: page.evaluate(f"() => window.__DB__.lotes.find(l=>l.id==={i})")
    editar(1)
    conf(page.locator("#f-tratospordia").input_value() == "4", "editar mostra os tratos por dia gravados")
    page.locator("#f-tratospordia").fill("3"); salvar()
    conf(lote_db(1)["tratos_por_dia"] == 3, "salvar grava 3", str(lote_db(1)))
    editar(1); page.locator("#f-tratospordia").fill(""); salvar()
    conf(lote_db(1)["tratos_por_dia"] is None, "apagar o campo limpa (manda nulo)")
    page.evaluate("() => { window.__upd = []; const o = db.from.bind(db); db.from = t => { const q = o(t); if (t==='lotes') { const u = q.update.bind(q); q.update = r => { window.__upd.push(r); return u(r); }; } return q; }; }")
    editar(3); salvar()
    upd = page.evaluate("() => window.__upd")
    conf(len(upd) == 1 and "tratos_por_dia" not in upd[0], "lote sem tratos: salvar nao manda a coluna (funciona antes do SQL)", str(upd))
    for ruim in ("13", "2.5"):
        st["avisos"].clear(); editar(3); page.locator("#f-tratospordia").fill(ruim); salvar()
        conf(any("Tratos por dia" in x for x in st["avisos"]) and lote_db(3)["tratos_por_dia"] is None, f"valor {ruim} e barrado com aviso", str(st["avisos"][-1:]))
    page.close()

    # ================= CONTAGEM DE ESTOQUE =================
    print("\n  CONTAGEM DE ESTOQUE")
    page, st = abrir(browser, ADMIN)
    ir(page, "estoque")
    btn = page.locator('[data-contagem-estoque]')
    conf(btn.count() == 1 and btn.is_enabled(), "Estoque tem o botao Contagem de estoque")
    btn.click(); page.wait_for_timeout(200)
    linhas = page.locator(".contagem-tabela tbody tr")
    conf(linhas.count() == 3, "a janela lista todos os ingredientes", str(linhas.count()))
    milho = page.locator(".contagem-tabela tr", has_text="Milho")
    conf("600,0 kg" in milho.inner_text(), "saldo do sistema hoje: 1.000 - 300 - 100 = 600 kg", milho.inner_text())
    page.locator('[data-contagem-ing="1"]').fill("550")
    conf("−50,0 kg" in page.locator('[data-contagem-dif="1"]').inner_text(), "diferenca aparece ao digitar (-50 kg)", page.locator('[data-contagem-dif="1"]').inner_text())
    page.locator('[data-contagem-ing="2"]').fill("500")
    conf(page.locator('[data-contagem-dif="2"]').inner_text() == "igual", "contado igual ao sistema: 'igual'")
    page.evaluate("() => { window.__ins = 0; const o = db.from.bind(db); db.from = t => { const q = o(t); if (t==='movimentos') { const i = q.insert.bind(q); q.insert = r => { window.__ins++; return i(r); }; } return q; }; }")
    antes = page.evaluate("() => window.__DB__.movimentos.length")
    page.locator('[data-save="contagemEstoque"]').click(); page.wait_for_timeout(600)
    novos = page.evaluate(f"() => window.__DB__.movimentos.slice({antes})")
    hoje = page.evaluate("() => window.__D(0)")
    conf(len(novos) == 1 and novos[0]["ingrediente_id"] == 1 and novos[0]["tipo"] == "saida" and float(novos[0]["quantidade"]) == 50
         and novos[0]["ajuste"] is True and novos[0]["data"] == hoje and novos[0].get("preco_kg") is None,
         "grava so o milho: saida de ajuste de 50 kg, sem preco, na data da contagem (nucleo igual e ureia em branco ficam)", str(novos))
    conf(page.evaluate("() => window.__ins") == 1, "uma gravacao so")
    conf(any("Milho" in d and "−50,0 kg" in d for d in st["dialogos"]), "pergunta antes, com o resumo do que vai ajustar", str(st["dialogos"][-1:]))
    conf(page.evaluate("() => state.modal") is None and page.evaluate("() => saldoIngrediente(1)") == 550, "fecha a janela e o saldo do milho passa a 550")
    hist = page.locator("[data-historico-ajustes]")
    conf(hist.count() == 1 and "Milho" in hist.inner_text() and "−50,0 kg" in hist.inner_text() and "R$ 50,00" in hist.inner_text(),
         "historico de contagens mostra o ajuste e o valor", hist.inner_text() if hist.count() else "")

    # data passada: saldo daquele dia
    btn = page.locator('[data-contagem-estoque]'); btn.click(); page.wait_for_timeout(200)
    page.evaluate("() => { const el = document.getElementById('f-datacontagem'); el.value = window.__D(-5); el.dispatchEvent(new Event('change', {bubbles:true})); }")
    page.wait_for_timeout(200)
    conf("700,0 kg" in page.locator(".contagem-tabela tr", has_text="Milho").inner_text(),
         "contagem numa data passada usa o saldo daquele dia (700 kg, sem a saida de hoje)", page.locator(".contagem-tabela tr", has_text="Milho").inner_text())
    page.locator('[data-contagem-ing="3"]').fill("40")
    page.evaluate("() => { const el = document.getElementById('f-datacontagem'); el.value = window.__D(-6); el.dispatchEvent(new Event('change', {bubbles:true})); }")
    page.wait_for_timeout(200)
    conf(page.locator('[data-contagem-ing="3"]').input_value() == "40", "trocar a data nao apaga o que ja foi digitado")
    page.evaluate("() => { const el = document.getElementById('f-datacontagem'); el.value = window.__D(-5); el.dispatchEvent(new Event('change', {bubbles:true})); }")
    page.wait_for_timeout(200)
    antes = page.evaluate("() => window.__DB__.movimentos.length")
    page.locator('[data-save="contagemEstoque"]').click(); page.wait_for_timeout(600)
    novos = page.evaluate(f"() => window.__DB__.movimentos.slice({antes})")
    conf(len(novos) == 1 and novos[0]["ingrediente_id"] == 3 and float(novos[0]["quantidade"]) == 10 and novos[0]["data"] == page.evaluate("() => window.__D(-5)"),
         "ajuste gravado na data da contagem", str(novos))

    # recusas
    def abre_e(f):
        page.evaluate("() => { state.modal=null; render(); }"); page.locator('[data-contagem-estoque]').click(); page.wait_for_timeout(150); f()
        n = page.evaluate("() => window.__DB__.movimentos.length")
        st["avisos"].clear(); page.locator('[data-save="contagemEstoque"]').click(); page.wait_for_timeout(400)
        return n, page.evaluate("() => window.__DB__.movimentos.length"), list(st["avisos"])
    n0, n1, av = abre_e(lambda: None)
    conf(n0 == n1 and any("Nenhum ingrediente foi contado" in x for x in av), "nada digitado: avisa e nao grava")
    n0, n1, av = abre_e(lambda: page.locator('[data-contagem-ing="1"]').fill("-5"))
    conf(n0 == n1 and any("inválida" in x for x in av), "quantidade negativa e barrada")
    n0, n1, av = abre_e(lambda: page.evaluate("() => { document.getElementById('f-datacontagem').value = window.__D(3); }"))
    conf(n0 == n1 and any("futuro" in x for x in av), "data no futuro e barrada")
    n0, n1, av = abre_e(lambda: page.locator('[data-contagem-ing="2"]').fill("500"))
    conf(n0 == n1 and any("nada a ajustar" in x for x in av), "tudo igual ao sistema: diz que nao ha o que ajustar e nao grava")

    page.evaluate("() => { state.carregandoHistorico = true; state.modal=null; render(); }"); page.wait_for_timeout(150)
    conf(page.locator('[data-contagem-estoque]').is_disabled(), "botao desligado enquanto o historico do estoque carrega (o saldo estaria errado)")
    page.evaluate("() => { state.carregandoHistorico = false; render(); }")
    page.set_viewport_size({"width": 390, "height": 844}); page.wait_for_timeout(150)
    page.locator('[data-contagem-estoque]').click(); page.wait_for_timeout(200)
    larg = page.evaluate("() => document.documentElement.scrollWidth - document.documentElement.clientWidth")
    modal_larg = page.evaluate("() => { const m = document.querySelector('.modal'); return m.scrollWidth - m.clientWidth; }")
    conf(larg <= 0 and modal_larg <= 0, "janela da contagem sem rolar de lado em 390 px", f"pagina {larg}, janela {modal_larg}")
    page.close()

    page, st = abrir(browser, OPERADOR)
    ir(page, "estoque")
    conf(page.locator('[data-contagem-estoque]').count() == 0, "quem so visualiza insumos nao ve o botao de contagem")
    page.close()
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
