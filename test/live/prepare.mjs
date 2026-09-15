// Test-only fixture generation; never used by the plugin at runtime.
import { cpSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const major = process.argv[2];
if (!['21', '22'].includes(major)) throw new Error('Expected Angular major 21 or 22');
const angular = major === '21' ? '21.2.23' : '22.1.6';
const root = mkdtempSync(join(tmpdir(), `angular-refs-${major}-`));
cpSync(join(dirname(fileURLToPath(import.meta.url)), 'project'), root, { recursive: true });
const dependencies = Object.fromEntries(['core', 'common', 'compiler', 'compiler-cli', 'forms', 'platform-browser', 'language-service', 'language-server']
  .map(name => [`@angular/${name}`, angular]));
Object.assign(dependencies, { typescript: major === '21' ? '5.9.3' : '6.0.3', rxjs: '7.8.2', tslib: '2.8.1',
  'typescript-language-server': '6.0.0', '@vtsls/language-server': '0.3.0' });
writeFileSync(join(root, 'package.json'), JSON.stringify({ private: true, dependencies }, null, 2));
writeFileSync(join(root, '.angular-refs-fixture'), 'angular-refs live fixture v1\n');
console.log(root);
