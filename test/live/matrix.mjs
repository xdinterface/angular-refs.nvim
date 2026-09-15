import { spawnSync } from 'node:child_process';
import { cpSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const roots = process.argv.slice(2);
if (!roots.length) throw new Error('Pass prepared test fixture directories');
const binaries = (process.env.AR_NVIM_BINARIES || 'nvim').split(',');
const providers = process.env.AR_TS_TOOLS ? ['ts_ls', 'vtsls', 'typescript-tools'] : ['ts_ls', 'vtsls'];
for (const root of roots) {
  if (readFileSync(join(root, '.angular-refs-fixture'), 'utf8') !== 'angular-refs live fixture v1\n') {
    throw new Error('Not a prepared angular-refs fixture: ' + root);
  }
  // Refresh only known test input files; preserve installed dependencies.
  cpSync(join(dirname(fileURLToPath(import.meta.url)), 'project'), root, { recursive: true });
  for (const binary of binaries) {
    for (const provider of providers) {
      console.log(`\nGate: ${root}, ${binary}, ${provider}`);
      const result = spawnSync(binary, ['--headless', '-i', 'NONE', '-u', 'test/minimal_init.lua', '-l', 'test/live/run.lua'], {
        stdio: 'inherit', timeout: 180000,
        env: { ...process.env, AR_TEST_ROOT: root, AR_TS_PROVIDER: provider },
      });
      if (result.status !== 0) process.exit(result.status || 1);
    }
  }
}
