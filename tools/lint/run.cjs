const path = require('node:path');
const { spawnSync } = require('node:child_process');
const entry = path.join(path.dirname(require.resolve('eslint/package.json')), 'bin/eslint.js');
const result = spawnSync(process.execPath, [entry, ...process.argv.slice(2)], { stdio: 'inherit' });
if (result.error) throw result.error;
process.exitCode = result.status === null ? 1 : result.status;
