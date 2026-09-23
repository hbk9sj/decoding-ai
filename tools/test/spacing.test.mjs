// node --test tools/test/*.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { space } from '../spacing.mjs';

const due = '2026-09-29T02:30:00.000Z';
const h = n => new Date(Date.parse(due) + n * 3600e3).toISOString();

test('nothing else queued: the slot stands', () => {
  assert.equal(space(due, []), due);
});
test('the same slot already taken: moved 12 h, to the evening', () => {
  assert.equal(space(due, [h(0)]), h(12));
});
test('two posts in one day are allowed when 12 h apart', () => {
  assert.equal(space(due, [h(-12)]), due);
});
test('a post exactly 12 h away on both sides is clear', () => {
  assert.equal(space(due, [h(-12), h(12)]), due);
});
test('a post 3 h after the slot: +12 h is only 9 h from it, so +24 h', () => {
  assert.equal(space(due, [h(3)]), h(24));
});
test('a post 3 h before the slot: moved 12 h', () => {
  assert.equal(space(due, [h(-3)]), h(12));
});
test('a post 11 h away blocks the slot and the next one', () => {
  assert.equal(space(due, [h(11)]), h(24));
});
test('clashes on three slots in a row: lands on the fourth', () => {
  // +1 h blocks the slot and +12 h; +13 h blocks +12 h and +24 h (11 h from it)
  assert.equal(space(due, [h(1), h(13)]), h(36));
});
test('every 12 h slot for a week is taken: refused', () => {
  assert.equal(space(due, Array.from({ length: 15 }, (_, k) => h(k * 12 + 2))), null);
});
test('bad input is refused, not guessed', () => {
  assert.throws(() => space('not a date', []));
});
