import test from 'node:test';
import assert from 'node:assert/strict';
import {scale} from '../index.js';

test('scales values by two', () => {
  assert.equal(scale(6), 12);
});
