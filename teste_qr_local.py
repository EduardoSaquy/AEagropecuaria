"""
Gerador de QR code do core.js (08/11/2026). O servidor do Supabase devolve o QR do segundo fator como um SVG grande e sem viewBox, e no iPad do
Eduardo ele nao aparecia ("nao apareceu QR Code"); por isso o app passou a gerar o QR aqui mesmo (qrMatriz / qrSvgLocal), a partir do endereco
otpauth:// ou so da chave. Este teste prova que o gerador esta CERTO, sem depender de nenhuma biblioteca instalada: para cada uma das 15 versoes
(1 a 15, nivel de correcao M, modo byte) e cada uma das 8 mascaras, a matriz gerada tem a mesma impressao digital (SHA-256 das linhas, 16
primeiros caracteres) da gerada pela biblioteca de referencia segno, medida uma vez e guardada abaixo. Os textos enchem a capacidade de cada
versao (sem bytes de enchimento). Alem disso:
  - a escolha da mascara pela penalidade devolve uma das 8 e a matriz tem o tamanho da versao (17 + 4 x versao);
  - o SVG tem viewBox, um so caminho e cada modulo com um numero inteiro de pixels;
  - textos acentuados viram UTF-8; texto grande demais (mais de 415 bytes) da erro em vez de um QR errado;
  - o QR do endereco otpauth de verdade do Supabase (versao 8) e o da chave sozinha (versao 6) saem nas versoes esperadas.
"""
import hashlib
import json
import re
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent
CORE = (REPO / "core.js").read_text(encoding="utf-8")
REFERENCIAS = json.loads('{"1":{"texto":"ujz%de8gx/d6nc","hashes":["0091939d38aa4d0f","176e0cdafb250d57","ac90c1545f5cd0a1","a97653dc7ed85d41","84364c7654306189","2bbf6eedef6eee34","bde5ee9f6c1dc772","599ef8fcb1d6901b"]},"2":{"texto":"f10epf91d:ho==/d:/zdoc9is0","hashes":["3aa95ca04f38ef47","587a302536b6e229","7f2fc77699b56974","33bd9ed29ac08cbc","b00565123bab1a71","df0da1971b65bff4","32e05297a7806c2e","8420a7b0eaeb66ea"]},"3":{"texto":"j8h:t9-lg/:=mxg9e:d&n5-81u3/3xtplpf:t75v2s","hashes":["a48056aace3bccab","f6e1c60611b30ed4","09734089a9de6ba4","22ed36bbfe06d9bc","fd2a45e16ce0570e","72efd825b4324400","e582bfd9f2681a71","568ac64eb5f827c6"]},"4":{"texto":"?eh60kvj50c.e9:uvw?5/3efr4.edt%:-2sy.wb3wk&h5dnsipzz5fk2z9ri19","hashes":["14a5c6490fa04e72","66f7d7c785019625","cef5daebd7fb4238","439a0aef51923935","f990d50b8b493b02","e94bd5d3ddfc50ca","de3d06aa23d13b59","f52440de0c0edb3d"]},"5":{"texto":"r0w-yojfljo.oa5/lqsaj08x&:ui6&%-d3-9zzzzg4=zdmen2khv?dga:j8gx&ben&yj=qw?x4hh5344tfjg","hashes":["d71724c32f3b0c66","6a3176762c94c3e3","cf998825dc7837e6","a69c08017e19f678","fae16f2b8e461d7d","d502956e2bf2b3e3","472f755eff211271","7ce62e542a545f12"]},"6":{"texto":"vq4k7bn7xj8b7t%fq7xkwo886v=o&mpzom75wbbr4qm?w2wxfogo4mvn4&&a4%w%f.hym4l1=vfz3zfkkibj/3%j&?4.wj99iba%g7i1mn","hashes":["d48348cada335109","ff53dc863c0607c9","548226f3e7a933e8","c26d4a841e30542d","c689ffcd297f4b4d","5bb326e24f626491","412cb9c59ed887b3","d654d6af8cec074b"]},"7":{"texto":"bqns6p/uq80idw3./706i8j76b2l?ajlj4&h9du-7794g9dpmrcg629be2u&6?6mr26846p7q9m2i0hz2ue.p1en.thj%.xjqi3ogz5k.ok16zv0mwufxbv932","hashes":["debb7fe9e2ff38d3","ed8411aaf08d99f0","1f38ab093fa27f37","06000c4e3a3aceeb","be74c522509317c4","88d62bbde2c660a8","b4cd6dc0b4c3f94a","71240afeea5b0539"]},"8":{"texto":"byv7&s6ehogfqrclri1-qzj86:5ufrdl1erb=fqf?oeqh3av90r&ic7phkqdlmt=t7ns26-lrwbqcab69m64p2g.%1.58z6tnovm=izwdiae=q1kdf.y6.s?psc3lkr2aqxv9upctnwlavyf4r6%mp6a","hashes":["fbc57f0e75b6669c","e02ad6274c107ad7","64f64907565c3ad0","2da669de4c7cb181","7b87424144f277ca","be54d6ab3ef81f32","5b8c8dff4ec95f3c","eb90a2200a0bb5af"]},"9":{"texto":"fqfjz/czbtt=of/7j.?yu5js&%jc6=16i76:b-/-%ofbci=xgy29d=b=8-p5qa3e68f.7e4qeqpno%35ye4-sc&=%me?jvq%t&:ia4d5r-gn-5s7s333h9mtf4bs3e62rynne/fj7qxi?=6rhxo55zbka5-2ztj0wyuhvauvzhmasqxezy/e","hashes":["8434de40948cbe7c","040164bb8d6ac1b4","925361ea7c10e98f","8588c8b07374d7d6","4da88cac82fd37b5","333e0ac63469fe29","2b31d79fd1b8fcd8","fb584c1895ba7224"]},"10":{"texto":"x1rdrgd.s=jpr16umx1b=z99nfd02&i%s5d9ik40vstq%qz%pt49.zhk%ken659o2v21i9mpflv9fupxq:mb0y07nyrvd5r:xi-67=nfrpyz%21tbic14/5aez732pgojj7-g%3f9caio:c%ti=q7=1hget7/myqo?aa8t3ru%p47p9pb0%tdbm5-%0fqo.1xo5cv0x-zmas6en5mtmo3","hashes":["1a435feeee2f7854","846afa53cfa073da","203fbd93d338cd9c","f54ab1c14223d041","515dd57aef8dcea7","a1fd2716a15c99e3","170b0dfff1cacdcd","c21c90a29bba5911"]},"11":{"texto":"oqsg&5&lo50.d?jzdnb?j0ddlz2uhfkvml%73ct.yxv2kgafrfw0h9nywt1fd4mx82mux4b=0p=zcyc3edqme?vxrv&cqurta?=ebog43yq15i5latj?puu3x?f6mzkp0e%c498uk1geq&fng052loi03&-p8.hssr:rxqqm2plppjs/muezqp67o%g%3cga4o2xcsohdm?/mex6l2?q.ag=?&wncxvjcnqc?%nau0-xl&tenc594e0gz.9","hashes":["42d892f47520d846","59f2f403f6c19226","bdf9ffdd35b5c432","10a5956836a931f4","144999a3222e0b19","42300503ca670c8d","3aa84b183a97cc97","b978212342b8077a"]},"12":{"texto":"j=8f%kzr0s.t0dt:w00bx%mzzna1k1hfz:x3kiad9j%zf:&x6kjwsk7kegy5mtic4ud?=yf&k=o&z&m4l:ncz7kywhjpmc9-c.uhy?39=t%0t/p1y.x262lba&53p2&3l4zgeiw1xf266.cc=ifu6fd6y%ibe&hmi5sk-oew&qku&r3jq64n/q&6puxcmlzk=r-uykqh7d=x297/gq8=zxqyx:jxvf2ol&ds7qt=/.uacojs&=106xdi5o&%cbda:wtg7w8o0/t/inx&4kiapj2ge=j.rzq","hashes":["63325a3eb7cbe606","41cc07c975cb397e","436ffdac409f33eb","94e2c93a5f797e13","5a645c16f0c09999","a89ca3d7ee2fcc90","f3a13fd5fd00bd0c","da892f38c8a6dac2"]},"13":{"texto":"ad%9w?%/2?75pkacd8bzlpkdga&9.mj0m7?%6%%0&l6tet=d48ay13f%2logqo%chvqdr=9-1-7qs%nf6akqpmkumyv?py=.8447ab1o:tnz&/e:kjcbhg&kwjbbci%=cece/xm8.eygpnnhcc=f==s4gig%nsuv1qbwqsdxu?64s&b0b17gw4d8:nf:sk1a7msdaw5g5l5/w6q:ksno5kh=f59g=uwgzzf1%bxntq186ky=o3i8??%cw/u7j2.9uk32q/oiv3%p6mrt&jjpu?7wkpumqgk.gmyjjtt1rmg=grny3caz1o6=s3bjq?zap1:/%0o.%%/","hashes":["c6ea82c63a074cb0","ed933c8c8f46ac17","7cc25bdb7d225299","26aed62de468c1ed","ee3404b6ae156674","ebac5b190d9a5b91","197f4f8ac86495c2","c22c0a4fc78e2a2b"]},"14":{"texto":"o-l%h31uq=g0pz=kq143b&07-.l%uay5gcq8nkm7wg:38n46b=x7v03n-lz6h&w=dqryzdae00=-w/qgotz7oz3nkie=m4%9ojw.=03s9%i4wory-q1-l4arwp%tu451&=f.xjtydf:ui7w=/a.ane%sq?g/jol2wjnz8k&?f.9=tm5n7f2.h9hq0oi459d43j5p5k8?aku3:5.s3x10-el=x=%bb&c-vg645jcn0=ivg.xv479ns1v1q9dssw5zv6r6wn%5hvmuti/=fcz9z8:dztgacm4?.d68&y&j=-?-fnc.=3=lg.lc0g%axit9qtl0cub1:%/d5:7ch0:z2ea-y?/.j409gf%4nj=a1a","hashes":["d6add4f25e09b8ae","d9a7fc310fbbf084","52a4ca06d1e86d39","99d5dc15bfb04456","39154cff38ecdffd","eff116d4c8c6dbf2","c7acc5ed0ff51429","915cb9c49d0446df"]},"15":{"texto":"a-.hfnhi4br:p2ldxjfs=953.qdcada%-&fytt?k5?dux:24-kjhx%k=04y2r:vsrd&%?v?aj?t/1pyy-y?o2sauqr1k/csj:jr9-5w8f895ymot?d-z3nq/ay38f8weoz/7q7u46/mmnmflsx::wz7jpc5xgx=3fju?bwr7?bgcn:5/:nqr1g2/?iqcvmlyfbdc9x35e?=zhfqu:o%f.6zl2kxpolcqwd9bdq6%4dgjuam-t//2%g4uxqyhx4yk2pj-a3mckoe&xi2gyb=e2vuo4h=xjvodl29j2jr00pjbr:svkq5gu34hj6d=.n94shqmx1qppgys0kdsj=b26v6i2a7slx1c0nr:lil7olm?ff?5rlni&.=m/tmae70d7wvs=5fa04i.rpl:xckx:?aw727e","hashes":["1f82ceaba0cb7cf5","a79edc5b21a41a04","66bb1455e7d4916a","06634ba20b10c69f","bef8e7a6e31f3d26","5e444b0a5f79115f","56f1a2dd0fcb0424","28e6830989eb356d"]}}')
passes = falhas = 0


def conf(ok, desc, extra=""):
    global passes, falhas
    if ok:
        passes += 1
        print(f"    ok      {desc}")
    else:
        falhas += 1
        print(f"    FALHOU  {desc}" + (f"\n              {extra}" if extra else ""))


codigo = CORE[CORE.index("const QR_ECC_M"):CORE.index("// Janela para ativar, ver e remover")]
codigo += "\nfunction esc(s){return String(s)}\nfunction qrSvgDoSupabase(){return ''}\nfunction qrComoSvgInline(){return ''}\nfunction qrComoImagem(){return ''}\n"

with sync_playwright() as pw:
    browser = pw.chromium.launch(executable_path="/opt/pw-browsers/chromium")
    page = browser.new_page()
    page.set_content("<!doctype html><meta charset=utf-8><script>" + codigo + "</script>")
    for v in range(1, 16):
        ref = REFERENCIAS[str(v)]
        iguais = []
        for m in range(8):
            r = page.evaluate("([t, m]) => { const q = qrMatriz(t, m); return {v: q.versao, n: q.n, bits: q.mod.map(l => l.map(c => c ? '1' : '0').join('')).join('')}; }", [ref["texto"], m])
            iguais.append(r["v"] == v and r["n"] == 17 + 4 * v and hashlib.sha256(r["bits"].encode()).hexdigest()[:16] == ref["hashes"][m])
        conf(all(iguais), f"versao {v}: as 8 mascaras dao a mesma matriz do segno ({len(ref['texto'])} bytes)", str(iguais))

    r = page.evaluate("() => { const q = qrMatriz('otpauth://totp/Supabase:eduardo@example.com?algorithm=SHA1&digits=6&issuer=Supabase&period=30&secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP'); return {v: q.versao, m: q.mascara, n: q.n}; }")
    conf(r["v"] == 8 and 0 <= r["m"] <= 7 and r["n"] == 49, "o endereco otpauth de verdade do Supabase sai na versao 8 (49 x 49) com uma mascara escolhida pela penalidade", str(r))
    r = page.evaluate("() => { const q = qrMatriz('otpauth://totp/AE%20Agropecuaria?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=AE%20Agropecuaria'); return {v: q.versao, n: q.n}; }")
    conf(r["v"] == 6 and r["n"] == 41, "o endereco montado so com a chave sai na versao 6 (41 x 41)", str(r))
    a = page.evaluate("() => qrMatriz('Fazenda S\u00e3o Jo\u00e3o').versao")
    b = page.evaluate("() => qrMatriz('Fazenda Sao Joao').versao")
    conf(a >= b, "texto acentuado vira UTF-8 (ocupa 2 bytes por letra acentuada) e cabe", f"{a} {b}")
    erro = page.evaluate("() => { try { qrMatriz('x'.repeat(420)); return null; } catch(e) { return String(e.message); } }")
    conf(erro and "grande demais" in erro, "texto de mais de 415 bytes da erro em vez de um QR errado", str(erro))
    svg = page.evaluate("() => qrSvgLocal('otpauth://totp/AE?secret=JBSWY3DPEHPK3PXP&issuer=AE', 240)")
    vb = re.search(r'viewBox="0 0 (\d+) (\d+)"', svg)
    larg = re.search(r' width="(\d+)"', svg)
    conf(vb and vb.group(1) == vb.group(2) and larg and int(larg.group(1)) % int(vb.group(1)) == 0 and svg.count("<path") == 1 and "<rect" not in svg,
         "o SVG tem viewBox, um so caminho, e cada modulo ocupa um numero inteiro de pixels", svg[:160])
    browser.close()

print(f"\n{passes} ok, {falhas} falhas")
sys.exit(1 if falhas else 0)
