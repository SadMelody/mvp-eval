import test from 'node:test';
import assert from 'node:assert/strict';
import {formatName} from '../index.js';

test('formats names in display order', () => {
  assert.equal(formatName('Ada', 'Lovelace'), 'Ada Lovelace');
});
