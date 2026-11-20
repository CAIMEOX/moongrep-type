///|
test "backend exclusions require a provably false predicate" {
  fn excluded(condition : String, backend : String) -> Bool {
    let tree = @untyped_cst.parse_structure(
      "#cfg(" + condition + ")\npub fn sample() -> Int { 1 }",
    ).root()
    excluded_by_target(@cst.toplevel_nodes(tree)[0], backend)
  }
  assert_true(excluded("not(any(target=\"native\", target=\"wasm\"))", "wasm"))
  assert_false(excluded("not(any(target=\"native\", target=\"wasm\"))", "js"))
  assert_false(excluded("any(feature=\"x\", target=\"native\")", "wasm"))
  assert_true(excluded("all(feature=\"x\", target=\"native\")", "wasm"))
}
