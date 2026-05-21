import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

if (/\bvar\b/.test(source)) {
  console.error('lint-var-basic: use const instead of var in index.js');
  process.exit(1);
}
