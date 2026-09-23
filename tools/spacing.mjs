#!/usr/bin/env node
// 12 hours between posts on the channel: two a day while the account grows (Suraj, 23 Sep
// 2026), never two in the same minute, which splits the audience's attention and the
// first-hour signal (day one, 23 Sep 2026: both went out at 09:15 IST).
//   node tools/spacing.mjs <due ISO> '<JSON array of other posts' due ISO times>'
// Prints the time to use: the slot itself if clear, else the first clear time 12, 24, 36 ...
// hours on (morning slot, evening slot), up to 7 days on. Exit 2 when the whole week is taken.
import { fileURLToPath } from 'node:url';

const HOUR = 3600e3;

export function space(due, taken, { gapHours = 12, maxDays = 7 } = {}) {
  const t0 = Date.parse(due);
  if (Number.isNaN(t0)) throw new Error(`not a date: ${due}`);
  const others = taken.map(t => Date.parse(t)).filter(t => !Number.isNaN(t));
  for (let k = 0; k * gapHours <= maxDays * 24; k++) {
    const c = t0 + k * gapHours * HOUR;
    if (others.every(t => Math.abs(t - c) >= gapHours * HOUR)) return new Date(c).toISOString();
  }
  return null;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [due, json = '[]'] = process.argv.slice(2);
  let at;
  try { at = space(due, JSON.parse(json)); } catch (e) { console.error(e.message); process.exit(1); }
  if (!at) { console.error(`no clear day within 7 days of ${due} — every 12 h slot is within 12 h of another post`); process.exit(2); }
  const out = at.replace('.000Z', 'Z');
  if (Date.parse(at) !== Date.parse(due)) console.error(`spaced: ${due} -> ${out} (another post was within 12 h)`);
  console.log(out);
}
