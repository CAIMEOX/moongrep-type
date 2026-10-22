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
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-theorems-'));
const project = path.join(temp, 'project');
const indexPath = path.join(temp, 'index.json');
const files = ['collections.mbt', 'option_fusion.mbt', 'identities.mbt'];
const expected = {
  array_filter_count: ['collection_array_count', 'collection_generic_count', 'collection_raising_count', 'collection_count_factory'],
  iter_filter_count: ['collection_iter_count'],
  iter_filter_next: ['collection_first'],
  iter_find_first_exists: [
    'collection_exists', 'collection_absent', 'collection_raising_exists',
    'collection_is_none', 'collection_is_some', 'collection_is_qualified',
    'collection_is_raising', 'collection_is_generic', 'collection_is_factory', 'collection_is_unicode',
  ],
  iter_map_flatten: ['collection_flatten', 'collection_flatten_factory'],
  option_map_fusion: ['theorem_option_map', 'theorem_option_map_raising', 'theorem_option_map_return'],
  result_map_fusion: ['theorem_result_map'],
  result_map_err_fusion: ['theorem_result_map_err'],
  option_bind_map: ['theorem_option_bind_map', 'theorem_option_bind_raise', 'theorem_option_bind_mutation'],
  result_bind_map: ['theorem_result_bind_map'],
  result_map_flatten: ['theorem_result_map_flatten', 'theorem_result_flatten_factory'],
  option_filter_fusion: ['theorem_option_filter'],
  option_map_default: ['theorem_option_default'],
  option_map_identity: ['identity_option_map'],
  result_map_identity: ['identity_result_map', 'identity_result_generic'],
  option_bind_identity: ['identity_option_bind', 'identity_unicode'],
  result_bind_identity: ['identity_result_bind'],
  option_unwrap_some: ['identity_some_unwrap'],
  result_unwrap_ok: ['identity_ok_unwrap'],
  result_unwrap_err: ['identity_err_unwrap'],
};
const ids = new Set(Object.keys(expected).map(name => `moonbitlang/${name}`));
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
function lint(file, extra = []) {
  return run(cli, ['lint', path.join(project, file), '--semantic-index', indexPath, '--json', ...extra]);
}
function hits(result) { return records(result.stdout).filter(r => r.type === 'finding' && ids.has(r.rule_id)); }
function sourceFor(snapshot, finding) {
  return snapshot.sources.find(s => s.path === fs.realpathSync(finding.file));
}
function functionAt(snapshot, finding) {
  const before = sourceFor(snapshot, finding).text.split('\n').slice(0, finding.range.start.line).join('\n');
  return [...before.matchAll(/^pub fn(?:\[[^\n]*?\])? (\w+)\(/gm)].at(-1)?.[1];
}
function slice(snapshot, finding) {
  const lines = sourceFor(snapshot, finding).text.split('\n').map(line => Array.from(line));
  const {start, end} = finding.range;
  if (start.line === end.line) return lines[start.line - 1].slice(start.column - 1, end.column - 1).join('');
  return [lines[start.line - 1].slice(start.column - 1).join(''),
    ...lines.slice(start.line, end.line - 1).map(line => line.join('')),
    lines[end.line - 1].slice(0, end.column - 1).join('')].join('\n');
}
function checkFindings(snapshot, extra = []) {
  const findings = files.flatMap(file => {
    const result = lint(file, extra);
    assert.equal(result.stderr, '', `${file}: complete examples need no missing/ambiguous evidence warnings`);
    return hits(result);
  });
  for (const [name, functions] of Object.entries(expected)) {
    assert.deepEqual(findings.filter(f => f.rule_id === `moonbitlang/${name}`).map(f => functionAt(snapshot, f)), functions, name);
  }
  assert.equal(findings.length, 40);
  for (const finding of findings) {
    assert.equal(finding.matched_source, slice(snapshot, finding), 'exact Unicode scalar source range');
    assert.ok(finding.source_context.some(line => line.is_match));
  }
  const unicode = findings.find(f => functionAt(snapshot, f) === 'identity_unicode');
  const line = sourceFor(snapshot, unicode).text.split('\n')[unicode.range.start.line - 1];
  assert.ok(line.indexOf('🚀') >= 0 && line.indexOf('🚀') < line.indexOf('value.bind'));
  assert.equal(unicode.range.start.column, Array.from(line.slice(0, line.indexOf('value.bind'))).length + 1);
  const presence = findings.find(f => functionAt(snapshot, f) === 'collection_is_unicode');
  const presenceLine = sourceFor(snapshot, presence).text.split('\n')[presence.range.start.line - 1];
  assert.ok(presenceLine.indexOf('🚀') >= 0 && presenceLine.indexOf('🚀') < presenceLine.indexOf('it.find_first'));
  assert.equal(presence.range.start.column, Array.from(presenceLine.slice(0, presenceLine.indexOf('it.find_first'))).length + 1);
  return findings;
}

try {
  fs.cpSync(path.join(root, 'examples/semantic-theorems'), project, {
    recursive: true,
    filter: source => !['_build', 'target', '.mooncakes'].includes(path.basename(source)),
  });
  run('moon', ['build', '--target', 'native']);
  let snapshot = extract();
  const findings = checkFindings(snapshot);
  const text = run(cli, ['lint', path.join(project, 'collections.mbt'), '--semantic-index', indexPath]).stdout;
  assert.match(text, /rule: moonbitlang\/array_filter_count\ndescription:/);
  assert.match(text, /source:\n/);
  assert.equal(hits(lint('collections.mbt', ['--disable', 'moonbitlang/array_filter_count'])).length, 14);
  assert.equal(hits(run(cli, ['lint', path.join(project, 'identities.mbt'), '--json'])).length, 0);

  // Every check also runs through a caller-owned YAML rule and ordinary scan.
  // This catches registration drift between builtins, parser, and dispatcher.
  for (const [name, functions] of Object.entries(expected)) {
    const yaml = fs.readFileSync(path.join(root, 'internal/rule/lintrules/moonbitlang', `${name}.yaml`), 'utf8');
    const custom = path.join(temp, `${name}.yaml`);
    fs.writeFileSync(custom, yaml.replace(`id: ${name}`, 'id: custom_theorem'));
    const selected = files.flatMap(file => {
      const result = run(cli, ['scan', path.join(project, file), '--rule', custom, '--semantic-index', indexPath, '--json']);
      assert.equal(result.stderr, '', name);
      return records(result.stdout).filter(r => r.type === 'finding');
    });
    assert.deepEqual(selected.map(f => functionAt(snapshot, f)), functions, `custom YAML ${name}`);
    assert.ok(selected.every(f => f.rule_id === 'custom_theorem'));
  }

  // Missing exact evidence is a diagnostic, never a theorem instance.
  for (const name of ['array_filter_count', 'option_map_fusion', 'option_map_identity']) {
    const finding = findings.find(f => f.rule_id === `moonbitlang/${name}`);
    const broken = structuredClone(snapshot);
    broken.facts = broken.facts.filter(f => !(f.location?.file === fs.realpathSync(finding.file)
      && JSON.stringify({start: f.location.start, end: f.location.end}) === JSON.stringify(finding.range)));
    fs.writeFileSync(indexPath, JSON.stringify(broken));
    const result = lint(path.basename(finding.file));
    assert.ok(!hits(result).some(f => f.rule_id === finding.rule_id && functionAt(snapshot, f) === functionAt(snapshot, finding)));
    assert.ok(records(result.stderr).some(w => w.category === 'semantic' && w.rule_id === finding.rule_id));
  }
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));

  fs.writeFileSync(path.join(project, 'view_wbtest.mbt'), 'test { assert_eq(identity_option_map(Some(1)), Some(1)) }\n');
  snapshot = extract();
  checkFindings(snapshot);
  checkFindings(snapshot, ['--semantic-view', 'wbtest']);
  const blackbox = 'view_test.mbt';
  fs.writeFileSync(path.join(project, blackbox), 'test { let value : Int? = Some(1); assert_eq(value.map(x => x), Some(1)) }\n');
  extract();
  const bb = lint(blackbox, ['--semantic-view', 'bbtest']);
  assert.equal(bb.stderr, '');
  assert.deepEqual(hits(bb).map(f => f.rule_id), ['moonbitlang/option_map_identity']);

  // Compiler-inserted conversions share the source call's exact range. Keep
  // them in the index while selecting the operation's pre-conversion evidence.
  fs.appendFileSync(path.join(project, 'moon.pkg'), '\nimport { "moonbitlang/core/debug" }\n');
  const coercions = 'coercions.mbt';
  fs.writeFileSync(path.join(project, coercions), `
///|
pub fn implicit_option(value : Int?) -> Unit raise {
  @debug.debug_inspect(value.map(x => x), content="unused")
}
///|
pub fn implicit_result(value : Result[Int, String]) -> Unit raise {
  @debug.debug_inspect(value.map(x => x), content="unused")
}
///|
pub fn implicit_array_trait(xs : Array[Int]) -> Unit raise {
  @debug.debug_inspect(xs.map(x => x + 1).map(x => x * 2), content="unused")
}
///|
pub fn view_size(xs : ArrayView[Int]) -> Int { xs.length() }
///|
pub fn implicit_array_view(xs : Array[Int]) -> Int {
  view_size(xs.map(x => x + 1).map(x => x * 2))
}
///|
pub fn explicit_trait(value : Int?) -> &@debug.Debug {
  value.map(x => x) as &@debug.Debug
}
///|
pub fn actual_view_method(xs : ArrayView[Int]) -> Array[Int] {
  xs.map(x => x + 1).map(x => x * 2)
}
`);
  snapshot = extract();
  for (const view of ['normal', 'wbtest']) {
    const result = lint(coercions, ['--semantic-view', view]);
    assert.equal(result.stderr, '', 'implicit conversions are not ambiguous source operations');
    const findings = records(result.stdout).filter(r => r.type === 'finding');
    assert.deepEqual(findings.map(f => [functionAt(snapshot, f), f.rule_id]).sort(), [
      ['implicit_option', 'moonbitlang/option_map_identity'],
      ['implicit_result', 'moonbitlang/result_map_identity'],
      ['implicit_array_trait', 'moonbitlang/array_map_fusion'],
      ['implicit_array_view', 'moonbitlang/array_map_fusion'],
      ['explicit_trait', 'moonbitlang/option_map_identity'],
    ].sort());
    for (const finding of findings) {
      assert.equal(finding.matched_source, slice(snapshot, finding));
      if (functionAt(snapshot, finding) === 'explicit_trait') continue;
      const exact = snapshot.facts.filter(f => f.location?.file === fs.realpathSync(finding.file)
        && f.package.endsWith(':' + view) && f.kind === 'expression' && f.node_kind.startsWith('Texpr_')
        && JSON.stringify({start: f.location.start, end: f.location.end}) === JSON.stringify(finding.range));
      const wrapper = functionAt(snapshot, finding) === 'implicit_array_view' ? 'Texpr_array_as_view' : 'Texpr_as';
      assert.deepEqual(exact.map(f => f.node_kind).sort(), ['Texpr_apply', wrapper].sort());
      assert.equal(exact.find(f => f.node_kind === wrapper).details.implicit, true);
      assert.notEqual(exact[0].type_id, exact[1].type_id, 'raw converted and original types remain distinct');
    }
  }
  assert.ok(snapshot.facts.some(f => f.location?.file.endsWith('/coercions.mbt')
    && f.node_kind === 'Texpr_as' && f.details.implicit === false), 'explicit conversions remain explicit');

  // The standalone map-fusion entrypoint uses the same evidence selection.
  const normalSnapshot = {...snapshot, facts: snapshot.facts.filter(f => f.package.endsWith(':normal'))};
  fs.writeFileSync(indexPath, JSON.stringify(normalSnapshot));
  const fusion = JSON.parse(run(cli, ['map-fusion', '--index', indexPath, '--json']).stdout);
  const report = fusion.files.find(f => f.file.endsWith('/coercions.mbt')).report;
  assert.equal(report.candidates.length, 2);
  assert.deepEqual(report.skipped.map(s => s.reason), ['not_standard_array_map']);
  for (const candidate of report.candidates) {
    assert.equal(snapshot.facts.find(f => f.id === candidate.outer_call.fact_id).node_kind, 'Texpr_apply');
  }
  fs.writeFileSync(indexPath, JSON.stringify(snapshot));

  fs.appendFileSync(path.join(project, 'collections.mbt'), '\n// changed after indexing\n');
  const stale = run(cli, ['lint', path.join(project, 'collections.mbt'), '--semantic-index', indexPath, '--json'], false);
  assert.equal(stale.status, 6);
  assert.equal(stale.stdout, '');
  assert.equal(JSON.parse(stale.stderr).category, 'scan_input');
  console.log('theorem integration passed: 20 checks, 40 findings, presence patterns and exclusions, implicit trait/view conversions, explicit casts, both rule entrypoints, negative cases, YAML, source mapping, three views, missing evidence, stale sources');
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
