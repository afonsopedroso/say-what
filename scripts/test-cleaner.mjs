import { clean } from '../web/cleaner.js';
const cases = [
  ['Um, so I think, uh, we should go.', 'So I think, we should go.'],
  ['I I think that\'s fine', 'I think that\'s fine'],
  ['Hã, eu acho que, hum, vamos amanhã.', 'Eu acho que, vamos amanhã.'],
  ['Tipo, está tudo bem.', 'Está tudo bem.'],
  ['Hello there new line how are you', 'Hello there\nHow are you'],
  ['Olá nova linha tudo bem ponto de interrogação', 'Olá\nTudo bem?'],
  ['Meet at 5. Meet at 6. Scratch that. Meet at 7.', 'Meet at 5. Meet at 7.'],
  ['Primeiro parágrafo. Novo parágrafo. Segundo.', 'Primeiro parágrafo.\n\nSegundo.'],
  ['Thank you.', ''], ['Obrigado.', ''], ['[Music]', ''],
  ['hello , world .how are you', 'Hello, world. How are you'],
  ["i'm here and i think so", "I'm here and I think so"],
  ['visit example.com today', 'Visit example.com today'],
];
let fail = 0;
for (const [i, o] of cases) { const r = clean(i); if (r !== o) { fail++; console.log('FAIL', JSON.stringify(i), '=>', JSON.stringify(r), 'expected', JSON.stringify(o)); } }
const r1 = clean('ask chat gpt and send it to my email.', { replacements: [{ from: 'chat gpt', to: 'ChatGPT' }], snippets: [{ trigger: 'my email', text: 'afonso@example.com' }] });
if (r1 !== 'Ask ChatGPT and send it to afonso@example.com') { fail++; console.log('FAIL snippets', r1); }
if (clean('Sounds good, see you later.', { style: 'casual' }) !== 'sounds good, see you later') { fail++; console.log('FAIL casual'); }
if (clean('thanks for the update', { style: 'formal' }) !== 'Thanks for the update.') { fail++; console.log('FAIL formal'); }
console.log(fail ? `${fail} failures` : 'all cleaner tests pass');
process.exit(fail ? 1 : 0);
