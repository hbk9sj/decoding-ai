// node --test tools/test/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { space } from '../spacing.mjs';

const due = '2026-09-29T02:30:00.000Z';
const h = n => new Date(Date.parse(due) + n * 3600e3).toISOString();

test('nothing else queued: the slot stands', () => {
  assert.equal(space(due, []), due);
});
test('the same slot already taken: moved one day, same clock time', () => {
  assert.equal(space(due, [h(0)]), h(24));
});
test('a post 3 h after the slot: tomorrow is only 21 h from it, so two days on', () => {
  assert.equal(space(due, [h(3)]), h(48));
});
test('a post 3 h before the slot: moved one day', () => {
  assert.equal(space(due, [h(-3)]), h(24));
});
test('a post 30 h away is clear', () => {
  assert.equal(space(due, [h(30)]), due);
});
test('a post exactly 24 h away is clear', () => {
  assert.equal(space(due, [h(-24), h(24)]), due);
});
test('clashes on two days: lands on the third', () => {
  // +1 h blocks today; +23 h blocks tomorrow (1 h from it, 23 h from the first)
  assert.equal(space(due, [h(1), h(23)]), h(48));
});
test('every day for a week is taken: refused', () => {
  assert.equal(space(due, [0, 1, 2, 3, 4, 5, 6, 7].map(d => h(d * 24 + 2))), null);
});
test('bad input is refused, not guessed', () => {
  assert.throws(() => space('not a date', []));
});
