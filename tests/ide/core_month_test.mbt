///|
async test "numeric, iteration and text rules distinguish standard operations from lookalikes" {
  let root = @fs.tmpdir(prefix="moongrep-core-month-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/core-month", root)
  let session = @provider.Session::new(target="wasm")
  for
    (rule, file, expected) in [
      ("float_finiteness", "numbers.mbt", 3),
      ("iter_next_loop", "loops.mbt", 2),
      ("direct_view_iteration", "loops.mbt", 2),
      ("slice_to_end", "text.mbt", 3),
      ("builder_stream_interpolation", "text.mbt", 1),
      ("integer_min", "numbers.mbt", 2),
      ("integer_max", "numbers.mbt", 3),
    ] {
    let id = "moonbitlang/" + rule
    let counts = run_ide_fixture_rules(
      [root + "/" + file, root + "/negative.mbt"],
      session,
      only=id,
    )
    assert_eq(counts, Map([(id, expected)]), msg=rule)
  }
}

///|
async test "backend-specific numerical comparisons are checked only when active" {
  let root = @fs.tmpdir(prefix="moongrep-month-cfg-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/core-month", root)
  let id = "moonbitlang/integer_min"
  let file = root + "/targets.mbt"
  for (backend, expected) in [("wasm", 0), ("native", 1)] {
    let counts = run_ide_fixture_rules(
      [file],
      @provider.Session::new(target=backend),
      only=id,
    )
    assert_eq(counts.get(id).unwrap_or(0), expected, msg=backend)
  }
}
