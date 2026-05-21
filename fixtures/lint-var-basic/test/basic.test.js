import test from 'node:test';
import assert from 'node:assert/strict';
import {normalize} from '../index.js';

test('normalizes input', () => {
  assert.equal(normalize(' Ada '), 'ada');
});
