"""
Nucleo comum dos apps (core.js e core_lavoura.js, 07/11/2026): o que era copiado de app para app mora num arquivo so.

Prova:
  - cada app que usa um nucleo carrega o arquivo certo, na ordem certa (depois do Supabase, antes do script do app) e com
    o ?v= igual a impressao digital do arquivo (sem isso o navegador pode juntar HTML novo com nucleo velho do cache);
  - nenhum app declara de novo uma funcao ou constante que o nucleo ja declara (o app venceria e a copia voltaria a divergir);
  - TRAVA CONTRA A VOLTA DA COPIA: nenhuma funcao de nivel superior aparece com o mesmo texto em dois apps, fora a lista
    DIVIDA_CONHECIDA (as que ainda tem versoes diferentes entre os apps e esperam ser reconciliadas). Copia nova falha o
    teste e diz qual: ela deve ir para o nucleo (ver CLAUDE.md, "Nucleo comum");
  - o service worker guarda os nucleos e o CSS comum (senao o app nao abre offline);
  - core.css (5 apps) e core_grade.css (Pecuaria, Cana, Cereais) vem depois do <style> do app e o bloco nao volta a ser copiado;
  - os nucleos sao carregados pelos apps de verdade: a pagina de cada app enxerga as funcoes do nucleo.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
sys.path.insert(0, str(REPO))
import atualiza_nucleo as nuc  # noqa: E402
APPS = ["AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"]

passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


def blocos_inline(html):
    return [m.group(1) for m in re.finditer(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.S)]


def sem_comentarios(txt):
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
    return re.sub(r"(^|\s)//[^\n]*", r"\1", txt)


def funcoes_de_nivel_superior(js):
    """{nome: texto} das 'function nome(' que comecam na coluna 0 (e como os apps sao escritos)."""
    linhas = js.replace("\r\n", "\n").split("\n")
    achadas, i = {}, 0
    while i < len(linhas):
        m = re.match(r"(?:async\s+)?function\s*\*?\s*(\w+)\s*\(", linhas[i])
        if not m:
            i += 1
            continue
        fim = i
        if not re.search(r"\}\s*;?\s*(//.*)?$", linhas[i]):
            fim = i + 1
            while fim < len(linhas) and linhas[fim].rstrip() != "}":
                fim += 1
        achadas[m.group(1)] = "\n".join(linhas[i:fim + 1])
        i = fim + 1
    return achadas


def valores_de_nivel_superior(js):
    return set(re.findall(r"^(?:const|let|var)\s+(\w+)", js.replace("\r\n", "\n"), re.M))


def norm(txt):
    return re.sub(r"\s+", "", sem_comentarios(txt))


print("== tags e impressao digital")
problemas = nuc.confere()
conf(not problemas, "as tags <script src=core*.js?v=...> dos apps estao em dia com os arquivos", "; ".join(problemas))
for app in APPS:
    html = (REPO / app).read_text(encoding="utf-8")
    esperados = [a for a, apps in nuc.NUCLEOS.items() if app in apps]
    srcs = re.findall(r'<script src="([^"]+)"></script>', html)
    ordem = [s.split("?")[0] for s in srcs if s.split("?")[0].startswith("core")]
    conf(ordem == esperados, f"{app}: carrega {esperados} nessa ordem", f"achei {ordem}")
    pos_supabase = html.find('src="vendor/supabase-js-')
    pos_core = html.find('<script src="core.js')
    primeiro_inline = min((m.start() for m in re.finditer(r"<script(?![^>]*\bsrc=)[^>]*>", html)), default=-1)
    conf(0 < pos_supabase < pos_core < primeiro_inline, f"{app}: core.js vem depois do Supabase e antes do script do app")

print("== o app nao declara de novo o que o nucleo declara")
for arq in nuc.NUCLEOS:
    js = (REPO / arq).read_text(encoding="utf-8")
    fn_nucleo = set(funcoes_de_nivel_superior(js)) | valores_de_nivel_superior(js)
    conf(len(fn_nucleo) > 5, f"{arq}: tem declaracoes ({len(fn_nucleo)})")
    for app in nuc.NUCLEOS[arq]:
        html = (REPO / app).read_text(encoding="utf-8")
        no_app = set()
        for bloco in blocos_inline(html):
            no_app |= set(funcoes_de_nivel_superior(bloco)) | valores_de_nivel_superior(bloco)
        repetidas = sorted(fn_nucleo & no_app)
        conf(not repetidas, f"{app}: nao repete nada de {arq}", f"repetidas: {repetidas}")

print("== nenhuma funcao copiada entre apps")
por_nome = {}
for app in APPS:
    html = (REPO / app).read_text(encoding="utf-8")
    for bloco in blocos_inline(html):
        for nome, txt in funcoes_de_nivel_superior(bloco).items():
            por_nome.setdefault(nome, []).append((app, norm(txt)))
copiadas = set()   # (nome, apps que tem o mesmo texto)
for nome, lst in por_nome.items():
    grupos = {}
    for app, t in lst:
        grupos.setdefault(t, []).append(app)
    for t, apps in grupos.items():
        if len(apps) > 1:
            copiadas.add((nome, tuple(apps)))
# Copias que ainda existem porque os apps tem versoes DIFERENTES da mesma funcao (o nucleo so recebe o que e igual em todos
# os apps que o carregam). Cada uma tem que ser reconciliada de vez: decidir o comportamento certo, passar para o nucleo e
# tirar da lista. A lista so pode encolher: copia nova que nao esteja aqui falha o teste; item daqui que sumiu tambem falha
# (para a lista nunca ficar mentindo).
DIVIDA_CONHECIDA = set()


def mostra(conj):
    return "; ".join(f"{n} em {', '.join(a.replace('.html', '') for a in apps)}" for n, apps in sorted(conj))


novas = copiadas - DIVIDA_CONHECIDA
conf(not novas, "nenhuma funcao NOVA copiada entre apps (so as da lista de divida conhecida)", mostra(novas) + "  -> mover para core.js")
sumiram = DIVIDA_CONHECIDA - copiadas
conf(not sumiram, "a lista de divida conhecida nao tem item que ja foi resolvido", mostra(sumiram) + "  -> tirar da DIVIDA_CONHECIDA")

print("== service worker")
sw = (REPO / "sw.js").read_text(encoding="utf-8")
for arq in list(nuc.NUCLEOS) + list(nuc.NUCLEOS_CSS):
    conf(f"'./{arq}'" in sw, f"sw.js guarda ./{arq} para abrir offline")

print("== CSS comum (core.css, core_grade.css)")
for app in APPS:
    html = (REPO / app).read_text(encoding="utf-8")
    esperados = [a for a, apps in nuc.NUCLEOS_CSS.items() if app in apps]
    hrefs = [h.split("?")[0] for h in re.findall(r'<link rel="stylesheet" href="(core[^"]+)">', html)]
    conf(hrefs == esperados, f"{app}: carrega {esperados} nessa ordem", f"achei {hrefs}")
    pos_style = html.find("</style>")
    pos_link = html.find('<link rel="stylesheet" href="core.css')
    conf(0 < pos_style < pos_link, f"{app}: o CSS comum vem depois do <style> do app (vale por cima)")
    estilo = "".join(re.findall(r"<style>(.*?)</style>", html, re.S))
    for arq in esperados:
        for cab in re.findall(r"/\* -{6,} ([^\n(]{6,40})", (REPO / arq).read_text(encoding="utf-8")):
            conf(cab not in estilo, f"{app}: nao copia de novo o bloco '{cab.strip()}' de {arq}")

print("== os apps enxergam o nucleo")
from playwright.sync_api import sync_playwright

STUB = (REPO / "teste_stub_supabase.js").read_text()
USADAS = {"core.js": ["avisar", "sessaoInicial", "lerPerfilCache", "ModalTrocarSenha", "hojeStr", "iconAdmin"],
          "core_lavoura.js": ["PageEstoqueInsumos", "saldoInsumo", "iconGrao"]}
with sync_playwright() as pw:
    b = pw.chromium.launch()
    for app in APPS:
        page = b.new_page()
        page.on("dialog", lambda d: d.dismiss())
        page.route("**/cdn.jsdelivr.net/**", lambda r: r.fulfill(status=200, body=""))
        page.route("**/fonts.g*apis.com/**", lambda r: r.fulfill(status=200, body=""))
        page.add_init_script(STUB)
        page.goto((REPO / app).as_uri())
        page.wait_for_timeout(800)
        for arq, nomes in USADAS.items():
            if app not in nuc.NUCLEOS[arq]:
                faltando_certo = page.evaluate("(ns) => ns.every(n => typeof window[n] !== 'function')", nomes)
                conf(faltando_certo, f"{app}: NAO carrega {arq} (e nao tem as funcoes dele)")
                continue
            tipos = page.evaluate("(ns) => Object.fromEntries(ns.map(n => [n, typeof window[n]]))", nomes)
            conf(all(t == "function" for t in tipos.values()), f"{app}: as funcoes de {arq} existem na pagina", str(tipos))
        page.close()
    b.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
