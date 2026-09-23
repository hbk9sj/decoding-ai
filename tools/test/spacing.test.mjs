// node --test tools/test/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { space } from '../spacing.mjs';

const due = '2026-09-29T02:30:00.000Z';
const h = n => new Date(Date.parse(due) + n * 3600e3).toISOString();

test('nothing else queued: the slot stands', () => {
  assert.equal(space(due, []), due);
});
test('a post 3 h after the slot: moved one day, same clock time', () => {
  assert.equal(space(due, [h(3)]), h(24));
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
  assert.equal(space(due, [h(1), h(25)]), h(48));
});
test('every day for a week is taken: refused', () => {
  assert.equal(space(due, [0, 1, 2, 3, 4, 5, 6, 7].map(d => h(d * 24 + 2))), null);
});
test('bad input is refused, not guessed', () => {
  assert.throws(() => space('not a date', []));
});
