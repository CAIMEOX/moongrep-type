///|
async test "standard collection string and map calls match only core operations" {
  let root = @fs.tmpdir(prefix="moongrep-stdlib-calls-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/stdlib-patterns", root)
  let counts = run_ide_fixture_rules(
    [root + "/idioms.mbt", root + "/negative.mbt"],
    @provider.Session::new(target="wasm"),
  )
  for
    (name, expected) in [
      ("collection_is_empty", 3),
      ("string_find_contains", 1),
      ("string_prefix_presence", 1),
      ("string_suffix_presence", 1),
      ("map_get_contains", 1),
      ("array_search_contains", 1),
      ("array_search_by_any", 1),
      ("iter_drop_next", 1),
      ("map_get_default", 1),
    ] {
    assert_eq(counts.get("moonbitlang/" + name), Some(expected), msg=name)
  }
  assert_eq(counts.length(), 9)
}

///|
async test "handwritten Option and Result matches use core constructors and the exact payload binding" {
  let root = @fs.tmpdir(prefix="moongrep-stdlib-match-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/stdlib-patterns", root)
  let counts = run_ide_fixture_rules(
    [root + "/matches.mbt", root + "/negative.mbt"],
    @provider.Session::new(target="wasm"),
  )
  for
    name in [
      "match_option_map", "match_option_bind", "match_option_unwrap_or", "match_option_unwrap_or_else",
      "match_result_map", "match_result_map_err", "match_result_bind", "match_result_to_option",
      "match_result_unwrap_or", "match_result_unwrap_or_else",
    ] {
    let expected = if name == "match_option_map" { 2 } else { 1 }
    assert_eq(counts.get("moonbitlang/" + name), Some(expected), msg=name)
  }
  assert_eq(counts.length(), 10)
}

///|
async test "short circuit loops and exact ASCII bounds resolve at their original expressions" {
  let root = @fs.tmpdir(prefix="moongrep-stdlib-predicates-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/stdlib-patterns", root)
  let counts = run_ide_fixture_rules(
    [root + "/predicates.mbt", root + "/negative.mbt"],
    @provider.Session::new(target="wasm"),
  )
  for
    (name, n) in [
      ("loop_any", 1),
      ("loop_all", 2),
      ("loop_find_first", 1),
      ("char_ascii_digit", 1),
      ("char_ascii_lowercase", 1),
      ("char_ascii_uppercase", 1),
    ] {
    assert_eq(counts.get("moonbitlang/" + name), Some(n), msg=name)
  }
  assert_eq(counts.length(), 6)
}
