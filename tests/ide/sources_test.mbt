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
    #|  match self.value.map(x => x) {
    #|    Some(x) => other.value is Some(y) && x == y
    #|    None => other.value is None
    #|  }
    #|}
    #|///|
    #|pub fn implicit_debug(value : Int?) -> Unit raise {
    #|  @debug.debug_inspect(value.map(x => x).unwrap_or(0), content="unused")
    #|}
    #|///|
    #|pub fn manual_array(xs : Array[Int]) -> Array[Int] {
    #|  let _ = "🚀"; xs.map(x => x + 1).map(x => x * 2)
    #|}
  @fs.write_file(root + "/probe.mbt", text.replace_all(old="\n", new="\r\n"))
  let counts = run_ide_fixture_rules(
    fixture_files(root),
    @provider.Session::new(target="wasm"),
  )
  assert_eq(counts.length(), 2)
  assert_eq(counts.get("moonbitlang/option_map_identity"), Some(2))
  assert_eq(counts.get("moonbitlang/array_map_fusion"), Some(1))
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
  let session = @provider.Session::new(target="wasm")
  let counts = run_ide_fixture_rules(fixture_files(root), session)
  assert_eq(counts.get("moonbitlang/array_map_fusion"), Some(3))
  let selected = run_ide_fixture_rules([root + "/source_wbtest.mbt"], session)
  assert_eq(selected.get("moonbitlang/array_map_fusion"), Some(1))
  @fs.write_file(root + "/source.mbt", "pub fn changed() -> Int { 1 }")
  let stale = try {
    session.validate()
    false
  } catch {
    _ => true
  }
  assert_true(stale)
}

///|
async test "a failed project check cannot produce semantic findings" {
  let root = @fs.tmpdir(prefix="moongrep-ide-invalid-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/moon.mod", "name = \"moongrep/invalid-probe\"\n")
  @fs.write_file(root + "/moon.pkg", "")
  @fs.write_file(
    root + "/probe.mbt",
    "pub fn invalid() -> Int { missing_name().filter(x => x).length() }\n",
  )
  let rejected = try {
    ignore(
      run_ide_fixture_rules(
        fixture_files(root),
        @provider.Session::new(target="wasm"),
      ),
    )
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
    let session = @provider.Session::new(target~)
    let file = root + "/probe.mbt"
    let tree = @untyped_cst.parse_structure(text, name=file).root()
    let checked = session.file(file, text, tree).unwrap()
    let nodes = [tree]
    let selected = while nodes.pop() is Some(n) {
      if n.kind is Expr_Apply && @cst.source_text(n, text) == "chosen()" {
        break n
      }
      for (_, child) in n.children {
        nodes.push(child)
      }
    } nobreak {
      fail("missing chosen() in fixture")
    }
    let ty = checked.type_at(selected).unwrap()
    assert_true(
      checked.raw_type(ty)
      is Some({ "kind": "builtin", "name": String(name), .. }) &&
      name == result_type,
    )
    session.validate()
  }
}

///|
async test "workspace candidates retain module ownership and file selection" {
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
    "pub fn only_native(xs : Array[Int]) -> Array[Int] { xs.map(x => x + 1).map(x => x * 2) }\n",
  )
  let session = @provider.Session::new(target="wasm")
  let counts = run_ide_fixture_rules(fixture_files(root), session)
  assert_eq(counts.get("moonbitlang/array_map_fusion"), Some(2))
  let file = root + "/second/source.mbt"
  let text = @fs.read_file(file).text()
  let checked = session
    .file(file, text, @untyped_cst.parse_structure(text).root())
    .unwrap()
  assert_true(checked.package_name().has_prefix("moongrep/work-second@"))
}

///|
async test "standalone source candidates do not require a module manifest" {
  let root = @fs.tmpdir(prefix="moongrep-ide-standalone-")
  defer @fs.rmdir(root, recursive=true)
  let file = root + "/sample.mbtx"
  @fs.write_file(
    file, "fn main { let xs = [1, 2]; ignore(xs.map(x => x + 1).map(x => x * 2)) }\n",
  )
  let counts = run_ide_fixture_rules(
    [file],
    @provider.Session::new(target="wasm"),
  )
  assert_eq(counts.get("moonbitlang/array_map_fusion"), Some(1))
}

///|
async test "YAML shapes and guards precede project checks; overlapping rules share IDE queries" {
  let root = @fs.tmpdir(prefix="moongrep-candidate-budget-")
  defer @fs.rmdir(root, recursive=true)
  let file = root + "/source.mbt"
  let rules = @compile.compile_rules(
    @builtin.load_semantic_rules().filter(r => {
      r.rule_id == "moonbitlang/array_filter_count"
    }),
  )
  let session = @provider.Session::new(target="wasm")
  @fs.write_file(file, "pub fn unrelated() -> Int { broken(123) }")
  let empty = candidate_file(file, rules)
  assert_true(empty.is_empty())
  assert_true(empty.verify(session).findings.is_empty())
  // The builtin shape admits any map, but this lambda cannot be an identity.
  @fs.write_file(file, "fn unused() { missing.map(x => x + 1) }")
  let identities = @compile.compile_rules(
    @builtin.load_semantic_rules().filter(r => {
      r.rule_id == "moonbitlang/option_map_identity"
    }),
  )
  let broad = candidate_file(file, identities)
  assert_false(broad.is_empty())
  assert_true(broad.verify(session).findings.is_empty())
  let yaml =
    #|id: count
    #|description: Only match selected receivers.
    #|semantic:
    #|  check: array-filter-count
    #|  patterns:
    #|    - shape: $(xs:id).filter($(p:exp)).length()
    #|      guard:
    #|        $xs: '^selected$'
  let guarded = @compile.compile_rules([
    @rule_model.RawRuleSpec::from_str("/rules/count.yaml", "/rules", yaml),
  ])
  @fs.write_file(file, "fn f() { other.filter(missing).length() }")
  let rejected = candidate_file(file, guarded)
  assert_true(rejected.is_empty())
  assert_true(rejected.verify(session).findings.is_empty())
  assert_false(@fs.exists(root + "/_build"))
  assert_eq(session.query_count(), 0)
  @fs.write_file(root + "/moon.mod", "name = \"probe/budget\"\n")
  @fs.write_file(root + "/moon.pkg", "")
  let text =
    #|pub fn f(xs : Array[Int], p : (Int) -> Bool) -> Int {
    #|  ignore(xs.length() + 123)
    #|  xs.filter(p).length()
    #|}
  @fs.write_file(file, text)
  let dup = { ..rules[0], rule_id: "custom/also_count", }
  let result = @async.with_timeout(60000, () => {
    candidate_file(file, [rules[0], dup]).verify(session)
  })
  assert_eq(result.findings.length(), 2)
  assert_eq(result.warnings.length(), 0)
  assert_eq(session.query_count(), 6)
  session.validate()
}
