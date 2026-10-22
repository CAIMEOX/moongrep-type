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
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-semantic-rules-'));
const project = path.join(temp, 'project');
const indexPath = path.join(temp, 'index.json');
const custom = path.join(temp, 'custom.yaml');
const names = [
  'prefer_array_comprehension', 'prefer_filter_map_comprehension', 'prefer_iter_comprehension',
  'avoid_collect_for_count', 'discarded_array_map', 'consumed_iterator', 'array_map_fusion',
];
const semanticIds = new Set(names.map(name => `moonbitlang/${name}`));

function run(command, args, success = true) {
  const result = spawnSync(command, args, {
    cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 64 * 1024 * 1024,
    env: {...process.env, NO_COLOR: '1'},
  });
  if (success) assert.equal(result.status, 0, result.error?.message || result.stderr);
  return result;
}
function records(text) { return text.trim().split('\n').filter(Boolean).map(JSON.parse); }
function extract() {
  const snapshot = JSON.parse(run(reader, ['--project', project]).stdout);
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));
  return snapshot;
}
function lint(extra = [], target = project) {
  return run(cli, ['lint', target, '--semantic-index', indexPath, '--json', ...extra]);
}
function semanticFindings(result) {
  return records(result.stdout).filter(record => record.type === 'finding' && semanticIds.has(record.rule_id));
}
function sourceFor(snapshot, finding) {
  return snapshot.sources.find(source => source.path === fs.realpathSync(finding.file));
}
function functionAt(snapshot, finding) {
  const text = sourceFor(snapshot, finding).text.split('\n').slice(0, finding.range.start.line).join('\n');
  return [...text.matchAll(/^pub fn(?:\[[^\n]*?\])? (\w+)\(/gm)].at(-1)?.[1];
}
function slice(snapshot, finding) {
  const lines = sourceFor(snapshot, finding).text.split('\n').map(line => Array.from(line));
  const {start, end} = finding.range;
  if (start.line === end.line) return lines[start.line - 1].slice(start.column - 1, end.column - 1).join('');
  return [lines[start.line - 1].slice(start.column - 1).join(''),
    ...lines.slice(start.line, end.line - 1).map(line => line.join('')),
    lines[end.line - 1].slice(0, end.column - 1).join('')].join('\n');
}
function customRule(guard = '^it$') {
  return `id: custom_count\ndescription: Custom count hint.\nsemantic:\n  check: collect-count\n  patterns:\n    - shape: $(iterator:id).collect().length()\n      guard:\n        $iterator: '${guard}'\n`;
}

try {
  fs.cpSync(path.join(root, 'examples/semantic-rules'), project, {recursive: true});
  run('moon', ['build', '--target', 'native']);
  const snapshot = extract();
  const result = lint();
  assert.equal(result.stderr, '', 'complete checked examples need no semantic warnings');
  const findings = semanticFindings(result);
  const expected = {
    prefer_array_comprehension: ['builder_plain', 'builder_filter', 'builder_indexed', 'builder_range', 'unicode_builder', 'generic_builder'],
    prefer_filter_map_comprehension: ['filter_map_if', 'filter_map_option'],
    prefer_iter_comprehension: ['iter_pipeline', 'collected_pipeline', 'generic_iter'],
    avoid_collect_for_count: ['count_without_array', 'count_without_array_alias', 'unicode_count'],
    discarded_array_map: ['discard_map'],
    consumed_iterator: ['reuse_iterator', 'reuse_after_ignored_count'],
    array_map_fusion: ['map_fusion'],
  };
  for (const name of names) {
    assert.deepEqual(findings.filter(f => f.rule_id === `moonbitlang/${name}`).map(f => functionAt(snapshot, f)), expected[name], name);
  }
  assert.equal(findings.length, 18);
  assert.ok(findings.every(f => !f.file.endsWith('/negative.mbt')));
  for (const finding of findings) {
    assert.equal(finding.matched_source, slice(snapshot, finding), 'whole-file Unicode source mapping');
    assert.ok(finding.source_context.some(line => line.is_match));
  }
  const unicode = findings.find(f => functionAt(snapshot, f) === 'unicode_count');
  const line = sourceFor(snapshot, unicode).text.split('\n')[unicode.range.start.line - 1];
  assert.equal(unicode.range.start.column, Array.from(line.slice(0, line.indexOf('items.collect'))).length + 1);

  assert.equal(semanticFindings(run(cli, ['lint', project, '--json'])).length, 0, 'syntax-only lint stays available');
  const disabled = semanticFindings(lint(['--disable', 'moonbitlang/prefer_array_comprehension']));
  assert.equal(disabled.length, 12);
  const readable = run(cli, ['lint', project, '--semantic-index', indexPath]).stdout;
  assert.ok(readable.includes('rule: moonbitlang/prefer_array_comprehension\ndescription:'));
  assert.ok(readable.includes('source:\n'));

  fs.writeFileSync(custom, customRule());
  const customArgs = ['scan', project, '--rule', custom, '--semantic-index', indexPath, '--json'];
  const customHits = records(run(cli, customArgs).stdout);
  assert.equal(customHits.length, 1);
  assert.equal(customHits[0].rule_id, 'custom_count');
  assert.equal(customHits[0].description, 'Custom count hint.');
  fs.writeFileSync(custom, customRule('^never$'));
  assert.equal(run(cli, customArgs).stdout, '', 'YAML regex guard filters semantic candidates');
  fs.writeFileSync(custom, customRule());
  const missing = run(cli, ['scan', project, '--rule', custom, '--json'], false);
  assert.equal(missing.status, 2);
  assert.equal(JSON.parse(missing.stderr).category, 'usage');
  assert.match(missing.stderr, /--semantic-index/);
  fs.writeFileSync(custom, customRule().replace('check: collect-count', 'check: arbitrary-script'));
  const invalid = run(cli, customArgs, false);
  assert.equal(invalid.status, 5);
  assert.match(invalid.stderr, /unknown semantic.check/);

  // Loss of evidence must be visible, not silently become a definite match.
  const altered = structuredClone(snapshot);
  const count = findings.find(f => functionAt(snapshot, f) === 'count_without_array');
  altered.facts = altered.facts.filter(f => !(f.location?.file === fs.realpathSync(count.file)
    && JSON.stringify({start: f.location.start, end: f.location.end}) === JSON.stringify(count.range)));
  fs.writeFileSync(indexPath, JSON.stringify(altered));
  const unavailable = lint();
  assert.equal(semanticFindings(unavailable).filter(f => functionAt(snapshot, f) === 'count_without_array').length, 0);
  assert.ok(records(unavailable.stderr).some(w => w.category === 'semantic' && w.rule_id === 'moonbitlang/avoid_collect_for_count'));
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));

  // Multiple build views coexist in one index. The selected view controls both
  // exact-range lookup and binding-use analysis.
  fs.writeFileSync(path.join(project, 'probe_wbtest.mbt'), 'test { assert_eq(builder_plain([1]), [2]) }\n');
  extract();
  assert.equal(semanticFindings(lint()).length, 18);
  assert.equal(semanticFindings(lint(['--semantic-view', 'wbtest'], path.join(project, 'collections.mbt'))).length, 18);
  const blackbox = path.join(project, 'probe_test.mbt');
  fs.writeFileSync(blackbox, 'test { let it = [1, 2].iter(); assert_eq(it.collect().length(), 2) }\n');
  extract();
  const blackboxResult = lint(['--semantic-view', 'bbtest'], blackbox);
  assert.equal(blackboxResult.stderr, '');
  assert.deepEqual(semanticFindings(blackboxResult).map(f => f.rule_id), ['moonbitlang/avoid_collect_for_count']);

  fs.appendFileSync(path.join(project, 'collections.mbt'), '\n// changed after checking\n');
  const stale = run(cli, ['lint', project, '--semantic-index', indexPath, '--json'], false);
  assert.equal(stale.status, 6);
  assert.equal(stale.stdout, '');
  assert.equal(JSON.parse(stale.stderr).category, 'scan_input');
  console.log('semantic YAML integration passed: 7 checks, 18 findings, negative examples, custom YAML/guards, disables, normal/wbtest/bbtest views, missing evidence, and stale-source rejection');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
