#!/usr/bin/env node
// Build only MoonGrep's own MoonBit reader with the installed toolchain.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
if (process.argv.length !== 2) {
  if (process.argv[2] === '--help') {
    console.log('Usage: node scripts/build-moonc-reader.mjs\nRequires the installed MoonBit toolchain and Node.js. No OCaml or compiler sources.');
    process.exit(0);
  }
  throw new Error('The pure MoonBit reader takes no compiler-source or OCaml build options.');
}
const out = path.join(root, '_build/semantic-reader');
fs.mkdirSync(out, {recursive:true});
fs.rmSync(path.join(out, 'moonc-reader'), {force:true});
const moon = process.env.MOON_HOME ? path.join(process.env.MOON_HOME, 'bin', 'moon') : 'moon';
const result = spawnSync(moon, ['build', 'cmd/semantic-reader', '--target', 'native'], {cwd:root, stdio:'inherit'});
if (result.error || result.status !== 0) throw new Error(result.error?.message || 'MoonBit reader build failed');
const executable = path.join(root, '_build/native/debug/build/moonbit-community/moongrep/cmd/semantic-reader/semantic-reader.exe');
fs.copyFileSync(executable, path.join(out, 'moonc-reader-native' + (process.platform === 'win32' ? '.exe' : '')));
fs.chmodSync(path.join(out, 'moonc-reader-native' + (process.platform === 'win32' ? '.exe' : '')), 0o755);
const check = spawnSync(process.execPath, [path.join(root, 'tools/moonc-reader/compatibility.mjs'), out], {cwd:root, encoding:'utf8', maxBuffer:64*1024*1024});
if (check.error || check.status !== 0) throw new Error(check.error?.message || check.stderr || 'Nightly compatibility check failed');
process.stderr.write(check.stdout);
fs.writeFileSync(path.join(out, 'build.json'), JSON.stringify({implementation:'MoonBit', compatibility:check.stdout.trim()}, null, 2)+'\n');
fs.copyFileSync(path.join(root, 'tools/moonc-reader/runner.mjs'), path.join(out, 'moonc-reader'));
fs.chmodSync(path.join(out, 'moonc-reader'), 0o755);
console.log(path.join(out, 'moonc-reader'));
