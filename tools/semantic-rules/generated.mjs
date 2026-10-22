#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const reader = path.resolve(process.argv[2] || path.join(root, '_build/semantic-reader/moonc-reader'));
const cli = path.join(root, '_build/native/debug/build/moonbit-community/moongrep/moongrep.exe');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-generated-'));
const indexPath = path.join(temp, 'index.json');
function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 64 * 1024 * 1024,
    env: {...process.env, NO_COLOR: '1'},
  });
  assert.equal(result.status, 0, result.error?.message || result.stderr);
  return result;
}
function records(text) { return text.trim().split('\n').filter(Boolean).map(JSON.parse); }
function lint(view) {
  const result = run(cli, ['lint', path.join(temp, 'probe.mbt'), '--semantic-index', indexPath,
    '--semantic-view', view, '--json']);
  assert.equal(result.stderr, '', 'generated bodies must not cause semantic warnings');
  return records(result.stdout).filter(r => r.type === 'finding');
}

try {
  fs.writeFileSync(path.join(temp, 'moon.mod'), 'name = "moongrep/generated-probe"\n');
  fs.writeFileSync(path.join(temp, 'moon.pkg'), 'import { "moonbitlang/core/debug" }\n');
  fs.writeFileSync(path.join(temp, 'probe.mbt'), `///|
pub struct Derived {
  values : Array[Int]
} derive(Eq, Compare, Debug, Show, Hash, ToJson, FromJson)

///|
pub struct Manual {
  value : Int?
}

///|
pub impl Eq for Manual with fn equal(self, other) {
  self.value.map(x => x) == other.value
}

///|
pub impl Show for Manual with fn output(self, logger) {
  logger.write_object(self.value)
}

///|
pub fn implicit_debug(value : Int?) -> Unit raise {
  @debug.debug_inspect(value.map(x => x), content="unused")
}

///|
pub fn manual_array(xs : Array[Int]) -> Array[Int] {
  xs.map(x => x + 1).map(x => x * 2)
}
`);
  fs.writeFileSync(path.join(temp, 'view_wbtest.mbt'), 'test { assert_eq(1, 1) }\n');
  run('moon', ['build', '--target', 'native']);
  const snapshot = JSON.parse(run(reader, ['--project', temp]).stdout);
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));
  for (const view of ['normal', 'wbtest']) {
    const facts = snapshot.facts.filter(f => f.package.endsWith(':' + view));
    const derived = facts.filter(f => f.node_kind === 'Timpl_fun_decl' && f.details.generated_top_level);
    assert.equal(derived.length, 7, 'all seven derive implementations carry provenance');
    for (const declaration of derived) {
      assert.ok(facts.filter(f => f.details.owner === declaration.details.owner)
        .every(f => f.details.generated_top_level === true), 'derive provenance reaches every child fact');
      assert.ok(facts.some(f => f.node_kind === 'Tdecl_type_decl' && !f.details.generated_top_level
        && JSON.stringify(f.location) === JSON.stringify(declaration.location)),
      'generated implementations reuse the authored type declaration range');
    }
    const manual = facts.filter(f => f.node_kind === 'Timpl_fun_decl' && !f.details.generated_top_level
      && f.location?.file.endsWith('/probe.mbt'));
    assert.equal(manual.length, 4, 'handwritten impls and functions remain authored');
    for (const declaration of manual) {
      assert.ok(facts.filter(f => f.details.owner === declaration.details.owner)
        .every(f => f.details.generated_top_level === false));
    }
    assert.ok(facts.some(f => f.node_kind === 'Texpr_as' && f.details.implicit === true
      && f.details.generated_top_level === false), 'implicit expression conversion is not a derived body');
    assert.deepEqual(lint(view).map(f => f.rule_id).sort(), [
      'moonbitlang/option_map_identity', 'moonbitlang/option_map_identity', 'moonbitlang/array_map_fusion',
    ].sort());
  }

  // A generated expression may reuse an authored range. It must not replace or
  // conflict with the authored evidence, even when it belongs to another view.
  const normal = {...snapshot, facts: snapshot.facts.filter(f => f.package.endsWith(':normal'))};
  const call = normal.facts.filter(f => f.node_kind === 'Texpr_apply'
    && f.location?.start.line === 28 && f.location.start.column === 3)
    .sort((left, right) => right.location.end.column - left.location.end.column)[0];
  assert.ok(call, 'outer handwritten map call');
  const overlap = structuredClone(call);
  overlap.id = Math.max(...snapshot.facts.map(f => f.id)) + 1;
  overlap.package = overlap.package.replace(':normal', ':wbtest');
  overlap.details.generated_top_level = true;
  normal.facts.push(overlap);
  fs.writeFileSync(indexPath, JSON.stringify(normal));
  const fusion = JSON.parse(run(cli, ['map-fusion', '--index', indexPath, '--json']).stdout);
  const report = fusion.files.find(f => f.file.endsWith('/probe.mbt')).report;
  assert.equal(report.candidates.length, 1);
  assert.equal(report.skipped.length, 0);

  // Exercise the no-authored-facts boundary with a real checked source and
  // symbol graph, without editing the checked program or deleting raw facts.
  for (const fact of normal.facts) {
    if (fact.details.owner === call.details.owner) fact.details.generated_top_level = true;
  }
  fs.writeFileSync(indexPath, JSON.stringify(normal));
  assert.deepEqual(lint('normal').map(f => f.rule_id), [
    'moonbitlang/option_map_identity', 'moonbitlang/option_map_identity',
  ]);
  console.log('generated provenance integration passed: seven derives, manual impls, implicit conversions, overlapping ranges, generated-only evidence, two views');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
