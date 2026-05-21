import test from 'node:test';
import assert from 'node:assert/strict';
import {label} from '../index.js';

test('labels values', () => {
  assert.equal(label('core'), 'pkg:core');
});
