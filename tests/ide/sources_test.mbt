///|
async test "authored derives manual impls and implicit conversions have unique evidence" {
  let root = @fs.tmpdir(prefix="moongrep-ide-derived-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/moon.mod", "name = \"moongrep/generated-probe\"\n")
  @fs.write_file(
    root + "/moon.pkg",
    "import { \"moonbitlang/core/debug\", \"moonbitlang/core/json\" }\n",
  )
  let text =
    #|///|
    #|#derive(Eq, Compare, Debug, Show, Hash, ToJson, FromJson)
    #|pub struct Derived {
    #|  values : Array[Int]
    #|}
    #|///|
    #|pub struct Manual {
    #|  value : Int?
    #|}
    #|///|
    #|pub impl Eq for Manual with fn equal(self, other) {
    #|  self.value.map(x => x) == other.value
    #|}
    #|///|
    #|pub fn implicit_debug(value : Int?) -> Unit raise {
    #|  @debug.debug_inspect(value.map(x => x), content="unused")
    #|}
    #|///|
    #|pub fn manual_array(xs : Array[Int]) -> Array[Int] {
    #|  let _ = "🚀"; xs.map(x => x + 1).map(x => x * 2)
    #|}
  @fs.write_file(root + "/probe.mbt", text.replace_all(old="\n", new="\r\n"))
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(root, target="wasm")
  })
  let counts = run_ide_fixture_rules(index)
  assert_eq(counts.length(), 2)
  assert_eq(counts.get("moonbitlang/option_map_identity"), Some(2))
  assert_eq(counts.get("moonbitlang/array_map_fusion"), Some(1))
  assert_true(
    index
    .facts()
    .all(fact => {
      !(fact.details is { "generated_top_level": true, .. }) &&
      fact.location is Some(location) &&
      location.start.line > 5
    }),
  )
}

///|
async test "IDE file contexts cover normal whitebox and blackbox sources once" {
  let root = @fs.tmpdir(prefix="moongrep-ide-contexts-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/moon.mod", "name = \"moongrep/ide-contexts\"\n")
  @fs.write_file(root + "/moon.pkg", "")
  @fs.write_file(
    root + "/source.mbt",
    "pub fn example(xs : Array[Int]) -> Array[Int] { xs.map(x => x + 1).map(x => x * 2) }\n",
  )
  for name in ["source_wbtest.mbt", "source_test.mbt"] {
    @fs.write_file(
      root + "/" + name,
      "test { let xs = [1, 2]; ignore(xs.map(x => x + 1).map(x => x * 2)) }\n",
    )
  }
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(root, target="wasm")
  })
  assert_eq(index.sources().length(), 3)
  assert_true(index.facts().all(fact => fact.package_name.has_suffix(":ide")))
  let counts = run_ide_fixture_rules(index)
  assert_eq(counts.get("moonbitlang/array_map_fusion"), Some(3))
  for input in index.sources() {
    let source = @semantic_source.Source::parse(
      index,
      file=input.path,
      text=input.text,
      view="ide",
    )
    assert_true(!source.facts().is_empty())
    let stale = try {
      ignore(
        @semantic_source.Source::parse(
          index,
          file=input.path,
          text=input.text + "\n",
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(stale)
  }
  // File selection keeps the owning package's IDE context and canonical paths.
  let file_index = @async.with_timeout(600000, () => {
    @provider.export_index(root + "/source_wbtest.mbt", target="wasm")
  })
  assert_eq(file_index.sources().length(), 1)
  assert_eq(
    run_ide_fixture_rules(file_index).get("moonbitlang/array_map_fusion"),
    Some(1),
  )
}

///|
async test "failed compiler checks cannot publish a semantic snapshot" {
  let root = @fs.tmpdir(prefix="moongrep-ide-invalid-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/moon.mod", "name = \"moongrep/invalid-probe\"\n")
  @fs.write_file(root + "/moon.pkg", "")
  @fs.write_file(
    root + "/probe.mbt",
    "pub fn invalid() -> Int { missing_name() }\n",
  )
  let rejected = try {
    ignore(@provider.export_index(root, target="wasm"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
async test "official IDE respects the explicitly checked backend" {
  let root = @fs.tmpdir(prefix="moongrep-ide-target-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    root + "/moon.mod",
    "name = \"moongrep/target-probe\"\npreferred_target = \"wasm\"\n",
  )
  @fs.write_file(root + "/moon.pkg", "")
  let text =
    #|///|
    #|#cfg(target="wasm")
    #|pub fn chosen() -> Int { 42 }
    #|///|
    #|#cfg(target="native")
    #|pub fn chosen() -> String { "native" }
    #|///|
    #|pub fn use_chosen() -> Unit { ignore(chosen()) }
  @fs.write_file(root + "/probe.mbt", text)
  for (target, result_type) in [("wasm", "Int"), ("native", "String")] {
    let index = @async.with_timeout(600000, () => {
      @provider.export_index(root, target~)
    })
    let calls = index
      .facts()
      .filter(fact => {
        fact.node_kind == "call" &&
        fact.symbol_id.bind(id => index.symbol(id)) is Some(symbol) &&
        symbol.name == "chosen"
      })
    guard calls is [call] && call.type_id is Some(ty) else {
      fail("missing backend-specific call")
    }
    assert_true(
      index.type_info(ty).unwrap().raw
      is { "kind": "builtin", "name": String(name), .. } &&
      name == result_type,
      msg=target,
    )
  }
}

///|
async test "workspace exports retain module ownership and file selection" {
  let root = @fs.tmpdir(prefix="moongrep-ide-workspace-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/moon.work", "members = [\"./first\", \"./second\"]\n")
  for name in ["first", "second"] {
    @fs.mkdir(root + "/" + name)
    @fs.write_file(
      root + "/" + name + "/moon.mod",
      "name = \"moongrep/work-\{name}\"\n",
    )
    @fs.write_file(root + "/" + name + "/moon.pkg", "")
    @fs.write_file(
      root + "/" + name + "/source.mbt",
      "pub fn sample(xs : Array[Int]) -> Array[Int] { xs.map(x => x + 1).map(x => x * 2) }\n",
    )
  }
  @fs.mkdir(root + "/first/native_only")
  @fs.write_file(
    root + "/first/native_only/moon.pkg",
    "supported_targets = \"+native\"\n",
  )
  @fs.write_file(
    root + "/first/native_only/source.mbt",
    "pub fn only_native() -> Int { 1 }\n",
  )
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(root, target="wasm")
  })
  assert_eq(index.sources().length(), 2)
  assert_eq(
    run_ide_fixture_rules(index).get("moonbitlang/array_map_fusion"),
    Some(2),
  )
  let selected = @async.with_timeout(600000, () => {
    @provider.export_index(root + "/second/source.mbt", target="wasm")
  })
  assert_eq(selected.sources().length(), 1)
  assert_true(
    selected
    .facts()
    .all(fact => fact.package_name.has_prefix("moongrep/work-second@")),
  )
}

///|
async test "standalone source exports do not require a module manifest" {
  let root = @fs.tmpdir(prefix="moongrep-ide-standalone-")
  defer @fs.rmdir(root, recursive=true)
  let file = root + "/sample.mbtx"
  @fs.write_file(
    file, "fn main { let xs = [1, 2]; ignore(xs.map(x => x + 1).map(x => x * 2)) }\n",
  )
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(file, target="wasm")
  })
  assert_eq(index.sources().length(), 1)
  assert_eq(
    run_ide_fixture_rules(index).get("moonbitlang/array_map_fusion"),
    Some(1),
  )
}
