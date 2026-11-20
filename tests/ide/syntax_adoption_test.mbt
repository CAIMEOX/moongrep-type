///|
async test "loop tuple unpack checks the reference set and the new header scope" {
  let root = @fs.tmpdir(prefix="moongrep-tuple-header-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/syntax-adoption", root)
  let id = "moonbitlang/loop_tuple_unpack"
  let counts = run_ide_fixture_rules(
    [root + "/tuples.mbt", root + "/negative.mbt"],
    @provider.Session::new(target="wasm"),
    only=id,
  )
  assert_eq(counts, Map([(id, 3)]))
}

///|
async test "alternative patterns report the whole chain once and exclude overlaps" {
  let root = @fs.tmpdir(prefix="moongrep-pattern-alternatives-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/syntax-adoption", root)
  let id = "moonbitlang/repeated_classifier"
  let file = root + "/grouped.mbt"
  let prefix = "pub fn grouped(n : Int32) -> Bool { "
  let expr = "n == 1 || (n == 2 || n == 3)"
  @fs.write_file(file, prefix + expr + " }\n")
  let session = @provider.Session::new(target="wasm")
  let counts = run_ide_fixture_rules(
    [root + "/classifiers.mbt", root + "/negative.mbt"],
    session,
    only=id,
  )
  assert_eq(counts, Map([(id, 5)]))
  let rules = @compile.compile_rules(
    @builtin.load_semantic_rules().filter(r => r.rule_id == id),
  )
  let report = candidate_file(file, rules).verify(session)
  guard report.findings is [hit] && report.warnings.is_empty() else {
    fail("expected one complete disjunction")
  }
  assert_eq(hit.loc.start.column(), prefix.length() + 1)
  assert_eq(hit.loc.end.column(), prefix.length() + expr.length() + 1)
  session.validate()
}

///|
async test "a broad user shape cannot turn effectful or redundant tests into semantic candidates" {
  let root = @fs.tmpdir(prefix="moongrep-classifier-guards-")
  defer @fs.rmdir(root, recursive=true)
  let file = root + "/sample.mbt"
  @fs.write_file(
    file,
    (
      #|fn pending() {
      #|  let _ = missing() == 1 || missing() == 2
      #|  let _ = left == 1 || right == 2
      #|  chr is ('a'..<='z') || chr == '\u{62}'
      #|}
    ),
  )
  let yaml =
    #|id: any_expr
    #|description: Check all expressions.
    #|semantic:
    #|  check: repeated-classifier
    #|  patterns:
    #|    - shape: $(expr:exp)
  let rules = @compile.compile_rules([
    @rule_model.RawRuleSpec::from_str("/rules/any.yaml", "/rules", yaml),
  ])
  let candidate = candidate_file(file, rules)
  let session = @provider.Session::new(target="wasm")
  assert_false(candidate.is_empty())
  let report = candidate.verify(session)
  assert_true(report.findings.is_empty())
  assert_true(report.warnings.is_empty())
  assert_eq(session.query_count(), 0)
  assert_false(@fs.exists(root + "/_build"))
}

///|
async test "iterator literals require core constructors or an immediate ordinary Array literal" {
  let root = @fs.tmpdir(prefix="moongrep-iterator-literal-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/syntax-adoption", root)
  let id = "moonbitlang/iterator_literal"
  let counts = run_ide_fixture_rules(
    [
      root + "/iterators.mbt",
      root + "/negative.mbt",
      root + "/lookalike/negative.mbt",
    ],
    @provider.Session::new(target="wasm"),
    only=id,
  )
  assert_eq(counts, Map([(id, 3)]))
}

///|
async test "conditional spread needs a private array used only by two pushes and iteration" {
  let root = @fs.tmpdir(prefix="moongrep-conditional-spread-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/syntax-adoption", root)
  let id = "moonbitlang/conditional_array_spread"
  let counts = run_ide_fixture_rules(
    [root + "/spreads.mbt", root + "/negative.mbt"],
    @provider.Session::new(target="wasm"),
    only=id,
  )
  assert_eq(counts, Map([(id, 2)]))
}

///|
async test "blackbox loop evidence needs only the tuple arity of a re-exported payload" {
  let root = @fs.tmpdir(prefix="moongrep-tuple-payload-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/moon.mod", "name = \"moongrep/pairprobe\"\n")
  @fs.write_file(
    root + "/moon.pkg",
    "import { \"moongrep/pairprobe/detail\" @internal_types }\n",
  )
  @fs.mkdir(root + "/detail")
  @fs.write_file(root + "/detail/moon.pkg", "")
  @fs.write_file(root + "/detail/detail.mbt", "pub(all) struct Glyph(Int32)\n")
  @fs.write_file(
    root + "/rows.mbt",
    "pub fn rows() -> Array[(UInt32, @internal_types.Glyph)] { [(1U, @internal_types.Glyph(4))] }\n",
  )
  let file = root + "/rows_test.mbt"
  @fs.write_file(
    file,
    (
      #|test {
      #|  for pair in @pairprobe.rows() {
      #|    let (key, glyph) = pair
      #|    ignore((key, glyph))
      #|  }
      #|}
    ),
  )
  let id = "moonbitlang/loop_tuple_unpack"
  let counts = run_ide_fixture_rules(
    [file],
    @provider.Session::new(target="wasm"),
    only=id,
  )
  assert_eq(counts, Map([(id, 1)]))
}
