"""
Roda os testes do repositorio (teste_*.py): e o que o GitHub Actions executa a cada envio (.github/workflows/testes.yml).

  python roda_testes.py                       roda todos
  python roda_testes.py --parte 2 --de 4      roda so a 2a de 4 partes (o CI divide em partes para terminar mais cedo)
  python roda_testes.py teste_csp.py ...      roda so os arquivos citados
  python roda_testes.py --workers 3           quantos testes ao mesmo tempo (padrao 3)

Cada arquivo e um processo: os escritos como script (print de "ok"/"FALHOU" e exit code) rodam com `python`, os escritos
para o pytest (def test_...) rodam com `pytest`. Falhou = exit code diferente de 0. Para cada teste que falha, o fim da saida
vai para o log e para uma anotacao do GitHub (visivel na pagina da rodada e pela API, mesmo sem abrir o log).

Os testes esperam o ambiente do sandbox em que foram escritos (o CI o monta: /home/claude/AEagropecuaria aponta para o
repositorio, /tmp/lav_test/stub.js e o stub do Supabase e /opt/pw-browsers/chromium e o navegador do Playwright).
"""
import argparse
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent
LIMITE_S = 900   # um teste que passa disso e considerado travado


def estilo_pytest(arquivo):
    return bool(re.search(r"^def test_", arquivo.read_text(encoding="utf-8"), re.M))


def roda_um(arquivo):
    if estilo_pytest(arquivo):
        cmd = [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "--tb=short", arquivo.name]
    else:
        cmd = [sys.executable, "-X", "utf8", arquivo.name]
    inicio = time.time()
    try:
        p = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=LIMITE_S)
        rc, saida = p.returncode, (p.stdout or "") + "\n" + (p.stderr or "")
    except subprocess.TimeoutExpired:
        rc, saida = 124, f"TRAVOU: passou de {LIMITE_S} s sem terminar"
    return arquivo.name, rc, round(time.time() - inicio), saida


def anotacao_github(titulo, texto):
    """Mostra o erro na pagina da rodada do GitHub (e na API de anotacoes)."""
    texto = texto.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    titulo = titulo.replace("%", "%25").replace(",", "%2C").replace(":", "%3A")
    print(f"::error title={titulo}::{texto}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("arquivos", nargs="*")
    ap.add_argument("--parte", type=int, default=1)
    ap.add_argument("--de", type=int, default=1)
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()

    todos = sorted(REPO.glob("teste_*.py"))
    if args.arquivos:
        nomes = {Path(a).name for a in args.arquivos}
        escolhidos = [f for f in todos if f.name in nomes]
        faltam = nomes - {f.name for f in escolhidos}
        if faltam:
            print("nao achei:", ", ".join(sorted(faltam)))
            return 2
    else:
        escolhidos = [f for i, f in enumerate(todos) if i % args.de == args.parte - 1]
    print(f"{len(escolhidos)} testes (parte {args.parte} de {args.de}), {args.workers} ao mesmo tempo\n", flush=True)

    inicio = time.time()
    resultados = []
    with ThreadPoolExecutor(args.workers) as ex:
        for nome, rc, seg, saida in ex.map(roda_um, escolhidos):
            resultados.append((nome, rc, seg, saida))
            print(f"{'OK    ' if rc == 0 else 'FALHOU'} {seg:4d}s  {nome}", flush=True)
            if rc != 0:
                fim = "\n".join(saida.strip().splitlines()[-40:])
                print("::group::saida de " + nome + " (ultimas 40 linhas)")
                print(fim)
                print("::endgroup::", flush=True)
                anotacao_github(f"Teste falhou: {nome}", fim[-6000:])

    falhas = [r for r in resultados if r[1] != 0]
    total_s = round(time.time() - inicio)
    print(f"\n{len(resultados) - len(falhas)} de {len(resultados)} testes passaram em {total_s} s")
    resumo = os.environ.get("GITHUB_STEP_SUMMARY")
    if resumo:
        with open(resumo, "a", encoding="utf-8") as fh:
            fh.write(f"### Parte {args.parte} de {args.de}: {len(resultados) - len(falhas)} de {len(resultados)} testes passaram ({total_s} s)\n\n")
            for nome, rc, seg, _ in resultados:
                fh.write(f"- {'OK' if rc == 0 else '**FALHOU**'} `{nome}` ({seg} s)\n")
    if falhas:
        print("FALHARAM: " + ", ".join(r[0] for r in falhas))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
