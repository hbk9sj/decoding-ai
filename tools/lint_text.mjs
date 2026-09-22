#!/usr/bin/env node
// The text-post contract. Every rule here comes from measured 2026 LinkedIn data
// (see BRIEF.md for the sources); a post that breaks one does not get posted.
//   node tools/lint_text.mjs <folder>      (folder holds copy.json with kind:"text")
// Exit 0 clean, 2 on any breach.
import { readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const folder = process.argv[2];
if (!folder) { console.error('usage: node tools/lint_text.mjs <folder>'); process.exit(1); }
const copy = JSON.parse(await readFile(join(ROOT, folder, 'copy.json'), 'utf8'));
const out = [];
const text = String(copy.body || '');
const lines = text.split('\n').map(s => s.trim());
const first = lines[0] || '';

// — the hook (the only part 60–70 % of readers ever see) —
if (!first) out.push('body is empty');
if (first.length > 140) out.push(`hook is ${first.length} chars — the mobile feed cuts at ~140`);
if (/\?\s*$/.test(first)) out.push('hook ends in a question — question openers measure −28 % median likes');
if (/^(stop|start|read|don'?t|never|listen|attention)\b/i.test(first)) out.push('imperative hook ("Stop…", "Read this…") — measured 0.02× engagement lift, the worst of any archetype');
if (!/\d/.test(first + ' ' + (lines[1] || ''))) out.push('no number in the first two lines — quantified proof appears in 61 % of top-1 % posts');

// — the body —
if (text.length < 400 || text.length > 1300) out.push(`body is ${text.length} chars — keep it 400–1300`);
if (/https?:\/\//.test(text)) out.push('a link in the body costs ~60 % of reach — put it in first_comment');
const tags = text.match(/#\w+/g) || [];
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
if (!copy.first_comment || !/https?:\/\//.test(copy.first_comment)) out.push('first_comment must carry the source link');
if (!copy.pillar) out.push('pillar missing (decoded | tried | belief)');
if (!copy.slug) out.push('slug missing');

if (out.length) { console.error('TEXT GATE FAILED\n- ' + out.join('\n- ')); process.exit(2); }
console.log(`text ok · ${text.length} chars · hook ${first.length} chars · grade ${grade.toFixed(1)} · ${tags.length} hashtags`);
