#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-runner-test-'));
const installed = path.join(temporary, 'bin');
fs.mkdirSync(installed);
const reader = path.join(installed, 'moonc-reader');
fs.copyFileSync(path.join(here, '../runner.mjs'), reader);
fs.chmodSync(reader, 0o755);
const native = path.join(installed, 'moonc-reader-native');
fs.writeFileSync(native, `#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const manifest = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
for (const p of manifest.packages) if (!fs.existsSync(p.artifact)) throw new Error('artifact disappeared before extraction');
if (process.env.RUNNER_TEST_MUTATE === 'source') fs.appendFileSync(manifest.sources[0].path, '\\n');
if (process.env.RUNNER_TEST_MUTATE === 'added') fs.writeFileSync(path.join(manifest.packages[0].source_root, 'new_source.mbt'), 'fn added() -> Int { 7 }\\n');
if (process.env.RUNNER_TEST_MUTATE === 'config') fs.appendFileSync(path.join(manifest.packages[0].source_root, 'moon.pkg'), '\\n');
process.stdout.write(JSON.stringify({schema_version:1, compiler_version:manifest.compiler_version, position_encoding:'unicode-scalar',sources:manifest.sources,types:[],symbols:[],facts:[],packages:manifest.packages}));
`);
fs.chmodSync(native, 0o755);
function invoke(project, extra = [], env = {}) {
  return spawnSync(reader, ['--project', project, ...extra], {encoding:'utf8', env:{...process.env,...env}, timeout:90000, maxBuffer:16*1024*1024});
}
function success(result) {
  assert.equal(result.status, 0, result.error?.message || result.stderr);
  return JSON.parse(result.stdout);
}
try {
  const project = path.join(temporary, 'project');
  fs.mkdirSync(project);
  fs.writeFileSync(path.join(project, 'moon.mod'), 'name = "runner/fixture"\nversion = "0.0.1"\npreferred_target = "wasm"\n');
  fs.writeFileSync(path.join(project, 'moon.pkg'), '');
  fs.writeFileSync(path.join(project, 'main.mbt'), '///|\npub fn answer() -> Int { 1 }\n');
  fs.writeFileSync(path.join(project, 'main_wbtest.mbt'), '///|\ntest { inspect(answer(), content="1") }\n');
  fs.writeFileSync(path.join(project, 'main_test.mbt'), '///|\ntest { inspect(1, content="1") }\n');
  const snapshot = success(invoke(project));
  assert.deepEqual(snapshot.packages.map(p=>p.import_kind).sort(), ['bbtest','normal','wbtest']);
  assert.equal(snapshot.sources.length, 3);
  for (const pkg of snapshot.packages) {
    assert.match(pkg.key, /@wasm:(normal|wbtest|bbtest)$/);
    assert.equal(fs.existsSync(pkg.artifact), false, 'owned temp was not cleaned up');
  }
  const whitebox = success(invoke(path.join(project, 'main_wbtest.mbt')));
  assert.deepEqual(whitebox.packages.map(p=>p.import_kind), ['wbtest']);
  assert.equal(whitebox.sources.length, 2);
  const blackbox = success(invoke(path.join(project, 'main_test.mbt')));
  assert.deepEqual(blackbox.packages.map(p=>p.import_kind), ['bbtest']);
  const script = path.join(temporary, 'standalone.mbtx');
  fs.writeFileSync(script, 'fn main { println("hello") }\n');
  const standalone = success(invoke(script));
  assert.equal(standalone.sources[0].path, fs.realpathSync(script));
  const normalFile = success(invoke(path.join(project, 'main.mbt')));
  assert.deepEqual(normalFile.packages.map(p=>p.import_kind), ['normal']);
  if(process.platform!=='win32') {
    const physical=path.join(temporary,'outside.mbt');
    const logical=path.join(project,'linked.mbt');
    fs.writeFileSync(physical,'pub fn linked() -> Int { answer() }\n');
    fs.symlinkSync(physical,logical);
    const linked=success(invoke(logical));
    assert.equal(linked.packages[0].name,'runner/fixture','symlink lost module context');
    assert.ok(linked.sources.some(s=>s.path===fs.realpathSync(physical)));
    fs.rmSync(logical);
  }
  const nativeTarget = success(invoke(project, ['--target','native']));
  assert.ok(nativeTarget.packages.every(p=>p.key.includes('@native:')));
  const workspace = path.join(temporary, 'workspace');
  fs.mkdirSync(workspace);
  fs.writeFileSync(path.join(workspace,'moon.work'), 'members = ["a", "b"]\n');
  for (const member of ['a','b']) {
    const directory = path.join(workspace,member);
    fs.mkdirSync(directory);
    fs.writeFileSync(path.join(directory,'moon.mod'), `name = "runner/${member}"\nversion = "0.0.1"\npreferred_target = "wasm"\n`);
    fs.writeFileSync(path.join(directory,'moon.pkg'), '');
    fs.writeFileSync(path.join(directory,'main.mbt'), `pub fn ${member}() -> Int { 1 }\n`);
  }
  const workspaceResult = success(invoke(workspace));
  assert.deepEqual([...new Set(workspaceResult.packages.map(p=>p.name.replace(/_blackbox_test$/, '')))].sort(), ['runner/a','runner/b']);
  const memberResult = success(invoke(path.join(workspace,'a')));
  assert.ok(memberResult.packages.every(p=>p.name.startsWith('runner/a')));
  const plainScript = path.join(temporary, 'standalone.mbt');
  fs.writeFileSync(plainScript, 'fn main { println("hello") }\n');
  assert.equal(success(invoke(plainScript)).sources[0].path, fs.realpathSync(plainScript));
  const stale = invoke(project, [], {RUNNER_TEST_MUTATE:'source'});
  assert.notEqual(stale.status, 0);
  assert.equal(stale.stdout, '');
  assert.match(stale.stderr, /changed during semantic extraction/);
  const configChange = invoke(project, [], {RUNNER_TEST_MUTATE:'config'});
  assert.notEqual(configChange.status, 0);
  assert.equal(configChange.stdout, '');
  assert.match(configChange.stderr, /changed during semantic extraction/);
  const added = invoke(project, [], {RUNNER_TEST_MUTATE:'added'});
  assert.notEqual(added.status, 0);
  assert.equal(added.stdout, '');
  assert.match(added.stderr, /membership changed/);
  fs.rmSync(path.join(project,'new_source.mbt'));
  fs.appendFileSync(path.join(project, 'main.mbt'), '\nfn broken() -> Int { "wrong" }\n');
  const failed = invoke(project);
  assert.notEqual(failed.status, 0);
  assert.equal(failed.stdout, '');
  assert.match(failed.stderr, /moon failed/);
  const fakeHome = path.join(temporary, 'fake-toolchain');
  fs.mkdirSync(path.join(fakeHome,'bin'), {recursive:true});
  fs.writeFileSync(path.join(fakeHome,'bin/moon'), '#!/bin/sh\necho should-not-run >&2\nexit 99\n', {mode:0o755});
  fs.writeFileSync(path.join(fakeHome,'bin/moonc'), '#!/bin/sh\necho unsupported-version\n', {mode:0o755});
  const incompatible = invoke(project, [], {MOON_HOME:fakeHome});
  assert.notEqual(incompatible.status, 0);
  assert.equal(incompatible.stdout, '');
  assert.match(incompatible.stderr, /Unsupported compiler version/);
  assert.doesNotMatch(incompatible.stderr, /should-not-run/);
  console.log('Runner checks passed: fresh artifacts, package views, target selection, workspaces, standalone input, stale inputs, failed checks, version gate, cleanup.');
} finally {
  fs.rmSync(temporary, {recursive:true,force:true});
}
