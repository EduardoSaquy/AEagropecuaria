"""
Mantem o <script src="core.js?v=..."> dos apps em dia com o arquivo (o ?v= e a impressao digital do conteudo).

POR QUE O ?v=
  core.js e core_lavoura.js sao arquivos separados do HTML. Sem o ?v=, o navegador pode entregar um core.js velho
  (cache do GitHub Pages, ate 10 min) junto com um HTML novo, e o app quebra ate o cache vencer. Com o ?v= o endereco
  muda sempre que o arquivo muda, entao HTML novo e nucleo novo andam juntos.

QUANDO RODAR
  Depois de mexer em core.js ou core_lavoura.js:   python atualiza_nucleo.py
  So conferir (o teste_nucleo.py faz isso):         python atualiza_nucleo.py --confere

Quais apps carregam qual nucleo esta em NUCLEOS (e a unica lista: o teste usa a mesma). A ordem dos arquivos aqui e a
ordem das tags no HTML: core.js primeiro.
"""
import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
NUCLEOS = {
    "core.js": ["AEMatriz.html", "AEpecuaria.html", "AECana.html", "AECereais.html", "AECombustivel.html"],
    "core_lavoura.js": ["AECana.html", "AECereais.html"],
}
SUPABASE_TAG = '<script src="vendor/supabase-js-2.118.0.js"></script>'
TAG_NUCLEO = re.compile(r'<script src="(core[a-z_]*\.js)(?:\?v=[0-9a-f]+)?"></script>\r?\n')


def impressao(arquivo):
    """10 primeiros caracteres do SHA-256 do arquivo; fim de linha CRLF/LF nao muda o resultado (Windows x GitHub)."""
    dados = (REPO / arquivo).read_bytes().replace(b"\r\n", b"\n")
    return hashlib.sha256(dados).hexdigest()[:10]


def tags_do_app(app):
    return [f'<script src="{arq}?v={impressao(arq)}"></script>' for arq, apps in NUCLEOS.items() if app in apps]


def ajusta(html, app):
    """O HTML com as tags dos nucleos certas e no lugar certo (logo depois da biblioteca do Supabase)."""
    eol = "\r\n" if "\r\n" in html else "\n"
    html = TAG_NUCLEO.sub("", html)
    if html.count(SUPABASE_TAG) != 1:
        raise SystemExit(f"{app}: esperava exatamente uma tag da biblioteca do Supabase, achei {html.count(SUPABASE_TAG)}")
    novas = "".join(t + eol for t in tags_do_app(app))
    return html.replace(SUPABASE_TAG + eol, SUPABASE_TAG + eol + novas, 1)


def confere():
    """Lista de problemas (vazia = tudo em dia)."""
    problemas = []
    for arq in NUCLEOS:
        if not (REPO / arq).exists():
            problemas.append(f"{arq} nao existe")
    if problemas:
        return problemas
    apps = sorted({a for lista in NUCLEOS.values() for a in lista})
    for app in apps:
        html = (REPO / app).read_bytes().decode("utf-8")
        if ajusta(html, app) != html:
            problemas.append(f"{app}: as tags dos nucleos estao desatualizadas (rode: python atualiza_nucleo.py)")
    return problemas


def main():
    if "--confere" in sys.argv:
        problemas = confere()
        for p in problemas:
            print(p)
        return 1 if problemas else 0
    apps = sorted({a for lista in NUCLEOS.values() for a in lista})
    for app in apps:
        caminho = REPO / app
        html = caminho.read_bytes().decode("utf-8")
        novo = ajusta(html, app)
        if novo != html:
            caminho.write_bytes(novo.encode("utf-8"))
            usadas = ", ".join(re.findall(r"core[a-z_]*\.js\?v=[0-9a-f]+", novo))
            print(f"{app}: atualizado -> {usadas}")
        else:
            print(f"{app}: ja estava em dia")
    return 0


if __name__ == "__main__":
    sys.exit(main())
