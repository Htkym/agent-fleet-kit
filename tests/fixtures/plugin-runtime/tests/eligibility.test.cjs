const assert = require('node:assert/strict');
const test = require('node:test');
const { eligible } = require('../src/eligibility.cjs');
const labels = require('../src/labels.json');

test('five years or more is eligible', () => {
  assert.equal(eligible(4), false);
  assert.equal(eligible(5), true);
  assert.equal(eligible(6), true);
});

test('invalid inputs remain rejected', () => {
  for (const value of [-1, 1.5, '5', null, NaN]) {
    assert.throws(() => eligible(value), RangeError);
  }
});

test('label keys are preserved and values are uppercase', () => {
  assert.deepEqual(labels, { eligible: 'ELIGIBLE', ineligible: 'INELIGIBLE' });
});
