#!/usr/bin/env node
// Black-box oracle: only the installed moonc and the pure MoonBit reader run.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const build = path.resolve(process.argv[2] || path.join(here, '../../_build/semantic-reader'));
const moonc = process.env.MOON_HOME ? path.join(process.env.MOON_HOME, 'bin', 'moonc') : 'moonc';
const core = path.join(process.env.MOON_HOME || path.join(os.homedir(), '.moon'), 'lib/core/_build/wasm/release/bundle');
const std = ['-std-path', core, '-i', path.join(core, 'prelude/prelude.mi') + ':prelude'];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-pure-oracle-'));
function run(exe, args) {
  const result = spawnSync(exe, args, {cwd:temp, encoding:'utf8', timeout:60000, maxBuffer:64*1024*1024});
  if (result.error || result.status !== 0) throw new Error(`${exe}: ${result.error?.message || result.stderr}`);
  return result.stdout;
}
function parseSexp(source) {
  let i=0;
  function value() {
    while (/\s/.test(source[i] || '') && i<source.length) i++;
    if (source[i] === '(') {
      i++; const out=[];
      while (true) {
        while (/\s/.test(source[i] || '') && i<source.length) i++;
        if (source[i] === ')') {i++; return out;}
        if (i>=source.length) throw new Error('truncated oracle sexp');
        out.push(value());
      }
    }
    if (source[i] === '"') {
      i++; let out='';
      while (source[i] !== '"') {
        if (i>=source.length) throw new Error('truncated oracle string');
        if (source[i] !== '\\') {out+=source[i++];continue;}
        i++; const e=source[i++];
        if (/\d/.test(e)) {out+=String.fromCharCode(Number(e+source.slice(i,i+2)));i+=2;}
        else out+=({n:'\n',r:'\r',t:'\t',b:'\b'}[e] ?? e);
      }
      i++; return out;
    }
    const start=i;
    while (i<source.length && !/[\s()]/.test(source[i])) i++;
    if (start===i) throw new Error('invalid oracle token');
    return source.slice(start,i);
  }
  const result=value();
  if(source.slice(i).trim())throw new Error('oracle trailing data');
  return result;
}
const primitive=new Set(['Unit','Bool','Byte','Char','Int','Int16','Int64','UInt','UInt16','UInt64','Float','Double','String','Bytes','V128']);
const normalizeName=s=>s.replace(/^@moonbitlang\/core\/(?:builtin|prelude)\./,'');
function pathName(p) {
  if(p.kind==='builtin')return p.name;
  if(p.kind==='tuple')return `Tuple${p.arity}`;
  if(p.kind==='named')return normalizeName((p.package ? '@'+p.package+'.':'')+p.name);
  return JSON.stringify(p);
}
try {
  const files=fs.readdirSync(path.join(here,'fixtures/project')).filter(f=>f.endsWith('.mbt')&&f!=='dependency.mbt').sort();
  const text=files.map(f=>fs.readFileSync(path.join(here,'fixtures/project',f),'utf8')).join('\n');
  const file=path.join(temp,'sample.mbt');fs.writeFileSync(file,text);
  const version=run(moonc,['-v']).trim();
  assert.equal(version,'v0.10.14+7080b3792-nightly (2026-10-10)');
  run(moonc,['compile','sample.mbt','-stop-after-typing','-show-loc',...std]);
  run(moonc,['check','sample.mbt','-pkg','','-o','sample.mi',...std]);
  const manifest={compiler_version:version,sources:[{path:file,text}],packages:[{key:'oracle@wasm:normal',name:'',source_root:temp,artifact:path.join(temp,'sample.typechecked'),import_kind:'normal',source_aliases:[]}]};
  fs.writeFileSync(path.join(temp,'manifest.json'),JSON.stringify(manifest));
  const snapshot=JSON.parse(run(path.join(build,'moonc-reader-native'),['--manifest',path.join(temp,'manifest.json')]));
  const types=new Map(snapshot.types.map(t=>[t.id,t]));
  const parameters=new Set(snapshot.types.filter(t=>t.kind==='parameter').map(t=>t.name));
  function normalizedType(id,seen=new Set()) {
    assert.ok(!seen.has(id),'cyclic decoded semantic type in oracle fixture');
    const t=types.get(id);assert.ok(t);
    switch(t.kind) {
      case 'builtin':return t.name;
      case 'parameter':return t.name;
      case 'resolved_variable':return normalizedType(t.target_type,new Set([...seen,id]));
      case 'unresolved':return '_';
      case 'error_recovery':return '?';
      case 'trait_object':return ['trait',pathName(t.path)];
      case 'named':return ['named',pathName(t.path),t.arguments.map(n=>normalizedType(n))];
      case 'function':return ['function',t.parameters.map(n=>normalizedType(n)),normalizedType(t.return_type),t.error.kind==='typed'?normalizedType(t.error.type_id):t.error.kind,t.async];
      default:throw new Error(`unknown semantic type ${t.kind}`);
    }
  }
  function nativeType(n) {
    if(typeof n==='string') {
      if(primitive.has(n)||parameters.has(n)||n==='_')return n;
      if(n==='StringView'||n==='BytesView')return ['named',n,[]];
      return null;
    }
    if(!Array.isArray(n))return null;
    if(n[0]==='T_constr')return ['named',normalizeName(n[1]),n[2].map(requiredType)];
    if(n[0]==='Tproduct')return ['named',`Tuple${n[1].length}`,n[1].map(requiredType)];
    if(n[0]==='T_suberror'||n[0]==='T_newtype'||n[0]==='T_valtype'||n[0]==='T_extenum')return ['named',normalizeName(n[1]),Array.isArray(n[2])?n[2].map(requiredType):[]];
    if(n[0]==='Result'||n[0]==='Option'||n[0]==='FixedArray')return ['named',n[0],n.slice(1).map(requiredType)];
    if(n[0]==='T_trait')return ['trait',normalizeName(n[1])];
    const arrow=n.indexOf('->');
    if(arrow>=1&&Array.isArray(n[arrow-1])) {
      const bang=n.indexOf('!');
      return ['function',n[arrow-1].map(requiredType),requiredType(n[arrow+1]),bang<0?'none':n[bang+1]==='?Error'?'parameter':requiredType(n[bang+1]),n[0]==='async'?'async':'sync'];
    }
    return null;
  }
  function requiredType(n) {const t=nativeType(n);assert.notEqual(t,null,`unsupported oracle type ${JSON.stringify(n)}`);return t;}
  const range=/^(\d+):(\d+)-(\d+):(\d+)$/;
  const basePattern=/^(\d+):1$/;
  function baseOf(n) {
    const direct=n.findLast(x=>typeof x==='string'&&basePattern.test(x));
    if(direct)return Number(direct.split(':')[0]);
    if(Array.isArray(n[1])) {
      const field=n[1].find(x=>Array.isArray(x)&&x[0]==='base_pos');
      if(field)return Number(field[1].split(':')[0]);
    }
    throw new Error(`no base position for ${n[0]}`);
  }
  function semantic(n,base) {
    const kind=n[0];
    let loc=n.findLast(x=>typeof x==='string'&&range.test(x));
    if(kind==='Texpr_function')loc=n[1].find(x=>x[0]==='loc_')[1];
    assert.ok(loc,`missing location: ${kind}`);
    if(loc==='0:0-0:0')return null;
    let ty;
    if(['Texpr_unit','Texpr_proof_assert'].includes(kind))ty='Unit';
    else if(['Texpr_is','Texpr_and','Texpr_or','Texpr_not'].includes(kind))ty='Bool';
    else if(kind==='Texpr_any_to_string')ty='String';
    else if(kind==='Texpr_string_as_view')ty=['named','StringView',[]];
    else if(kind==='Texpr_bytes_as_view')ty=['named','BytesView',[]];
    else if(kind==='Tpat_with')ty=semantic(n[1],base)?.[2];
    else { const candidates=n.slice(1).map(nativeType).filter(x=>x!==null); ty=['Texpr_try','Texpr_defer'].includes(kind)?candidates[0]:candidates.at(-1); }
    assert.ok(ty,`no type for ${kind}: ${JSON.stringify(n)}`);
    const [,sl,sc,el,ec]=loc.match(range).map(Number);
    return [kind,`${base+sl}:${sc}-${base+el}:${ec}`,ty];
  }
  const expected=[];
  const nativeLocals=new Map();
  function visit(n,base) {
    if(!Array.isArray(n))return;
    if(typeof n[0]==='string'&&/^(Timpl_|Tdecl_)/.test(n[0]))base=baseOf(n);
    if(n.length===2 && typeof n[0]==='string' && /\/\d+$/.test(n[0]) && typeof n[1]==='string' && range.test(n[1]) && n[1]!=='0:0-0:0') {
      const [,sl,sc,el,ec]=n[1].match(range).map(Number);
      const key=base+':'+n[0];
      if(!nativeLocals.has(key))nativeLocals.set(key,new Set());
      nativeLocals.get(key).add(`${base+sl}:${sc}-${base+el}:${ec}`);
    }
    if(typeof n[0]==='string'&&/^(Texpr_|Tpat_)/.test(n[0])) {
      const row=semantic(n,base);if(row)expected.push(JSON.stringify(row));
    }
    for(const child of n)visit(child,base);
  }
  visit(parseSexp(fs.readFileSync(file+'.typedtree','utf8')),0);
  const actual=snapshot.facts.filter(f=>/^(Texpr_|Tpat_)/.test(f.node_kind)&&['expression','pattern'].includes(f.kind)&&f.location).map(f=>{
    assert.equal(f.location.file,file);
    const {start,end}=f.location;
    return JSON.stringify([f.node_kind,`${start.line}:${start.column}-${end.line}:${end.column}`,normalizedType(f.type_id)]);
  });
  assert.deepEqual([...new Set(actual)].sort(),[...new Set(expected)].sort(),'decoded expression/pattern types or source spans differ from native typedtree');
  const localIds=new Set(snapshot.symbols.filter(s=>s.kind==='local').map(s=>s.id));
  const decodedLocals=new Map();
  for(const f of snapshot.facts) if(localIds.has(f.symbol_id)&&f.location&&['binding','symbol_reference'].includes(f.kind)) {
    const {start,end}=f.location;
    if(!decodedLocals.has(f.symbol_id))decodedLocals.set(f.symbol_id,new Set());
    decodedLocals.get(f.symbol_id).add(`${start.line}:${start.column}-${end.line}:${end.column}`);
  }
  const groups=m=>[...m.values()].map(s=>JSON.stringify([...s].sort())).sort();
  assert.deepEqual(groups(decodedLocals),groups(nativeLocals),'local binding/reference identity differs from native typedtree');
  console.log(`Pure reader compatibility passed: ${new Set(expected).size} expression/pattern types and ranges, ${nativeLocals.size} local symbol groups match nightly's native typedtree; no compiler libraries.`);
} finally {fs.rmSync(temp,{recursive:true,force:true});}
