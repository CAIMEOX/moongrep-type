#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const reader = path.resolve(process.argv[2] || path.join(root, '_build/semantic-reader/moonc-reader'));
const executable = path.join(root, '_build/native/debug/build/moonbit-community/moongrep/cmd/map-fusion/map-fusion.exe');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-map-fusion-'));
const project = path.join(temp, 'project');
const indexPath = path.join(temp, 'index.json');

function run(command, args, success = true) {
  const result = spawnSync(command, args, {
    cwd: root, encoding: 'utf8', timeout: 90000, maxBuffer: 32 * 1024 * 1024,
  });
  if (success) assert.equal(result.status, 0, result.error?.message || result.stderr);
  return result;
}

function extract() {
  const snapshot = JSON.parse(run(reader, ['--project', project]).stdout);
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));
  return snapshot;
}

function analyze() {
  return JSON.parse(run(executable, ['--index', indexPath]).stdout);
}

function sourceSlice(snapshot, location) {
  const source = snapshot.sources.find(source => source.path === location.file);
  assert.ok(source, 'every finding must point to an indexed source');
  const lines = source.text.split('\n').map(line => Array.from(line));
  const {start, end} = location;
  if (start.line === end.line) return lines[start.line - 1].slice(start.column - 1, end.column - 1).join('');
  return [
    lines[start.line - 1].slice(start.column - 1).join(''),
    ...lines.slice(start.line, end.line - 1).map(line => line.join('')),
    lines[end.line - 1].slice(0, end.column - 1).join(''),
  ].join('\n');
}

function enclosingFunction(text, location) {
  const preceding = text.split('\n').slice(0, location.start.line).join('\n');
  return [...preceding.matchAll(/^pub fn(?:\[[^\n]*?\])? (\w+)\(/gm)].at(-1)?.[1];
}

try {
  fs.cpSync(path.join(here, 'fixture'), project, {recursive: true});
  run('moon', ['build', 'cmd/map-fusion', '--target', 'native']);
  const snapshot = extract();
  const output = analyze();
  assert.equal(output.compiler_version, snapshot.compiler_version);
  assert.equal(output.position_encoding, 'unicode-scalar');
  const source = snapshot.sources.find(source => source.path.endsWith('/maps.mbt'));
  const report = output.files.find(file => file.file === source.path).report;
  const names = report.candidates.map(candidate => enclosingFunction(source.text, candidate.location));
  assert.deepEqual(names, ['lambdas', 'generic', 'named', 'multiline', 'triple', 'triple', 'effects', 'factories']);
  assert.deepEqual(report.skipped.map(skipped => [enclosingFunction(source.text, skipped.location), skipped.reason]), [
    ['throwing', 'callback_requires_sync_non_raising_unary_function'],
    ['optional', 'not_standard_array_map'],
    ['lazy_maps', 'not_standard_array_map'],
    ['lookalike', 'not_standard_array_map'],
  ]);
  const facts = new Map(snapshot.facts.map(fact => [fact.id, fact]));
  for (const candidate of report.candidates) {
    assert.equal(candidate.status, 'requires_review');
    assert.ok(!('replacement' in candidate) && !('edits' in candidate));
    assert.deepEqual(candidate.map_symbol.identity, {
      kind: 'method', self_type: {kind: 'named', package: 'moonbitlang/core/builtin', name: 'Array'}, name: 'map',
    });
    for (const key of ['receiver', 'inner_call', 'outer_call', 'first_callback', 'second_callback']) {
      const evidence = candidate[key];
      assert.equal(sourceSlice(snapshot, evidence.location), evidence.text, key);
      const fact = facts.get(evidence.fact_id);
      assert.ok(fact, 'evidence must preserve the compiler fact ID');
      assert.deepEqual(evidence.location, fact.location);
      assert.equal(evidence.type_id, fact.type_id);
      assert.equal(candidate.package, fact.package);
      if (key.endsWith('_call')) assert.equal(fact.symbol_id, candidate.map_symbol.id);
    }
  }
  const named = report.candidates[names.indexOf('named')];
  assert.equal(named.first_callback.text, 'to_text');
  assert.equal(named.second_callback.text, 'text_length');
  assert.equal(named.type_flow.input_element.name, 'Int');
  assert.equal(named.type_flow.intermediate_element.name, 'String');
  assert.equal(named.type_flow.output_element.name, 'Int');
  const generic = report.candidates[names.indexOf('generic')];
  const parameters = Object.values(generic.type_flow);
  assert.deepEqual(parameters.map(parameter => parameter.index), [0, 1, 2]);
  assert.equal(new Set(parameters.map(parameter => parameter.owner)).size, 1);
  const multiline = report.candidates[names.indexOf('multiline')];
  const firstLine = source.text.split('\n')[multiline.location.start.line - 1];
  assert.equal(multiline.location.start.column, Array.from(firstLine.slice(0, firstLine.indexOf('xs.map'))).length + 1);

  // The command must reject a snapshot when either its compiler or source differs.
  fs.writeFileSync(indexPath, JSON.stringify({...snapshot, compiler_version: 'incompatible-nightly'}));
  const incompatible = run(executable, ['--index', indexPath], false);
  assert.equal(incompatible.status, 2);
  assert.equal(incompatible.stdout, '');
  assert.match(incompatible.stderr, /compiler mismatch/);
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));
  fs.appendFileSync(path.join(project, 'maps.mbt'), '\n// edited after typechecking\n');
  const stale = run(executable, ['--index', indexPath], false);
  assert.equal(stale.status, 2);
  assert.equal(stale.stdout, '');
  assert.match(stale.stderr, /source differs/);

  // A common source present in both normal and whitebox compilations is explicit
  // ambiguity. The POC must not quietly pick one build view.
  fs.writeFileSync(path.join(project, 'maps.mbt'), source.text);
  fs.writeFileSync(path.join(project, 'probe_wbtest.mbt'), 'test { ignore(0) }\n');
  extract();
  const ambiguous = analyze().files.find(file => file.file.endsWith('/maps.mbt')).report;
  assert.equal(ambiguous.candidates.length, 0);
  assert.equal(ambiguous.skipped.length, 12);
  assert.ok(ambiguous.skipped.every(skipped => skipped.reason === 'ambiguous_semantics'));
  console.log(`map-fusion nightly integration passed: ${report.candidates.length} candidates, ${report.skipped.length} rejected chains; source mapping, stale input, and package ambiguity checked`);
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
