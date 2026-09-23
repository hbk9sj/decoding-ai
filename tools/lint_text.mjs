#!/usr/bin/env node
// The text-post contract. Every rule here comes from measured 2026 LinkedIn data
// (see BRIEF.md for the sources); a post that breaks one does not get posted.
//   node tools/lint_text.mjs <folder>      (folder holds copy.json with kind:"text")
// Exit 0 clean, 2 on any breach.
import { readFile, stat } from 'node:fs/promises';
import { resolve, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const folder = process.argv[2];
if (!folder) { console.error('usage: node tools/lint_text.mjs <folder>'); process.exit(1); }
const dir = join(ROOT, folder);
const copy = JSON.parse(await readFile(join(dir, 'copy.json'), 'utf8'));
const out = [];
const full = String(copy.body || '').replace(/\s+$/, '');
const URL_RE = /https?:\/\/[^\s)>\]]+/g;
// The source ships inside the post: its last line, plain text, the only URL. A preview card
// halves median reach (414 vs 858 impressions, 566,957 posts) and link comments get hidden,
// so the URL rides in the body where the cost is small and it is always seen. Length, hook
// and reading level are measured on the prose above that line.
const allLines = full.split('\n');
const lastLine = (allLines.at(-1) || '').trim();
const text = allLines.slice(0, -1).join('\n').replace(/\s+$/, '');
const lines = text.split('\n').map(s => s.trim());
const first = lines[0] || '';
// numbers as whole tokens, so "41" is not found inside "438,413"
const nums = s => new Set((String(s ?? '').match(/\d(?:[\d,.]*\d)?/g) || []));

// — the hook (the only part 60–70 % of readers ever see) —
if (!first) out.push('body is empty');
if (first.length > 140) out.push(`hook is ${first.length} chars — the mobile feed cuts at ~140`);
if (/\?\s*$/.test(first)) out.push('hook ends in a question — question openers measure −28 % median likes');
if (/^(stop|start|read|don'?t|never|listen|attention)\b/i.test(first)) out.push('imperative hook ("Stop…", "Read this…") — measured 0.02× engagement lift, the worst of any archetype');
if (!/\d/.test(first + ' ' + (lines[1] || ''))) out.push('no number in the first two lines — quantified proof appears in 61 % of top-1 % posts');

// — the body —
if (text.length < 400 || text.length > 1300) out.push(`body is ${text.length} chars without the source line — keep it 400–1300`);
if (full.length > 3000) out.push(`whole body is ${full.length} chars — LinkedIn cuts a post at 3,000`);
const urls = full.match(URL_RE) || [];
if (urls.length !== 1) out.push(`exactly one URL in the body, the source, on the last line (found ${urls.length})`);
const m = lastLine.match(/^Source:\s.+\s(https?:\/\/\S+)$/);
if (!m) out.push('source line must be the last line: "Source: <who>, <when> — <url>"');
else if (m[1] !== copy.source?.url) out.push(`the URL on the source line does not match source.url (${m[1]})`);
const tags = full.replace(URL_RE, '').match(/#\w+/g) || [];
if (tags.length > 2) out.push(`${tags.length} hashtags — more than 2 collapses reach`);
if ((text.match(/\n\n/g) || []).length < 2) out.push('needs white space: at least three short blocks separated by blank lines');

// — voice: the tells that make a post read as machine-written —
const banned = ['delve', 'in today\'s fast-paced', 'game-changer', 'game changer', 'unlock the power', 'revolutioniz', 'seamless', 'cutting-edge', 'leverage the', 'in conclusion', 'the bottom line is', 'let that sink in', 'thoughts?', 'agree?', 'comment below', 'drop a comment', 'dm me the word', 'comment "', 'tag someone', 'who else', '🚀', '💡', '🔥'];
for (const b of banned) if (text.toLowerCase().includes(b)) out.push(`banned phrase: "${b}"`);
if (/\b(I|we|my|our)\b/.test(text) === false && copy.pillar === 'tried') out.push('a "tried it" post with no first person is not a test, it is a summary');

// — reading level (Flesch–Kincaid grade; above ~10 measures ~35 % less reach) —
const sentences = text.split(/[.!?]+\s/).filter(s => s.trim().length > 2).length || 1;
const wordsArr = text.replace(/[#*]/g, '').split(/\s+/).filter(Boolean);
const syll = w => { w = w.toLowerCase().replace(/[^a-z]/g, ''); if (!w) return 1; const m = w.match(/[aeiouy]+/g); let n = m ? m.length : 1; if (/e$/.test(w) && n > 1) n--; return Math.max(1, n); };
const grade = 0.39 * (wordsArr.length / sentences) + 11.8 * (wordsArr.reduce((a, w) => a + syll(w), 0) / wordsArr.length) - 15.59;
if (grade > 10.5) out.push(`reading level grade ${grade.toFixed(1)} — keep it at or below 10`);

// — the things that earn a save and a follow —
if (!copy.action) out.push('no action line: every post ends with one thing the reader can do today');
if (copy.action && !text.includes(copy.action.slice(0, 24))) out.push('the action line is not in the body');
if (!copy.source?.url || !copy.source?.publisher) out.push('source.publisher and source.url are required');
if ('first_comment' in copy) out.push('first_comment is retired — the source goes on the last line of the body (Buffer Free refuses it, and LinkedIn hides link comments)');

// — the card: every text post carries one image, and every number on it is in the body —
const CARD = { stat: ['label', 'value', 'body'], contrast: ['headline', 'leftLabel', 'left', 'rightLabel', 'right'] };
if (copy.kind === 'text') {
  const c = copy.card;
  if (!c || !CARD[c.type]) out.push('card required on a text post: {type: "stat" | "contrast", …fields, alt} (images lead under 5k followers)');
  else {
    const alt = String(c.alt || '');
    if (alt.length < 40 || alt.length > 400) out.push(`card.alt is ${alt.length} chars — describe the card in 40–400`);
    const inBody = nums(full);
    for (const f of CARD[c.type]) for (const n of nums(c[f])) if (!inBody.has(n)) out.push(`card number ${n} not in body (card.${f})`);
  }
}

// — "tried" means measured: the measurement ships with the post —
const evidence = [];
if (copy.pillar === 'tried') {
  if (!Array.isArray(copy.evidence) || !copy.evidence.length) out.push('evidence required for a "tried" post: files under evidence/ that show the measurement');
  else for (const e of copy.evidence) {
    const p = resolve(dir, e);
    if (relative(join(dir, 'evidence'), p).startsWith('..') || !(await stat(p).catch(() => null))?.isFile()) { out.push(`evidence file missing or outside evidence/: ${e}`); continue; }
    evidence.push(await readFile(p, 'utf8'));
  }
}

// — the second comment is posted by hand, so it may not carry a claim the post does not —
if (copy.second_comment != null) {
  const sc = String(copy.second_comment);
  if (sc.length > 600) out.push(`second_comment is ${sc.length} chars — keep it under 600`);
  if (URL_RE.test(sc)) out.push('second_comment carries a URL — the source is already on the post');
  URL_RE.lastIndex = 0;
  const known = nums([full, ...Object.values(copy.card || {}), ...evidence].join(' '));
  for (const n of nums(sc)) if (!known.has(n)) out.push(`second_comment: ${n} appears nowhere else (body, card, evidence)`);
}
if (!copy.pillar) out.push('pillar missing (decoded | tried | belief)');
if (!copy.slug) out.push('slug missing');

if (out.length) { console.error('TEXT GATE FAILED\n- ' + out.join('\n- ')); process.exit(2); }
console.log(`text ok · ${text.length} chars · hook ${first.length} chars · grade ${grade.toFixed(1)} · ${tags.length} hashtags`);
