"""
Numero de brinco repetido entre sexos diferentes nao pode fundir animais.

Bug relatado pelo Eduardo em 02/09/2026: pesou um lote de macho com um
numero que ja existia como femea (Cria) -- o app so pedia raca (nao sexo,
porque o lote e' fixo em macho) e, por baixo, animalCadastrado()/
upsertAnimal() tratavam "numero" como unico na fazenda inteira: achavam a
femea existente e SOBRESCREVIAM o sexo/lote dela pra macho, em vez de
criar um animal novo. Corrigido: a identidade do animal passa a ser o par
numero+sexo.
"""
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path("/home/claude/AEagropecuaria")
STUB = Path("/tmp/lav_test/stub.js").read_text()

DB = {
    "fazendas": [{"id": 1, "nome": "Faz Teste"}],
    "lotes": [
        {"id": 1, "nome": "Curral Macho", "destino": "confinamento", "sexo": "macho",
         "numero_animais": 10, "data_fim": None, "dieta_id": None},
        {"id": 2, "nome": "Cria Femeas", "destino": "cria", "sexo": "femea",
         "numero_animais": 5, "data_fim": None, "dieta_id": None},
    ],
    # animal 777 ja existe como femea, cadastrado no lote de Cria
    "animais": [{"id": 900, "numero": "777", "lote_id": 2, "sexo": "femea", "raca": "nelore", "criado_por": "x"}],
    "dietas": [], "ingredientes": [], "movimentos_estoque": [], "producoes_racao": [],
    "saidas_racao": [], "leituras_cocho": [], "pastos": [],
    "manejos": [], "abates": [], "reproducao_custos": [], "diagnosticos_gestacionais": [],
    "partos": [], "desmamas": [], "custos_fixos": [], "precos_arroba": [],
    "titulos": [], "alertas": [], "pesagens": [], "pesagens_animais": [],
    "protocolos_inseminacao": [],
}
ADMIN = {"id": "u1", "nome": "Eduardo", "usuario": "eduardo", "papel": "admin",
         "permissoes": {}, "ativo": True}

passes = falhas = 0
def conf(ok, nome, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {nome}")
    else:  falhas += 1; print(f"    FALHOU  {nome}" + (f"\n            {extra}" if extra else ""))

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    erros = []
    page.on("pageerror", lambda e: erros.append(str(e)))
    page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
    page.add_init_script(STUB)
    page.add_init_script(
        f"window.__DB__ = {json.dumps(dict(DB, profiles=[ADMIN]))};"
        f"window.__SESSAO__ = {{user:{{id:'u1'}}, access_token:'x'}};")
    page.goto("file://" + str(REPO / "AEpecuaria.html"))
    page.wait_for_timeout(1000)

    print("\n  NUMERO REPETIDO ENTRE SEXOS -- nao pode fundir animais")

    ruido = ("ServiceWorker", "ERR_TUNNEL", "ERR_NAME_NOT_RESOLVED", "Failed to load resource")
    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "abre sem erro de JavaScript", " | ".join(erros[:3]))

    # animalCadastrado agora exige o sexo bater
    r = page.evaluate("() => !!animalCadastrado('777', 'macho')")
    conf(r is False, "numero 777 NAO 'ja cadastrado' quando busca por macho (so existe como femea)")

    r = page.evaluate("() => !!animalCadastrado('777', 'femea')")
    conf(r is True, "numero 777 'ja cadastrado' quando busca por femea (bate)")

    r = page.evaluate("() => !!animalCadastrado('777')")
    conf(r is True, "sem sexo informado, acha o 777 (uso so informativo)")

    # upsertAnimal: pesar o 777 como macho tem que CRIAR um animal novo,
    # nao sobrescrever a femea existente
    res = page.evaluate("""async () => {
      const antes = state.animais.find(a=>a.numero==='777' && a.sexo==='femea');
      const r = await upsertAnimal('777', 1, {sexo:'macho', raca:'angus'});
      // callsites reais atualizam o cache local depois de criar (ver
      // salvarAnimalManejo) -- sem isso o proximo upsertAnimal nao veria
      // esse cadastro novo, so window.__DB__ (que o stub grava direto).
      if(!r.error && r.data) state.animais.push({id:r.data.id, numero:'777', loteId:1, sexo:'macho', raca:'angus', criadoPor:''});
      return {error: r.error ? r.error.message : null, id: r.data ? r.data.id : null, antesId: antes ? antes.id : null};
    }""")
    conf(res["error"] is None, "upsertAnimal(777, macho) nao deu erro", res.get("error") or "")
    conf(res["id"] is not None and res["id"] != res["antesId"],
         "criou um ANIMAL NOVO (id diferente da femea 900), nao atualizou o existente",
         f"novo id={res['id']} femea id={res['antesId']}")

    # a femea original continua intacta (sexo/lote nao mudaram)
    femea = page.evaluate("() => { const a = window.__DB__.animais.find(x=>x.id===900); return a ? {sexo:a.sexo, lote_id:a.lote_id} : null; }")
    conf(femea is not None and femea["sexo"] == "femea" and femea["lote_id"] == 2,
         "a femea original (id 900) continua femea, no lote de Cria -- NAO foi sobrescrita",
         json.dumps(femea))

    # e agora existem os dois: 777 macho E 777 femea, cadastros separados
    total777 = page.evaluate("() => window.__DB__.animais.filter(a=>a.numero==='777').length")
    conf(total777 == 2, "existem 2 animais com numero 777 agora (macho e femea), nao 1 fundido", f"total={total777}")

    # upsertAnimal sem sexo, quando o numero so existe UM (ja resolvido antes
    # do teste acima criar o segundo) -- usa outro numero pra esse caso
    res2 = page.evaluate("""async () => {
      const r = await upsertAnimal('888', 3, {sexo:'macho', raca:'nelore'});
      return {error: r.error ? r.error.message : null};
    }""")
    conf(res2["error"] is None, "upsertAnimal com numero novo (888) e sexo informado funciona normal")

    # upsertAnimal SEM sexo, quando o numero (777) ja tem DOIS cadastros
    # (macho e femea) -- tem que bloquear em vez de escolher um dos dois
    # as cegas
    res3 = page.evaluate("""async () => {
      const r = await upsertAnimal('777', 1, {raca:'angus'});
      return {error: r.error ? r.error.message : null};
    }""")
    conf(res3["error"] is not None, "upsertAnimal(777) SEM sexo bloqueia com erro (nao escolhe as cegas entre macho/femea)", str(res3))

    # validarAnimalNovo tambem respeita o sexo
    r = page.evaluate("() => validarAnimalNovo('777', 'macho', 'brahman')")
    conf(r is None, "validarAnimalNovo(777, macho) passa (777-macho ja existe, upsert so atualiza)")

    r = page.evaluate("() => validarAnimalNovo('999', 'macho', '')")
    conf(r is not None and 'raça' in r, "validarAnimalNovo(999 novo, sem raca) cobra raca", str(r))

    conf(not [e for e in erros if not any(r in e for r in ruido)],
         "sem erro de JavaScript no fluxo todo", " | ".join(erros[:3]))

    print(f"\n  {passes} passaram, {falhas} falharam")
    browser.close()
