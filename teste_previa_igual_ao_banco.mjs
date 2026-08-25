// Reproduz a previa da tela (ModalBaixa) para os MESMOS casos e compara
// com o que o gatilho do banco gravou.
const casos = [
  {titulo:100.00,  rat:[33.33,33.33,33.34],       baixa:60.00,   banco:[20.00,20.00,20.00]},
  {titulo:1000.01, rat:[333.34,333.34,333.33],    baixa:600.01,  banco:[200.01,200.01,199.99]},
  {titulo:0.05,    rat:[0.02,0.02,0.01],          baixa:0.03,    banco:[0.01,0.01,0.01]},
  {titulo:7777.77, rat:[2592.59,2592.59,2592.59], baixa:4666.66, banco:[1555.55,1555.55,1555.56]},
  {titulo:5000.00, rat:[3000.00,1000.00,1000.00], baixa:3000.00, banco:[1800.00,600.00,600.00]},
];
let falhou = 0;
for(const c of casos){
  // exatamente a expressao que esta no ModalBaixa
  const previa = c.rat.map((v,i)=> i===c.rat.length-1
    ? c.baixa - c.rat.slice(0,-1).reduce((a,x)=>a+Math.round(c.baixa*(x/c.titulo)*100)/100, 0)
    : Math.round(c.baixa*(v/c.titulo)*100)/100);
  const p = previa.map(x=>Math.round(x*100)/100);
  const igual = JSON.stringify(p) === JSON.stringify(c.banco);
  const soma = Math.round(p.reduce((a,b)=>a+b,0)*100)/100;
  console.log(`  ${igual && soma===c.baixa ? 'ok    ' : 'FALHOU'}  titulo ${c.titulo} baixa ${c.baixa}`);
  console.log(`          tela  : ${p.join(' + ')} = ${soma}`);
  console.log(`          banco : ${c.banco.join(' + ')} = ${Math.round(c.banco.reduce((a,b)=>a+b,0)*100)/100}`);
  if(!igual || soma!==c.baixa) falhou++;
}
console.log(falhou ? `\n  ${falhou} caso(s) em que a tela mostraria numero diferente do banco` : '\n  a tela e o banco fazem a mesma conta nos 5 casos');
process.exit(falhou?1:0);
