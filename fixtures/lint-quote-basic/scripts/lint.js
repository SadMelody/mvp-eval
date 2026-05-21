import {readFileSync} from 'node:fs';

const source = readFileSync(new URL('../index.js', import.meta.url), 'utf8');

if (source.includes('"')) {
  console.error('lint-quote-basic: use single quotes in index.js');
  process.exit(1);
}
