///|
fn parent(path : String) -> String {
  @path.Path(path).dirname().to_string()
}

///|
async fn command(
  program : String,
  args : Array[String],
  root : String,
  environment : Map[String, String],
) -> String {
  let executable = tool_program(program)
  let args = if program == "moon" { ["-C", root, ..args] } else { args }
  let (status, stdout, stderr) = @process.collect_output(
    executable,
    args,
    cwd=root,
    extra_env=environment,
  )
  if status != 0 {
    fail("\{program} exited with \{status}: \{stderr.text()}\{stdout.text()}")
  }
  stdout.text()
}

///|
fn tool_program(program : String) -> String {
  @env.get_env_var("MOON_HOME")
  .map(home => home + "/bin/" + program)
  .unwrap_or(program)
}

///|
fn command_option(command : Array[Json], option : String) -> String raise {
  for i in 0..<(command.length() - 1) {
    if command[i] == Json::string(option) && command[i + 1] is String(value) {
      return value
    }
  }
  fail("checked package inventory has no \{option}")
}

///|
async fn config_root(path : String, workspace : String?) -> (String, Bool) {
  if workspace is Some(manifest) && manifest != "off" {
    guard @fs.kind(manifest) is Regular else {
      fail("MOON_WORK must select a workspace manifest")
    }
    return (parent(manifest), false)
  }
  let is_directory = @fs.kind(path) is Directory
  let start = if is_directory { path } else { parent(path) }
  let mut root = start
  let mut module_root : String? = None
  while true {
    if workspace != Some("off") {
      for name in ["moon.work", "moon.work.json"] {
        if @fs.exists(root + "/" + name) {
          if module_root is Some(module_root) &&
            !workspace_contains(root + "/" + name, module_root) {
            return (module_root, true)
          }
          return (root, false)
        }
      }
    }
    for name in ["moon.mod", "moon.mod.json"] {
      if module_root is None && @fs.exists(root + "/" + name) {
        module_root = Some(root)
      }
    }
    let next = parent(root)
    if next == root {
      break
    }
    root = next
  }
  match module_root {
    Some(root) => (root, true)
    None if !is_directory => (start, true)
    None => fail("not a MoonBit module or workspace: \{path}")
  }
}

///|
async fn source_membership(root : String) -> Array[String] {
  let pending = [root]
  let visited : Map[String, Bool] = Map([])
  let files = []
  while pending.pop() is Some(directory) {
    let real = @fs.realpath(directory)
    if visited.contains(real) {
      continue
    }
    visited[real] = true
    for name in @fs.readdir(directory) {
      if name.has_prefix(".") ||
        ["_build", "target", "node_modules"].contains(name) {
        continue
      }
      let file = directory + "/" + name
      if @fs.kind(file) is Directory {
        pending.push(file)
      } else if file.has_suffix(".mbt") ||
        file.has_suffix(".mbtx") ||
        file.has_suffix(".mbt.md") ||
        [
          "moon.pkg", "moon.pkg.json", "moon.mod", "moon.mod.json", "moon.work",
          "moon.work.json", "moon.lock",
        ].contains(name) {
        files.push(file + "=>" + @fs.realpath(file))
      }
    }
  }
  files.sort()
  files
}

///|
async fn remember_config(
  directory : String,
  snapshots : Map[String, Bytes?],
) -> Unit {
  let mut directory = directory
  while true {
    for
      name in [
        "moon.pkg", "moon.pkg.json", "moon.mod", "moon.mod.json", "moon.work", "moon.work.json",
        "moon.lock",
      ] {
      let file = directory + "/" + name
      if !snapshots.contains(file) {
        snapshots[file] = if @fs.exists(file) {
          Some(@fs.read_file(file).binary())
        } else {
          None
        }
      }
    }
    let next = parent(directory)
    if next == directory {
      break
    }
    directory = next
  }
}

///|
async fn require_unchanged(snapshots : Map[String, Bytes?]) -> Unit {
  for file, before in snapshots {
    let now = if @fs.exists(file) {
      Some(@fs.read_file(file).binary())
    } else {
      None
    }
    if before != now {
      fail("IDE input changed during extraction: \{file}")
    }
  }
}

///|
/// Export authored semantic evidence through the official language service.
/// No serialized compiler representation is read, and no compiler version is
/// pinned to a private layout. Missing IDE information stays explicit.
pub async fn export_index(
  project : String,
  target? : String,
) -> @semantic.Index {
  let requested = @fs.realpath(project)
  let directory_selection = @fs.kind(requested) is Directory
  let environment : Map[String, String] = Map([])
  let workspace = match @env.get_env_var("MOON_WORK") {
    Some("off") => Some("off")
    Some(path) => {
      let absolute = @fs.realpath(path)
      environment["MOON_WORK"] = absolute
      Some(absolute)
    }
    None => None
  }
  let (root, disable_workspace) = config_root(requested, workspace)
  if disable_workspace {
    environment["MOON_WORK"] = "off"
  }
  let version = command("moonc", ["-v"], root, environment).trim().to_owned()
  let args = ["check", "--no-mbti"]
  if target is Some(target) {
    args.append(["--target", target])
  }
  let standalone = !directory_selection &&
    !(@fs.exists(root + "/moon.mod") ||
    @fs.exists(root + "/moon.mod.json") ||
    @fs.exists(root + "/moon.work") ||
    @fs.exists(root + "/moon.work.json"))
  if standalone {
    args.push(requested)
  }
  ignore(command("moon", args, root, environment))
  let inventory_root = if standalone {
    root + "/_build/" + @path.Path(requested).basename().to_owned()
  } else {
    root + "/_build"
  }
  let backends : Array[String] = @json.from_json(
    @fs.read_file(inventory_root + "/index.json").json(),
  )
  guard backends is [backend] else {
    fail("select one backend with --target for IDE export")
  }
  let selector = @fs.read_file(inventory_root + "/packages.json").json()
  guard selector is { "backend": String(active), "opt_level": "debug", .. } &&
    active == backend else {
    fail("checked package selector disagrees with the requested backend")
  }
  let inventory = @fs.read_file(
    inventory_root + "/\{backend}/debug/check/packages.json",
  ).json()
  guard inventory is { "packages": Array(packages), .. } else {
    fail("invalid Moon package inventory")
  }
  let sources : Map[String, InputSource] = Map([])
  let package_roots : Map[String, String] = Map([])
  let snapshots : Map[String, Bytes?] = Map([])
  let memberships : Map[String, Array[String]] = Map([])
  remember_config(root, snapshots)
  for package_entry in packages {
    guard package_entry is { "root-path": String(package_root), .. } else {
      fail("incomplete package inventory")
    }
    // Moon also inventories packages that have no check action for this
    // backend (for example, native-only test packages in a Wasm check).
    guard package_entry is { "check-command": Array(check), .. } else {
      continue
    }
    let name = command_option(check, "-pkg")
    let package_root = @fs.realpath(package_root)
    package_roots[package_root] = name
    remember_config(package_root, snapshots)
    if !memberships.contains(package_root) {
      memberships[package_root] = source_membership(package_root)
    }
    for input in check {
      if input is String(file) &&
        (file.has_suffix(".mbt") || file.has_suffix(".mbtx")) &&
        @fs.exists(file) {
        snapshots[@fs.realpath(file)] = Some(@fs.read_file(file).binary())
      }
    }
    guard package_entry is Object(fields) else { fail("package object") }
    for key in ["deps", "wbtest-deps", "test-deps"] {
      if fields.get(key) is Some(Array(deps)) {
        for dependency in deps {
          if dependency
            is { "path": String(path), "fspath": String(directory), .. } {
            package_roots[@fs.realpath(directory)] = path
          }
        }
      }
    }
    let selected = if directory_selection {
      inside(requested, package_root)
    } else {
      inside(package_root, requested)
    }
    if !selected || package_entry is { "is-third-party": true, .. } {
      continue
    }
    for key in ["check-command", "wbtest-check-command", "test-check-command"] {
      if fields.get(key) is Some(Array(inputs)) {
        let context_aliases : Map[String, String] = Map([])
        let dependency_keys = if key == "test-check-command" {
          ["test-deps"]
        } else if key == "wbtest-check-command" {
          ["deps", "wbtest-deps"]
        } else {
          ["deps"]
        }
        for dependency_key in dependency_keys {
          if fields.get(dependency_key) is Some(Array(dependencies)) {
            for dependency in dependencies {
              if dependency
                is { "path": String(path), "alias": String(pkg_alias), .. } {
                context_aliases[pkg_alias] = path
              }
            }
          }
        }
        let context_types : Map[String, Json] = Map([])
        let context_package = command_option(inputs, "-pkg")
        for input in inputs {
          if input is String(file) &&
            (file.has_suffix(".mbt") || file.has_suffix(".mbtx")) &&
            @fs.exists(file) {
            let file = @fs.realpath(file)
            let data = @fs.read_file(file)
            let text = data.text()
            if snapshots.get(file) is Some(Some(before)) &&
              before != data.binary() {
              fail("input changed during source discovery: \{file}")
            }
            snapshots[file] = Some(data.binary())
            for
              name, path in type_declarations(
                text, context_package, context_aliases,
              ) {
              context_types[name] = path
            }
            if (!directory_selection && file != requested) ||
              sources.contains(file) {
              continue
            }
            sources[file] = {
              path: file,
              text,
              package_name: context_package,
              aliases: context_aliases,
              type_names: context_types,
            }
          }
        }
      }
    }
  }
  guard !sources.is_empty() else {
    fail("no checked sources own \{project} (check root: \{root})")
  }
  let source_entries = sources.values().to_array()
  source_entries.sort_by((left, right) => left.path.compare(right.path))
  // The first check provides source inventory and prebuild outputs. Validate
  // the captured inputs with a second, normally cached check before querying.
  ignore(command("moon", args, root, environment))
  require_unchanged(snapshots)
  let plan = plan(source_entries)
  let builder : Builder = {
    types: TypeTable::new(),
    symbols: [],
    symbol_ids: Map([]),
    facts: [],
    documents: Map([]),
    catalogs: Map([]),
    packages: package_roots,
    sources,
  }
  for source in source_entries {
    builder.documents[source.path] = source.text
  }
  let client : Client = { root, backend, environment, cache: Map([]), }
  client.prefetch(plan)
  for query in plan.queries {
    builder.query(client, query, backend)
  }
  require_unchanged(snapshots)
  let current_backends : Array[String] = @json.from_json(
    @fs.read_file(inventory_root + "/index.json").json(),
  )
  if current_backends != backends ||
    @fs.read_file(inventory_root + "/packages.json").json() != selector {
    fail("checked backend changed during IDE extraction")
  }
  for directory, before in memberships {
    if source_membership(directory) != before {
      fail("source membership changed during IDE extraction: \{directory}")
    }
  }
  for file, text in builder.documents {
    if @fs.read_file(file).text() != text {
      fail("definition source changed during IDE extraction: \{file}")
    }
  }
  if command("moonc", ["-v"], root, environment).trim().to_owned() != version {
    fail("compiler changed during IDE extraction")
  }
  let result : Json = {
    "schema_version": 1,
    "provider": "moon-ide",
    "compiler_version": version,
    "position_encoding": "unicode-scalar",
    "context": "ide-file",
    "backend": backend,
    "sources": source_entries.map(source => {
      ({ "path": source.path, "text": source.text } : Json)
    }),
    "types": builder.types.values,
    "symbols": builder.symbols,
    "facts": builder.facts,
  }
  @semantic.Index::from_json(result, compiler_version=version)
}
