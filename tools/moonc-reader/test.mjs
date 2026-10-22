#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const reader=path.resolve(process.argv[2] || path.join(here,'../../_build/semantic-reader/moonc-reader'));
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'moongrep-reader-test-'));
const project=path.join(temp,'project');
fs.cpSync(path.join(here,'fixtures/project'),project,{recursive:true});
function extract() {
  const r=spawnSync(reader,['--project',project],{encoding:'utf8',timeout:90000,maxBuffer:32*1024*1024});
  assert.equal(r.status,0,r.error?.message||r.stderr);
  return JSON.parse(r.stdout);
}
function sourceSlice(snapshot,fact) {
  if(!fact.location)return null;
  const source=snapshot.sources.find(s=>s.path===fact.location.file);
  assert.ok(source,`missing source ${fact.location.file}`);
  const {start,end}=fact.location;
  const lines=source.text.split(/\r\n|[\n\r\u2028\u2029]/u).map(s=>Array.from(s));
  assert.ok(start.line>=1 && end.line>=start.line && end.line<=lines.length);
  assert.ok(start.column>=1 && start.column<=lines[start.line-1].length+1);
  assert.ok(end.column>=1 && end.column<=lines[end.line-1].length+1);
  if(start.line===end.line){assert.ok(end.column>=start.column);return lines[start.line-1].slice(start.column-1,end.column-1).join('');}
  return null;
}
try {
  const snapshot=extract();
  assert.equal(snapshot.schema_version,1);
  assert.equal(snapshot.position_encoding,'unicode-scalar');
  const types=new Map(snapshot.types.map(t=>[t.id,t]));
  const symbols=new Map(snapshot.symbols.map(s=>[s.id,s]));
  function resolved(id) { const seen=new Set();let t=types.get(id);while(t?.kind==='resolved_variable'){assert.ok(!seen.has(t.id));seen.add(t.id);t=types.get(t.target_type);}return t; }
  assert.equal(types.size,snapshot.types.length);
  assert.equal(symbols.size,snapshot.symbols.length);
  assert.equal(new Set(snapshot.facts.map(f=>f.id)).size,snapshot.facts.length);
  for(const f of snapshot.facts){if(f.type_id!==null)assert.ok(types.has(f.type_id));if(f.symbol_id!==null)assert.ok(symbols.has(f.symbol_id));sourceSlice(snapshot,f);}
  const typed=(text,kind)=>snapshot.facts.filter(f=>f.type_id!==null&&(!kind||f.kind===kind)&&sourceSlice(snapshot,f)===text);
  assert.ok(typed('3.0').some(f=>resolved(f.type_id).name==='Double'),'dead branch Double lost');
  assert.ok(typed('unicode_neighbor','binding').length,'Unicode scalar source mapping failed');
  assert.ok(typed('identity(3.0)','expression').length,'cross-file generic call lost');
  const outer=typed('make()()','expression').find(f=>f.node_kind==='Texpr_apply');
  assert.ok(outer);assert.equal(outer.symbol_id,null);assert.equal(outer.details.callee_symbol_id,null);assert.equal(outer.details.dispatch,'indirect');
  assert.ok(snapshot.symbols.some(s=>s.kind==='parameter_method'),'generic trait method identity missing');
  assert.ok(snapshot.symbols.some(s=>s.kind==='field'));
  assert.ok(snapshot.symbols.some(s=>s.kind==='constructor'));
  const pair=snapshot.symbols.find(s=>s.kind==='constructor'&&s.name==='Pair');
  assert.ok(pair,'tuple struct constructor identity missing');
  assert.ok(snapshot.facts.some(f=>f.kind==='declaration'&&f.node_kind==='constructor'&&f.symbol_id===pair.id),'implicit tuple constructor declaration missing');
  const bad=snapshot.symbols.filter(s=>s.kind==='constructor'&&s.name==='Bad');
  assert.equal(bad.length,1,'suberror constructor identity must survive Error upcast');
  const extras=snapshot.symbols.filter(s=>s.kind==='constructor'&&s.name==='Extra');
  assert.equal(extras.length,1,'external enum extension identity lost');
  assert.ok(extras[0].identity.constructor_package,'extensible constructor package lost');
  assert.ok(snapshot.types.some(t=>t.kind==='function'&&t.error.kind==='typed'),'checked errors missing');
  assert.ok(snapshot.types.some(t=>t.kind==='parameter'&&t.owner),'generic type owner missing');
  assert.ok(snapshot.sources.some(s=>s.path.endsWith('/dep/value.mbt')),'dependency package source missing');
  const polyA=snapshot.types.filter(t=>t.kind==='parameter'&&t.name==='A');
  assert.ok(polyA.some(t=>t.owner.endsWith('::left')));assert.ok(polyA.some(t=>t.owner.endsWith('::right')));
  const valueTypes=snapshot.types.filter(t=>t.kind==='named'&&t.path.name==='Value');
  assert.ok(valueTypes.length);assert.ok(valueTypes.every(t=>t.named_kind==='Valtype'),'value-type declaration kind lost');
  for(const fact of snapshot.facts)for(const arg of fact.details.type_arguments?.types||[])
    for(const constraint of arg.constraints)assert.equal(constraint.location,null,'callee constraints must not use caller-relative locations');
  const valueField=snapshot.symbols.find(s=>s.kind==='field'&&s.identity.owner_type.package==='moongrep/semantic-fixture/dep');
  assert.ok(valueField);assert.ok(snapshot.facts.some(f=>f.kind==='field_reference'&&f.symbol_id===valueField.id));

  const shared=snapshot.symbols.filter(s=>s.kind==='local'&&s.name==='shared');
  assert.ok(shared.length>=4);
  const shadowed=shared.filter(s=>s.identity.owner.includes('"name":"shadow"'));
  assert.equal(shadowed.length,2,'shadowed bindings lost');
  assert.equal(new Set(shadowed.map(s=>s.identity.stamp)).size,2,'shadowing merged compiler identities');
  const aliases=snapshot.facts.filter(f=>f.node_kind==='Texpr_ident'&&sourceSlice(snapshot,f)==='forwarded');
  assert.ok(aliases.some(f=>f.details.alias_symbol_id&&f.details.target_symbol_id),'import alias identity lost');
  const captures=snapshot.symbols.filter(s=>s.kind==='local'&&s.name==='captured');
  assert.equal(captures.length,1,'or-pattern must share one resolved binding');
  const sites=new Set(snapshot.facts.filter(f=>f.kind==='binding'&&f.symbol_id===captures[0].id&&f.location).map(f=>JSON.stringify(f.location)));
  assert.equal(sites.size,2,'or-pattern definition sites lost');
  // Canonical source ranges also work when the compiler receives a symlink spelling.
  if(process.platform!=='win32') {
    const logical=path.join(project,'generic.mbt');
    const physical=path.join(temp,'real-generic.mbt');
    fs.renameSync(logical,physical);fs.symlinkSync(physical,logical);
    const linked=extract();
    assert.ok(linked.sources.some(s=>s.path===fs.realpathSync(physical)));
    assert.ok(linked.facts.some(f=>f.location?.file===fs.realpathSync(physical)),'symlink source identity lost');
    for(const fact of linked.facts) sourceSlice(linked,fact);
  }
  // A changed invalid source must never reuse a successful cache.
  const file=path.join(project,'dead_branch.mbt');fs.appendFileSync(file,'\nfn invalid() -> Int { "wrong" }\n');
  const failed=spawnSync(reader,['--project',project],{encoding:'utf8',timeout:90000,maxBuffer:32*1024*1024});
  assert.notEqual(failed.status,0,'invalid source reused stale checked artifact');
  assert.equal(failed.stdout.trim(),'','failed analysis emitted a success snapshot');
  console.log(`Reader checks passed: ${snapshot.facts.length} facts, ${snapshot.types.length} types, ${snapshot.symbols.length} symbols.`);
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
