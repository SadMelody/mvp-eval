import {readFileSync} from 'node:fs';

const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

if (!packageJson.scripts.test.includes('scripts/check-package-config.js')) {
  console.error('dependency script error: test script must run scripts/check-package-config.js');
  process.exit(1);
}
