// Gera os arquivos da entrega do PBL Fase 6:
//   saida/Omni-Tribo-Fase6-RM555833/
//     Omni-Tribo - Fase 6 - Documentacao.pdf
//     Omni-Tribo - Fase 6 - Slides.pdf
//     LINKS.txt
//     codigo/Oracle/…              (os fontes desta fase, sem credencial)
//   saida/Omni-Tribo-Fase6-RM555833.zip
//
// Uso (a partir de Oracle/entrega):
//   npm install                                          # primeira vez
//   VIDEO_URL="https://youtu.be/…" node gerar.mjs
//
// A FOTO do integrante é lida de Oracle/entrega/foto.jpg (ou .png). Sem o arquivo, o slide 1 sai
// com um quadro tracejado no lugar — e o script AVISA, porque o enunciado exige a foto.
// Sem VIDEO_URL, o link sai marcado como pendente no documento e nos slides, e o script avisa.
//
// Por que um script e não um PDF exportado à mão: o link do vídeo só existe depois da gravação, e
// ele precisa aparecer no documento E nos slides. Com o gerador, é rodar de novo.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { marked } from 'marked';
import puppeteer from 'puppeteer';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const oracle = path.resolve(aqui, '..');
const saida = path.join(aqui, 'saida');
const pacote = path.join(saida, 'Omni-Tribo-Fase6-RM555833');
const REPO = 'https://github.com/RenanFerreira02/Omni-Tribo-PBL';
const PENDENTE = 'COLE-A-URL-DO-VIDEO-AQUI';

const videoUrl = (process.env.VIDEO_URL ?? '').trim();
const avisos = [];
if (!videoUrl) {
  avisos.push('VIDEO_URL não informada: o link do vídeo saiu marcado como PENDENTE.');
} else if (!/^https:\/\/(www\.)?(youtube\.com|youtu\.be)\//.test(videoUrl)) {
  // Entrada não confiável vai parar dentro de HTML; só aceitamos o que tem cara de YouTube.
  throw new Error(`VIDEO_URL não parece um link do YouTube: ${videoUrl}`);
}

const foto = ['foto.jpg', 'foto.jpeg', 'foto.png']
  .map((nome) => path.join(aqui, nome))
  .find((arquivo) => fs.existsSync(arquivo));
if (!foto) {
  avisos.push('Sem Oracle/entrega/foto.jpg: o slide 1 saiu SEM a foto que o enunciado exige.');
}

const ler = (...partes) => fs.readFileSync(path.join(oracle, ...partes), 'utf8');
const escapar = (texto) =>
  texto.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** Imagem embutida como data URI: o HTML intermediário não depende de caminho relativo. */
function dataUri(arquivo) {
  const tipo = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml' }[
    path.extname(arquivo).toLowerCase()
  ];
  return `data:${tipo};base64,${fs.readFileSync(arquivo).toString('base64')}`;
}

/**
 * Markdown de `Oracle/docs` → HTML.
 *
 * Link relativo vira link para o GitHub: dentro de um PDF, `../sql/04_functions.sql` não aponta
 * para lugar nenhum. Imagem relativa é embutida. Âncora interna (#…) fica como está.
 */
function paraHtml(markdown, pastaDoArquivo) {
  const comImagens = markdown.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (tudo, alt, destino) => {
    if (/^https?:/.test(destino)) return tudo;
    const arquivo = path.resolve(pastaDoArquivo, destino);
    return fs.existsSync(arquivo) ? `![${alt}](${dataUri(arquivo)})` : tudo;
  });
  const comLinks = comImagens.replace(/(?<!!)\[([^\]]+)\]\(([^)]+)\)/g, (tudo, texto, destino) => {
    if (/^(https?:|#|data:|mailto:)/.test(destino)) return tudo;
    const [caminho, ancora] = destino.split('#');
    const absoluto = path.resolve(pastaDoArquivo, caminho);
    const relativoAoRepo = path.relative(path.resolve(oracle, '..'), absoluto).split(path.sep).join('/');
    const tipo = fs.existsSync(absoluto) && fs.statSync(absoluto).isDirectory() ? 'tree' : 'blob';
    return `[${texto}](${REPO}/${tipo}/main/${relativoAoRepo}${ancora ? '#' + ancora : ''})`;
  });
  return marked.parse(comLinks, { gfm: true });
}

// ───────────────────────────── documento ─────────────────────────────

const docs = path.join(oracle, 'docs');
const videoNoDocumento = videoUrl
  ? `[${videoUrl}](${videoUrl})`
  : '**PENDENTE — gravar o vídeo e gerar o PDF de novo com VIDEO_URL**';

let entrega = ler('docs', 'ENTREGA-FASE6.md').replace('`' + PENDENTE + '`', videoNoDocumento);
// O cabeçalho do Markdown (título, nome, links) vira a capa; o corpo começa na seção 1.
const inicioDoCorpo = entrega.indexOf('## 1.');
const corpo = entrega.slice(inicioDoCorpo);

// No DER, o bloco Mermaid é trocado pelo SVG já renderizado.
const der = ler('docs', 'DER.md')
  .replace(/^# .*\n/, '')
  // Sem o subtítulo "Diagrama": sozinho antes de uma imagem de página inteira, ele ficava órfão.
  .replace(/^## Diagrama\n/m, '')
  .replace(/```mermaid[\s\S]*?```/, `<img class="der" src="${dataUri(path.join(docs, 'DER.svg'))}" alt="DER">`);
const semTitulo = (texto) => texto.replace(/^# .*\n/, '');

const htmlDocumento = `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Omni-Tribo · PBL Fase 6</title>
<style>
  @page { size: A4; margin: 20mm 18mm 20mm; }
  body { font-family: "Noto Sans", "DejaVu Sans", Arial, sans-serif; font-size: 10.5pt; line-height: 1.5; color: #17212b; }
  h1 { font-size: 20pt; margin: 0 0 6pt; color: #1f5a3d; break-before: page; }
  h2 { font-size: 14.5pt; margin: 20pt 0 6pt; padding-bottom: 3pt; border-bottom: 1.5pt solid #dbe2e8; break-after: avoid; }
  h3 { font-size: 11.5pt; margin: 14pt 0 4pt; break-after: avoid; }
  p, li { orphans: 3; widows: 3; }
  a { color: #1f5a3d; text-decoration: none; }
  code { font-family: "Noto Sans Mono", "DejaVu Sans Mono", monospace; font-size: 8.8pt; background: #eef2f0; padding: 0 3pt; border-radius: 2pt; }
  pre { background: #f3f6f4; border: .6pt solid #dbe2e8; border-radius: 4pt; padding: 7pt 9pt; white-space: pre-wrap; word-break: break-word; break-inside: avoid; }
  pre code { background: none; padding: 0; font-size: 7.6pt; line-height: 1.4; }
  table { border-collapse: collapse; width: 100%; margin: 6pt 0 10pt; font-size: 9pt; }
  th, td { border: .6pt solid #cfd8de; padding: 3.5pt 5pt; text-align: left; vertical-align: top; }
  th { background: #eef2f0; }
  tr { break-inside: avoid; }
  img { max-width: 100%; }
  img.der { display: block; max-width: 100%; max-height: 200mm; width: auto; margin: 6pt auto; }
  hr { border: 0; border-top: .6pt solid #dbe2e8; margin: 14pt 0; }
  blockquote { margin: 8pt 0; padding: 2pt 10pt; border-left: 3pt solid #1f5a3d; color: #44525f; }
  .capa { height: 245mm; display: flex; flex-direction: column; justify-content: center; }
  .capa .rotulo { font-size: 10pt; letter-spacing: .12em; text-transform: uppercase; color: #1f5a3d; font-weight: 700; }
  .capa .titulo { font-size: 40pt; font-weight: 700; line-height: 1.1; margin: 8pt 0 6pt; }
  .capa .sub { font-size: 15pt; color: #5d6b7a; margin-bottom: 36pt; }
  .capa dl { display: grid; grid-template-columns: 34mm 1fr; row-gap: 5pt; font-size: 11pt; margin: 0; }
  .capa dt { color: #5d6b7a; } .capa dd { margin: 0; }
  .sumario { break-before: page; } .sumario h2 { border: 0; }
  .sumario ol { font-size: 11pt; line-height: 1.9; }
  section.primeira h2:first-child { margin-top: 0; }
</style></head><body>

<div class="capa">
  <div class="rotulo">FIAP · Sistemas de Informação · PBL Fase 6 · Smart HAS</div>
  <div class="titulo">Omni-Tribo</div>
  <div class="sub">Camada Oracle PL/SQL integrada ao back-end Java</div>
  <dl>
    <dt>Integrante</dt><dd><strong>Renan Ferreira</strong> — RM 555833</dd>
    <dt>Repositório</dt><dd><a href="${REPO}">${REPO}</a></dd>
    <dt>Vídeo</dt><dd>${videoUrl ? `<a href="${escapar(videoUrl)}">${escapar(videoUrl)}</a>` : '<strong>PENDENTE</strong> — gravar e gerar o PDF de novo'}</dd>
    <dt>Banco</dt><dd>Oracle Database 19c, instância da FIAP</dd>
    <dt>Data</dt><dd>outubro de 2026</dd>
  </dl>
</div>

<div class="sumario">
  <h2>Conteúdo</h2>
  <ol>
    <li>O que foi entregue</li>
    <li>Parte 1 — Aprimoramento da solução</li>
    <li>Parte 2 — Integração do banco Oracle</li>
    <li>Parte 3 — Functions e procedures em PL/SQL</li>
    <li>Como reproduzir</li>
    <li>Limites declarados</li>
  </ol>
  <p><strong>Apêndices:</strong> A — DER · B — Functions e procedures em detalhe · C — Dicionário de
  dados · D — Evidências de execução</p>
</div>

<section class="primeira" style="break-before: page">${paraHtml(corpo, docs)}</section>

<h1>Apêndice A — DER</h1>
${paraHtml(der, docs)}

<h1>Apêndice B — Functions e procedures em detalhe</h1>
${paraHtml(semTitulo(ler('docs', 'PLSQL.md')), docs)}

<h1>Apêndice C — Dicionário de dados</h1>
${paraHtml(semTitulo(ler('docs', 'DICIONARIO.md')), docs)}

<h1>Apêndice D — Evidências de execução</h1>
${paraHtml(semTitulo(ler('evidencias', 'README.md')), path.join(oracle, 'evidencias'))}
<h2>Testes (saída completa)</h2>
<pre><code>${escapar(ler('evidencias', '03-testes.txt').trim())}</code></pre>
<h2>Java → Oracle (saída completa)</h2>
<pre><code>${escapar(ler('evidencias', '04-java-rest-jdbc-oracle.txt').trim())}</code></pre>

</body></html>`;

// ───────────────────────────── slides ─────────────────────────────

const htmlSlides = fs
  .readFileSync(path.join(aqui, 'slides.html'), 'utf8')
  .replaceAll(
    '{{VIDEO}}',
    videoUrl ? escapar(videoUrl) : '<span class="pendente">pendente — gravar e gerar de novo</span>',
  )
  .replace(
    '{{FOTO}}',
    foto
      ? `<img class="foto" src="${dataUri(foto)}" alt="Foto de Renan Ferreira">`
      : '<div class="foto-vazia">FOTO<br>salve como<br>Oracle/entrega/foto.jpg</div>',
  )
  .replace('{{CAPTURA}}', dataUri(path.join(aqui, 'imagens', 'dashboard-potes-imobilizados.png')));

// ───────────────────────────── PDFs ─────────────────────────────

/** Chrome do cache do Puppeteer, se a versão que esta instalação pede não tiver sido baixada. */
function chromeDoCache() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  try {
    if (fs.existsSync(puppeteer.executablePath())) return undefined; // o padrão serve
  } catch {
    /* segue para o cache */
  }
  const raiz = path.join(os.homedir(), '.cache', 'puppeteer', 'chrome');
  if (!fs.existsSync(raiz)) return undefined;
  const candidatos = fs
    .readdirSync(raiz)
    .map((versao) => path.join(raiz, versao, 'chrome-linux64', 'chrome'))
    .filter((arquivo) => fs.existsSync(arquivo))
    .sort();
  return candidatos.pop();
}

fs.rmSync(saida, { recursive: true, force: true });
fs.mkdirSync(pacote, { recursive: true });

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'omnitribo-entrega-'));
const htmlDoc = path.join(tmp, 'documento.html');
const htmlSld = path.join(tmp, 'slides.html');
fs.writeFileSync(htmlDoc, htmlDocumento);
fs.writeFileSync(htmlSld, htmlSlides);

const pdfDocumento = path.join(pacote, 'Omni-Tribo - Fase 6 - Documentacao.pdf');
const pdfSlides = path.join(pacote, 'Omni-Tribo - Fase 6 - Slides.pdf');

const navegador = await puppeteer.launch({
  headless: true,
  executablePath: chromeDoCache(),
  args: ['--no-sandbox'],
});
try {
  const pagina = await navegador.newPage();

  await pagina.goto(pathToFileURL(htmlDoc).href, { waitUntil: 'networkidle0' });
  await pagina.pdf({
    path: pdfDocumento,
    format: 'A4',
    printBackground: true,
    displayHeaderFooter: true,
    headerTemplate: '<span></span>',
    footerTemplate:
      '<div style="font-size:7.5pt;color:#5d6b7a;width:100%;padding:0 18mm;display:flex;justify-content:space-between">' +
      '<span>Omni-Tribo · PBL Fase 6 · Renan Ferreira · RM 555833</span>' +
      '<span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>',
    margin: { top: '20mm', bottom: '20mm', left: '18mm', right: '18mm' },
  });

  await pagina.goto(pathToFileURL(htmlSld).href, { waitUntil: 'networkidle0' });
  await pagina.pdf({ path: pdfSlides, width: '1280px', height: '720px', printBackground: true });
} finally {
  await navegador.close();
  fs.rmSync(tmp, { recursive: true, force: true });
}

// ───────────────────────────── pacote ─────────────────────────────

fs.writeFileSync(
  path.join(pacote, 'LINKS.txt'),
  [
    'Omni-Tribo — PBL Fase 6 (Smart HAS)',
    'Renan Ferreira — RM 555833',
    '',
    `Repositório (GitHub): ${REPO}`,
    `Pasta desta fase:     ${REPO}/tree/main/Oracle`,
    `Vídeo (YouTube):      ${videoUrl || 'PENDENTE — gravar o vídeo e gerar o pacote de novo'}`,
    '',
    'Neste ZIP:',
    '  Omni-Tribo - Fase 6 - Documentacao.pdf   documento da entrega',
    '  Omni-Tribo - Fase 6 - Slides.pdf         apresentação (10 slides)',
    '  codigo/Oracle/                           fontes desta fase: SQL, PL/SQL, Java e evidências',
    '',
    'O projeto completo (app mobile, API e dashboard) está no repositório acima.',
    '',
  ].join('\n'),
);

// Cópia dos fontes desta fase. O que NÃO entra, e por quê:
//   .env                credencial do Oracle
//   target/             build do Java
//   entrega/            o próprio gerador, node_modules e a saída
const ignorar = new Set(['.env', 'target', 'entrega', 'node_modules']);
// Item a item, e não a pasta inteira: o destino fica DENTRO de Oracle/, e o Node recusa copiar um
// diretório para um subdiretório de si mesmo.
const destinoCodigo = path.join(pacote, 'codigo', 'Oracle');
fs.mkdirSync(destinoCodigo, { recursive: true });
for (const item of fs.readdirSync(oracle)) {
  if (ignorar.has(item)) continue;
  fs.cpSync(path.join(oracle, item), path.join(destinoCodigo, item), {
    recursive: true,
    filter: (origem) => !ignorar.has(path.basename(origem)),
  });
}

// Trava de segurança: o pacote vai para fora da máquina, então conferimos antes de compactar.
const vazou = [];
(function varrer(pasta) {
  for (const item of fs.readdirSync(pasta, { withFileTypes: true })) {
    const completo = path.join(pasta, item.name);
    if (item.isDirectory()) varrer(completo);
    else if (item.name === '.env') vazou.push(completo);
  }
})(pacote);
if (vazou.length > 0) {
  throw new Error(`Arquivo de credencial dentro do pacote: ${vazou.join(', ')}`);
}

const zip = `${pacote}.zip`;
execFileSync('zip', ['-r', '-q', path.basename(zip), path.basename(pacote)], { cwd: saida });

const tamanho = (arquivo) => `${(fs.statSync(arquivo).size / 1024).toFixed(0)} KB`;
console.log(`Documento: ${path.relative(process.cwd(), pdfDocumento)} (${tamanho(pdfDocumento)})`);
console.log(`Slides:    ${path.relative(process.cwd(), pdfSlides)} (${tamanho(pdfSlides)})`);
console.log(`ZIP:       ${path.relative(process.cwd(), zip)} (${tamanho(zip)})`);
for (const aviso of avisos) {
  console.log(`AVISO: ${aviso}`);
}
