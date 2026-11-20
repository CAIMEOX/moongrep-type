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
