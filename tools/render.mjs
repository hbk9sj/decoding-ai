#!/usr/bin/env node
// Render one carousel folder to PNG pages + a LinkedIn document PDF, and GATE it.
//   node tools/render.mjs <folder>       (folder holds copy.json)
// Exit 0: every page clean, PDF written.  2: gate failed.  3: Playwright missing.  1: other.
import { createServer } from 'node:http';
import { readFile, writeFile, stat } from 'node:fs/promises';
import { resolve, join, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PDFDocument } from 'pdf-lib';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const folder = process.argv[2];
if (!folder) { console.error('usage: node tools/render.mjs <folder-with-copy.json>'); process.exit(1); }
const rel = folder.replace(/^\.?\//, '').replace(/\/$/, '');
const dir = resolve(ROOT, rel);
const copy = JSON.parse(await readFile(join(dir, 'copy.json'), 'utf8'));

const W = 1080, H = 1350, SCALE = 2;
const words = s => String(s ?? '').trim().split(/\s+/).filter(Boolean).length;
const fail = msgs => { console.error('GATE FAILED\n- ' + msgs.join('\n- ')); process.exit(2); };

// ---- 1. copy contract, before any pixels ----
const pre = [];
const TPL = ['broadsheet', 'riso', 'field', 'memo'];
if (!TPL.includes(copy.template)) pre.push(`template must be one of ${TPL.join(', ')} (got ${copy.template})`);
if (!copy.slug) pre.push('slug missing');
if (!copy.title || copy.title.length > 70) pre.push('title missing or over 70 chars (it is the second hook in the feed)');
if (!copy.source?.url || !copy.source?.publisher) pre.push('source.url and source.publisher are required');
const pages = copy.pages || [];
if (pages.length < 8 || pages.length > 10) pre.push(`pages must be 8–10 (got ${pages.length}); completion rate feeds reach`);
if (pages[0]?.type !== 'cover') pre.push('page 1 must be the cover (the hook)');
if (pages.at(-1)?.type !== 'cta') pre.push('last page must be the cta');
if (!pages.some(p => p.type === 'takeaway')) pre.push('one takeaway page ("do this today") is required');
const limits = {
  cover: p => [[words(p.headline) <= 12, 'cover.headline ≤ 12 words'], [words(p.deck) <= 26, 'cover.deck ≤ 26 words']],
  point: p => [[words(p.headline) <= 9, 'point.headline ≤ 9 words'], [words(p.body) <= 38, 'point.body ≤ 38 words'], [!p.note || words(p.note) <= 8, 'point.note ≤ 8 words']],
  stat: p => [[String(p.value ?? '').length <= 9, 'stat.value ≤ 9 chars'], [words(p.body) <= 34, 'stat.body ≤ 34 words']],
  contrast: p => [[words(p.headline) <= 9, 'contrast.headline ≤ 9 words'], [words(p.left) <= 22, 'contrast.left ≤ 22 words'], [words(p.right) <= 22, 'contrast.right ≤ 22 words']],
  quote: p => [[words(p.quote) <= 26, 'quote ≤ 26 words'], [words(p.body) <= 30, 'quote.body ≤ 30 words']],
  takeaway: p => [[words(p.headline) <= 9, 'takeaway.headline ≤ 9 words'], [words(p.body) <= 38, 'takeaway.body ≤ 38 words']],
  cta: p => [[words(p.headline) <= 10, 'cta.headline ≤ 10 words'], [words(p.body) <= 28, 'cta.body ≤ 28 words']],
};
pages.forEach((p, i) => {
  const f = limits[p.type];
  if (!f) return pre.push(`page ${i + 1}: unknown type "${p.type}"`);
  f(p).forEach(([ok, why]) => { if (!ok) pre.push(`page ${i + 1} (${p.type}): ${why}`); });
});
if (pre.length) fail(pre);

// ---- 2. static server ----
const types = { '.html': 'text/html', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.ttf': 'font/ttf' };
const server = createServer(async (req, res) => {
  try {
    const p = resolve(ROOT, '.' + decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!p.startsWith(ROOT)) throw new Error('outside root');
    const data = await readFile(p);
    res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' });
    res.end(data);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

let chromium;
try { ({ chromium } = await import('playwright')); }
catch { console.error('Playwright missing: cd tools && npm ci && npx playwright install chromium'); server.close(); process.exit(3); }
let browser;
try { browser = await chromium.launch(); }
catch (e) { console.error('Chromium failed to launch: ' + e.message); server.close(); process.exit(3); }

// ---- 3. the in-page gate ----
const gateScript = () => {
  const W = 1080, H = 1350, out = [];
  const board = document.querySelector('.artboard').getBoundingClientRect();
  const boxes = [...document.querySelectorAll('[data-box="text"]')];
  const rect = el => { const r = el.getBoundingClientRect(); return { x: r.left - board.left, y: r.top - board.top, w: r.width, h: r.height }; };
  const name = el => (el.className || el.tagName).toString().split(' ').filter(Boolean).slice(0, 2).join('.') + ':' + (el.textContent || '').trim().slice(0, 30).replace(/\s+/g, ' ');
  // a) nothing outside the frame, and nothing inside the 48px bleed margin
  for (const b of boxes) {
    const r = rect(b);
    if (r.x < 48 || r.y < 48 || r.x + r.w > W - 48 || r.y + r.h > H - 48)
      out.push(`outside safe area: ${name(b)} [${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.w)}×${Math.round(r.h)}]`);
  }
  // b) no two text blocks overlap (siblings only; nesting is fine)
  const hits = (a, b) => a.x < b.x + b.w - 2 && b.x < a.x + a.w - 2 && a.y < b.y + b.h - 2 && b.y < a.y + a.h - 2;
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    if (boxes[i].contains(boxes[j]) || boxes[j].contains(boxes[i])) continue;
    if (hits(rect(boxes[i]), rect(boxes[j]))) out.push(`overlap: ${name(boxes[i])} × ${name(boxes[j])}`);
  }
  // c) every visible text node: min size and contrast against its painted ground
  const lum = c => { const [r, g, b] = c.map(v => { v /= 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }); return .2126 * r + .7152 * g + .0722 * b; };
  const parse = s => (s.match(/[\d.]+/g) || []).slice(0, 3).map(Number);
  const groundOf = el => { let n = el; while (n && n !== document.body) { const bg = getComputedStyle(n).backgroundColor; const p = parse(bg); if (p.length === 3 && !/rgba\(0, 0, 0, 0\)/.test(bg)) return p; n = n.parentElement; } return [244, 241, 234]; };
  let checks = 0;
  for (const el of document.querySelectorAll('.headline,.deck,.body,.label,.kicker,.folio,.numeral,.bigstat,.hand,.stamp')) {
    const t = (el.textContent || '').trim(); if (!t) continue;
    const cs = getComputedStyle(el), size = parseFloat(cs.fontSize);
    const min = el.classList.contains('label') || el.classList.contains('folio') || el.classList.contains('kicker') ? 19 : 28;
    if (size < min) out.push(`text too small: ${name(el)} ${size}px < ${min}px`);
    const fg = parse(cs.color), bg = groundOf(el);
    const L1 = lum(fg), L2 = lum(bg), ratio = (Math.max(L1, L2) + .05) / (Math.min(L1, L2) + .05);
    const need = size >= 48 ? 3 : 4.5;
    if (ratio < need) out.push(`contrast ${ratio.toFixed(2)} < ${need}: ${name(el)}`);
    checks++;
  }
  // d) no font fell back
  const fams = new Set();
  for (const el of document.querySelectorAll('.headline,.deck,.body,.label,.kicker,.folio,.numeral,.bigstat,.hand,.stamp')) {
    if (!(el.textContent || '').trim()) continue;
    fams.add(getComputedStyle(el).fontFamily.split(',')[0].replace(/["']/g, ''));
  }
  for (const f of fams) if (!['Archivo', 'Newsreader', 'NewsreaderIt', 'SpaceGrotesk', 'JetBrainsMono', 'Caveat', 'InstrumentSerif'].includes(f)) out.push(`unexpected font family: ${f}`);
  for (const f of fams) if (!document.fonts.check(`32px "${f}"`)) out.push(`font not loaded: ${f}`);
  return { problems: out, checks };
};

// ---- 4. render every page ----
const ctx = await browser.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: SCALE });
const report = { slug: copy.slug, template: copy.template, pages: [] };
let totalChecks = 0;
const pngs = [];
for (let i = 1; i <= pages.length; i++) {
  const page = await ctx.newPage();
  await page.goto(`http://127.0.0.1:${port}/render/page.html?post=${encodeURIComponent(rel)}&page=${i}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('body[data-ready="1"]', { timeout: 15000 });
  const { problems, checks } = await page.evaluate(gateScript);
  totalChecks += checks;
  const file = join(dir, `p${String(i).padStart(2, '0')}.jpg`);
  await page.screenshot({ path: file, type: 'jpeg', quality: 92, clip: { x: 0, y: 0, width: W, height: H } });
  pngs.push(file);
  report.pages.push({ page: i, type: pages[i - 1].type, problems });
  await page.close();
}
await browser.close(); server.close();
await writeFile(join(dir, 'gate.json'), JSON.stringify(report, null, 2));

const bad = report.pages.filter(p => p.problems.length);
if (bad.length) fail(bad.flatMap(p => p.problems.map(x => `page ${p.page}: ${x}`)));

// ---- 5. assemble the PDF and gate the file ----
const pdf = await PDFDocument.create();
pdf.setTitle(copy.title); pdf.setAuthor('Decoding AI'); pdf.setSubject(copy.topic || '');
for (const f of pngs) {
  const img = await pdf.embedJpg(await readFile(f));
  const page = pdf.addPage([W, H]);
  page.drawImage(img, { x: 0, y: 0, width: W, height: H });
}
const bytes = await pdf.save();
const pdfPath = join(dir, 'carousel.pdf');
await writeFile(pdfPath, bytes);
const mb = bytes.length / 1e6;
const post = [];
if (pdf.getPageCount() !== pages.length) post.push(`pdf has ${pdf.getPageCount()} pages, expected ${pages.length}`);
for (const p of pdf.getPages()) { const { width, height } = p.getSize(); if (Math.round(width) !== W || Math.round(height) !== H) post.push(`pdf page ${Math.round(width)}×${Math.round(height)} — every page must be ${W}×${H}`); }
if (mb > 10) post.push(`pdf is ${mb.toFixed(1)} MB — keep it under 10 MB`);
if (post.length) fail(post);

// thumbnail = page 1, half size, for Buffer's required thumbnailUrl
// thumbnail: page 1 at 1x, PNG, for Buffer's required thumbnailUrl
const { chromium: c2 } = await import('playwright');
const b2 = await c2.launch();
const ctx2 = await b2.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
const pg = await ctx2.newPage();
await pg.setContent(`<body style="margin:0"><img src="data:image/jpeg;base64,${(await readFile(pngs[0])).toString('base64')}" style="width:1080px;height:1350px;display:block"></body>`);
await pg.screenshot({ path: join(dir, 'thumb.png') });
// contact sheet for human review: all pages side by side
const sheet = await ctx2.newPage();
await sheet.setViewportSize({ width: 270 * pngs.length, height: 338 });
const imgs = await Promise.all(pngs.map(async f => `<img src="data:image/jpeg;base64,${(await readFile(f)).toString('base64')}" style="width:270px;height:338px;display:block">`));
await sheet.setContent(`<body style="margin:0;display:flex">${imgs.join('')}</body>`);
await sheet.screenshot({ path: join(dir, 'sheet.jpg'), type: 'jpeg', quality: 82 });
await b2.close();

console.log(`rendered ${pages.length} pages · ${totalChecks}/${totalChecks} text checks clean · pdf ${mb.toFixed(2)} MB · ${rel}/carousel.pdf`);
