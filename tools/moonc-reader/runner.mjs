#!/usr/bin/env node
// This file deliberately uses dynamic imports inside main so the installed,
// extensionless executable works with both CommonJS and ESM Node defaults.
async function main() {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const os = await import('node:os');
  const crypto = await import('node:crypto');
  const {spawnSync} = await import('node:child_process');
  const {TextDecoder} = await import('node:util');
  const versions = new Set([
    'v0.10.14+7080b3792-nightly (2026-10-10)',
  ]);
  const targets = new Set(['wasm', 'wasm-gc', 'js', 'native', 'llvm']);
  const args = process.argv.slice(2);
  let projectArg, target;
  for (let i = 0; i < args.length; i++) {
    const option = args[i];
    if (option === '--help' || option === '-h') {
      process.stdout.write('Usage: moonc-reader --project <path> [--target wasm|wasm-gc|js|native|llvm]\n');
      return;
    }
    if (option !== '--project' && option !== '--target') throw new Error(`Unexpected argument: ${option}`);
    if (i + 1 === args.length) throw new Error(`Missing value for ${option}`);
    const value = args[++i];
    if (option === '--project') {
      if (projectArg !== undefined) throw new Error('--project may only be given once');
      projectArg = value;
    } else {
      if (target !== undefined || !targets.has(value)) throw new Error(`Invalid or repeated target: ${value}`);
      target = value;
    }
  }
  if (!projectArg) throw new Error('--project is required');
  const executableSuffix = process.platform === 'win32' ? '.exe' : '';
  const regular = file => { try { return fs.statSync(file).isFile(); } catch { return false; } };
  const exists = file => { try { fs.statSync(file); return true; } catch { return false; } };
  const canonical = file => fs.realpathSync(path.resolve(file));
  const inside = (directory, file) => { const relative = path.relative(directory, file); return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)); };
  function which(name) {
    for (const directory of (process.env.PATH || '').split(path.delimiter)) {
      const file = path.resolve(directory || '.', name + executableSuffix);
      if (regular(file)) return canonical(file);
    }
    throw new Error(`Required tool is not on PATH: ${name}`);
  }
  let moon;
  if (process.env.MOON_HOME) {
    moon = path.resolve(process.env.MOON_HOME, 'bin', 'moon' + executableSuffix);
    if (!regular(moon)) throw new Error(`MOON_HOME does not contain moon: ${moon}`);
    moon = canonical(moon);
  } else {
    moon = which('moon');
  }
  const compiler = path.join(path.dirname(moon), 'moonc' + executableSuffix);
  if (!regular(compiler)) throw new Error(`The selected moon toolchain has no sibling moonc: ${compiler}`);
  function run(program, argv, {cwd, diagnostics = false} = {}) {
    const result = spawnSync(program, argv, {cwd, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, windowsHide: true});
    if (result.error) throw new Error(`Could not run ${path.basename(program)}: ${result.error.message}`);
    if (result.status !== 0) {
      const reason = result.signal ? `signal ${result.signal}` : `exit code ${result.status}`;
      throw new Error(`${path.basename(program)} failed (${reason}):\n${result.stderr || ''}${result.stdout || ''}`);
    }
    if (diagnostics) {
      if (result.stdout) process.stderr.write(result.stdout);
      if (result.stderr) process.stderr.write(result.stderr);
    } else if (result.stderr) {
      process.stderr.write(result.stderr);
    }
    return result.stdout;
  }
  function compilerVersion() {
    const value = run(compiler, ['-v']).trim();
    if (!versions.has(value)) throw new Error(`Unsupported compiler version: ${value}. Validate a reader for this exact toolchain before reading its artifacts.`);
    return value;
  }
  const compiler_version = compilerVersion();
  const requested = path.resolve(projectArg);
  const project = canonical(requested);
  const isDirectory = fs.statSync(project).isDirectory();
  const configNames = ['moon.pkg', 'moon.pkg.json', 'moon.mod', 'moon.mod.json', 'moon.work', 'moon.work.json', 'moon.lock'];
  const configInput = !isDirectory && configNames.includes(path.basename(project));
  const selection = configInput ? path.dirname(requested) : requested;
  const canonicalSelection = canonical(selection);
  const selectionDirectory = isDirectory || configInput;
  const cwd = selectionDirectory ? selection : path.dirname(selection);
  if (!selectionDirectory && !/\.(mbt|mbtx|mbtp|mbt\.md)$/.test(selection)) throw new Error(`Unsupported source file: ${selection}`);
  if (selectionDirectory) {
    let cursor = canonical(cwd), hasRoot = false;
    while (true) {
      if (['moon.mod', 'moon.mod.json', 'moon.work'].some(name => regular(path.join(cursor, name)))) { hasRoot = true; break; }
      const parent = path.dirname(cursor);
      if (parent === cursor) break;
      cursor = parent;
    }
    if (!hasRoot) throw new Error(`Not a MoonBit module or workspace: ${selection}`);
  }
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'moongrep-semantics-'));
  try {
    const build = path.join(temporary, '_build');
    const checkArgs = ['-C', cwd, 'check', '--target-dir', build];
    if (target) checkArgs.push('--target', target);
    let linkedModuleFile = false;
    if (!selectionDirectory && selection !== canonicalSelection && !selection.endsWith('.mbtx')) {
      let directory = canonical(cwd);
      while (true) {
        if (['moon.mod', 'moon.mod.json', 'moon.work'].some(name => regular(path.join(directory, name)))) { linkedModuleFile = true; break; }
        const parent = path.dirname(directory);
        if (parent === directory) break;
        directory = parent;
      }
    }
    const fileSelector = !selectionDirectory && !linkedModuleFile;
    if (fileSelector) checkArgs.push(selection);
    run(moon, checkArgs, {cwd, diagnostics: true});
    if (compilerVersion() !== compiler_version) throw new Error('Compiler changed during project checking');
    // File-selector checks can omit inventory metadata for module packages.
    // Ask moon for the module inventory in the same owned build directory.
    if (fileSelector && !regular(path.join(build, 'index.json')) && !regular(path.join(build, path.basename(selection), 'index.json'))) {
      run(moon, checkArgs.slice(0, -1), {cwd, diagnostics:true});
      if (compilerVersion() !== compiler_version) throw new Error('Compiler changed during inventory generation');
    }
    const standaloneInventory = !regular(path.join(build, 'index.json')) && !selectionDirectory;
    const inventoryBuild = standaloneInventory ? path.join(build, path.basename(selection)) : build;
    const indexFile = path.join(inventoryBuild, 'index.json');
    if (!regular(indexFile)) throw new Error(`moon check did not produce an inventory index: ${indexFile}`);
    const backends = JSON.parse(fs.readFileSync(indexFile, 'utf8'));
    if (!Array.isArray(backends) || backends.some(value => !targets.has(value))) throw new Error('Unsupported build inventory backend index');
    const selectedBackends = target ? backends.filter(value => value === target) : backends;
    if (!selectedBackends.length) throw new Error('Requested target is missing from the checked inventory');
    const inventories = [];
    const inventoryFiles = [indexFile];
    function optionValues(command, option) {
      const values = [];
      for (let i = 1; i < command.length; i++) if (command[i] === option) {
        if (i + 1 >= command.length) throw new Error(`Missing ${option} value in package command`);
        values.push(command[++i]);
      }
      return values;
    }
    function oneOption(command, option) {
      const values = optionValues(command, option);
      if (values.length !== 1) throw new Error(`Expected exactly one ${option} in package command`);
      return values[0];
    }
    function sourceArguments(command) {
      return [...new Set(command.filter(arg => /\.(mbt|mbtx|mbtp|mbt\.md)$/.test(arg) && regular(arg)).map(canonical))];
    }
    for (const backend of selectedBackends) {
      const file = path.join(inventoryBuild, backend, 'debug', 'check', 'packages.json');
      if (!regular(file)) throw new Error(`Missing checked package inventory: ${file}`);
      inventoryFiles.push(file);
      const inventory = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (!Array.isArray(inventory.packages)) throw new Error(`Invalid package inventory: ${file}`);
      for (const item of inventory.packages) inventories.push({item, backend});
    }
    const dependencyRoots = new Set();
    const allPackages = [];
    for (const {item, backend} of inventories) {
      if (typeof item['root-path'] !== 'string') throw new Error('Inventory package has no root-path');
      const sourceRoot = canonical(item['root-path']);
      for (const key of ['deps', 'wbtest-deps', 'test-deps']) {
        for (const dependency of item[key] || []) if (typeof dependency.fspath === 'string' && exists(dependency.fspath)) dependencyRoots.add(canonical(dependency.fspath));
      }
      for (const [kind, commandKey, intrinsicKey] of [
        ['normal', 'check-command', 'files'], ['wbtest', 'wbtest-check-command', 'wbtest-files'], ['bbtest', 'test-check-command', 'test-files'],
      ]) {
        const command = item[commandKey];
        if (command === null || command === undefined) continue;
        if (!Array.isArray(command) || command.some(arg => typeof arg !== 'string') || command[0] !== 'check') throw new Error(`Unsupported package check command: ${commandKey}`);
        const actualTarget = oneOption(command, '-target');
        if (actualTarget !== backend) throw new Error(`Inventory and command targets differ: ${backend} / ${actualTarget}`);
        const name = oneOption(command, '-pkg');
        oneOption(command, '-o');
        const sources = sourceArguments(command);
        if (!sources.length) continue;
        let intrinsic = Object.keys(item[intrinsicKey] || {}).filter(regular).map(canonical);
        if (kind === 'bbtest') intrinsic.push(...Object.keys(item['mbt-md-files'] || {}).filter(regular).map(canonical));
        intrinsic = intrinsic.filter(file => sources.includes(file));
        allPackages.push({key: `${name}@${backend}:${kind}`, name, source_root: sourceRoot, import_kind: kind, command, sources, intrinsic, thirdParty: item['is-third-party'] === true});
      }
    }
    const selected = allPackages.filter(pkg => selectionDirectory
      ? !pkg.thirdParty && inside(canonicalSelection, pkg.source_root)
      : pkg.intrinsic.includes(canonicalSelection));
    selected.sort((left, right) => left.key.localeCompare(right.key));
    if (!selected.length) throw new Error(`No checked source packages own the requested path: ${selection}`);
    if (!selectionDirectory && selected.length !== 1) throw new Error(`Ambiguous checked package ownership for: ${selection}`);
    if (new Set(selected.map(pkg => pkg.key)).size !== selected.length) throw new Error('Duplicate package build views in compiler inventory');
    const decoder = new TextDecoder('utf-8', {fatal: true});
    const sourcePaths = [...new Set(selected.flatMap(pkg => pkg.sources))].sort();
    const sources = sourcePaths.map(file => ({path: file, text: decoder.decode(fs.readFileSync(file))}));
    for (const source of sources) {
      let blockLines = 0;
      for (const line of source.text.split(/\r\n|[\n\r\u2028\u2029]/u)) {
        if (line.startsWith('///|')) blockLines = 0;
        if (++blockLines > 16383) throw new Error(`Source block exceeds the exact location limit: ${source.path}`);
        if (Array.from(line).length > 65535) throw new Error(`Source line exceeds the exact location limit: ${source.path}`);
      }
    }
    const snapshots = new Map();
    function snapshot(file, optional = false) {
      file = path.resolve(file);
      if (snapshots.has(file)) return;
      if (!regular(file)) {
        if (optional && !exists(file)) { snapshots.set(file, null); return; }
        throw new Error(`Missing compiler input: ${file}`);
      }
      snapshots.set(file, crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'));
    }
    function snapshotConfigurations(directory) {
      while (true) {
        for (const name of configNames) snapshot(path.join(directory, name), true);
        const parent = path.dirname(directory);
        if (parent === directory) break;
        directory = parent;
      }
    }
    function snapshotInterfaces(directory, visited = new Set()) {
      const real = canonical(directory);
      if (visited.has(real)) return;
      visited.add(real);
      for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
        const file = path.join(directory, entry.name);
        const stat = fs.statSync(file);
        if (stat.isDirectory()) snapshotInterfaces(file, visited);
        else if (stat.isFile() && entry.name.endsWith('.mi')) snapshot(file);
      }
    }
    for (const file of inventoryFiles) snapshot(file);
    snapshot(compiler);
    snapshotConfigurations(cwd);
    for (const pkg of allPackages) {
      for (const file of pkg.sources) snapshot(file);
      snapshotConfigurations(pkg.source_root);
    }
    const standardDirectories = new Set();
    for (const pkg of selected) {
      for (const value of optionValues(pkg.command, '-i')) snapshot(value.replace(/\.mi:.*$/, '.mi'));
      for (const option of ['-all-pkgs', '-patch-file', '-check-mi']) for (const file of optionValues(pkg.command, option)) {
        snapshot(file);
        if (option === '-all-pkgs') {
          const pending = [JSON.parse(fs.readFileSync(file, 'utf8'))];
          while (pending.length) {
            const value = pending.pop();
            if (typeof value === 'string' && value.endsWith('.mi')) snapshot(value, true);
            else if (value && typeof value === 'object') pending.push(...Object.values(value));
          }
        }
      }
      for (const directory of optionValues(pkg.command, '-std-path')) standardDirectories.add(directory);
    }
    for (const directory of standardDirectories) snapshotInterfaces(directory);
    for (const directory of dependencyRoots) snapshotConfigurations(directory);
    // Detect newly added sources/configuration as well as changed existing files.
    // Real directory identities prevent cycles through symlinks.
    function directoryMembership(directory, recursive = true) {
      const files = [], visited = new Set();
      function walk(current) {
        const real = canonical(current);
        if (visited.has(real)) return;
        visited.add(real);
        for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
          if (['.git', '_build', 'node_modules'].includes(entry.name)) continue;
          const file = path.join(current, entry.name);
          let stat;
          try { stat = fs.statSync(file); } catch { throw new Error(`Source directory changed during extraction: ${file}`); }
          if (stat.isDirectory()) { if (recursive) walk(file); }
          else if (stat.isFile() && (/\.(mbt|mbtx|mbtp|mbt\.md)$/.test(entry.name) || configNames.includes(entry.name))) files.push(`${file}=>${canonical(file)}`);
        }
      }
      walk(directory);
      return files.sort().join('\n');
    }
    const membership = new Map();
    for (const directory of new Set([...allPackages.map(pkg => pkg.source_root), ...dependencyRoots])) {
      const recursive = !(standaloneInventory && directory === cwd);
      membership.set(directory, {recursive, entries:directoryMembership(directory, recursive)});
    }
    function unchanged() {
      for (const [directory, before] of membership) if (directoryMembership(directory, before.recursive) !== before.entries) throw new Error(`Source directory membership changed during semantic extraction: ${directory}`);
      for (const [file, expected] of snapshots) {
        const actual = regular(file) ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : null;
        if (actual !== expected || (expected === null && exists(file))) throw new Error(`Compiler input changed during semantic extraction: ${file}`);
      }
      for (const source of sources) if (decoder.decode(fs.readFileSync(source.path)) !== source.text) throw new Error(`Source changed during semantic extraction: ${source.path}`);
    }
    const packages = [];
    for (let i = 0; i < selected.length; i++) {
      const pkg = selected[i];
      const output = path.join(temporary, `${i}.mi`);
      const command = [...pkg.command];
      command[command.indexOf('-o') + 1] = output;
      run(compiler, command, {cwd, diagnostics: true});
      const artifact = output.replace(/\.mi$/, '.typechecked');
      if (!regular(artifact)) throw new Error(`Compiler did not emit the required typed frontend artifact: ${artifact}`);
      const aliases = new Map();
      for (const arg of pkg.command) if (/\.(mbt|mbtx|mbtp|mbt\.md)$/.test(arg) && regular(arg)) {
        const logical = path.resolve(cwd, arg);
        const target = canonical(logical);
        const candidates = [logical];
        if (canonical(path.dirname(logical)) === pkg.source_root) candidates.push(path.join(pkg.source_root, path.basename(logical)));
        for (const candidate of candidates) {
          if (aliases.has(candidate) && aliases.get(candidate) !== target) throw new Error(`Ambiguous source alias: ${candidate}`);
          aliases.set(candidate, target);
        }
      }
      packages.push({key: pkg.key, name: pkg.name, source_root: pkg.source_root, artifact, import_kind: pkg.import_kind, source_aliases: [...aliases]});
    }
    unchanged();
    if (compilerVersion() !== compiler_version) throw new Error('Compiler changed during semantic extraction');
    const manifestPath = path.join(temporary, 'manifest.json');
    fs.writeFileSync(manifestPath, JSON.stringify({compiler_version, sources, packages}));
    const native = path.join(path.dirname(path.resolve(process.argv[1])), 'moonc-reader-native' + executableSuffix);
    if (!regular(native)) throw new Error(`Missing native reader: ${native}`);
    const output = run(native, ['--manifest', manifestPath], {cwd});
    unchanged();
    const snapshotOutput = JSON.parse(output);
    if (snapshotOutput.compiler_version !== compiler_version || snapshotOutput.schema_version !== 1) throw new Error('Native reader emitted an incompatible envelope');
    process.stdout.write(output.endsWith('\n') ? output : output + '\n');
  } finally {
    fs.rmSync(temporary, {recursive: true, force: true});
  }
}
main().catch(error => { process.stderr.write(`moonc-reader: ${error.message}\n`); process.exitCode = 2; });
