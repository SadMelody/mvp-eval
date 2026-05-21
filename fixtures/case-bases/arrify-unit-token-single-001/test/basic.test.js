import test from 'node:test';
import assert from 'node:assert/strict';
import arrify from '../index.js';

test('keeps nullish values as an empty array', () => {
	assert.deepEqual(arrify(null), []);
	assert.deepEqual(arrify(undefined), []);
});

test('wraps scalar values', () => {
	assert.deepEqual(arrify('value'), ['value']);
	assert.deepEqual(arrify(1), [1]);
});

test('converts iterable values to arrays', () => {
	assert.deepEqual(arrify(new Set([1, 2])), [1, 2]);
});
