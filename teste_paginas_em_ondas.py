"""
fetchAllRows (core.js) le as paginas em ONDAS de 4 em paralelo depois da 1a (13/11/2026); antes era uma pagina depois da outra.
Confere com uma consulta falsa que demora 100 ms por pagina: todas as linhas, na ordem, sem repetir nem faltar, em 0, 1 pagina
exata, pagina+1, varias ondas; tabela pequena continua com uma ida so; erro numa pagina devolve o que veio antes e o erro;
e o tempo cai (8.500 linhas: 9 idas em fila viram 1 + 2 ondas). Falha no codigo anterior (tempo e numero de idas em paralelo).
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
STUB = (REPO / "teste_stub_supabase.js").read_text()
passes = falhas = 0
def conf(ok, desc, extra=""):
    global passes, falhas
    if ok: passes += 1; print(f"    ok      {desc}")
    else:  falhas += 1; print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))

JS = """async ([n, atraso, erroNaPagina]) => {
  const linhas = Array.from({length:n}, (_, i) => ({id: i+1}));
  let emAndamento = 0, maxParalelo = 0, idas = 0;
  const consulta = () => ({ range: (a, b) => { idas++; emAndamento++; maxParalelo = Math.max(maxParalelo, emAndamento);
    return new Promise(r => setTimeout(() => { emAndamento--;
      if (erroNaPagina !== null && a === erroNaPagina*1000) r({data:null, error:{message:'falhou'}});
      else r({data: linhas.slice(a, b+1), error:null}); }, atraso)); } });
  const t0 = performance.now();
  const res = await fetchAllRows(consulta);
  const ids = (res.data||[]).map(x=>x.id);
  return {n: ids.length, emOrdem: ids.every((v,i)=>v===i+1), unicos: new Set(ids).size, erro: res.error ? res.error.message : null,
          ms: performance.now()-t0, idas, maxParalelo};
}"""

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    page.add_init_script(STUB)
    page.add_init_script("window.__DB__ = {profiles:[]}; window.__SESSAO__ = null;")
    page.goto((REPO / "AEMatriz.html").as_uri()); page.wait_for_function("() => typeof fetchAllRows === 'function'")
    print("\n  LEITURA EM PAGINAS (fetchAllRows)")
    for n in (0, 1, 999, 1000, 1001, 4000, 5000, 5001, 8500, 27823):
        r = page.evaluate(JS, [n, 5, None])
        conf(r["n"] == n and r["emOrdem"] and r["unicos"] == n and r["erro"] is None,
             f"{n} linhas: todas, na ordem, sem repetir", str(r))
    r = page.evaluate(JS, [300, 100, None])
    conf(r["idas"] == 1, "tabela pequena (300 linhas): uma ida so", str(r))
    r = page.evaluate(JS, [8500, 100, None])
    conf(r["maxParalelo"] == 4, "8.500 linhas: ate 4 paginas ao mesmo tempo", str(r))
    conf(r["ms"] < 450, f"8.500 linhas com 100 ms por ida: {r['ms']:.0f} ms (em fila seriam ~900 ms)", str(r))
    r = page.evaluate(JS, [5500, 5, 3])
    conf(r["erro"] == "falhou" and r["n"] == 3000 and r["emOrdem"], "erro na 4a pagina: devolve as 3 primeiras, na ordem, e o erro", str(r))
    r = page.evaluate(JS, [5500, 5, 0])
    conf(r["erro"] == "falhou" and r["n"] == 0, "erro na 1a pagina: nada e o erro", str(r))
    browser.close()

print(f"\n  {passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
