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
  let counts = run_ide_fixture_rules(
    [root + "/classifiers.mbt", root + "/negative.mbt"],
    @provider.Session::new(target="wasm"),
    only=id,
  )
  assert_eq(counts, Map([(id, 5)]))
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
