///|
async test "workspace selection respects explicit manifests and the off override" {
  let temporary = @fs.tmpdir(prefix="moongrep-workspace-selection-")
  defer @fs.rmdir(temporary, recursive=true)
  let root = @fs.realpath(temporary)
  @fs.mkdir(root + "/module")
  @fs.write_file(root + "/moon.work", "members = [\"./module\"]\n")
  @fs.write_file(root + "/module/moon.mod", "name = \"probe/workspace\"\n")
  assert_eq(config_root(root + "/module", None), (root, false))
  assert_eq(
    config_root(root + "/module", Some("off")),
    (root + "/module", true),
  )
  @fs.mkdir(root + "/external")
  @fs.write_file(root + "/external/moon.work", "members = []\n")
  assert_eq(
    config_root(root + "/module", Some(root + "/external/moon.work")),
    (root + "/external", false),
  )
}

///|
async test "nested modules with shell punctuation keep their own check root" {
  let temporary = @fs.tmpdir(prefix="moongrep-nested-module-")
  defer @fs.rmdir(temporary, recursive=true)
  let root = @fs.realpath(temporary)
  let nested = root + "/source with spaces;literal"
  @fs.mkdir(nested)
  @fs.write_file(root + "/moon.mod", "name = \"probe/outer\"\n")
  @fs.write_file(nested + "/moon.mod", "name = \"probe/nested\"\n")
  assert_eq(@fs.realpath(nested), nested)
  @fs.write_file(
    root + "/moon.work",
    "// Unrelated parent workspace\nmembers = [\".\"]\n",
  )
  assert_eq(config_root(nested, None), (nested, true))
}

///|
async test "input validation rejects changed sources and newly added configuration" {
  let root = @fs.tmpdir(prefix="moongrep-snapshot-inputs-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(root + "/source.mbt", "fn unchanged { () }\n")
  let snapshots : Map[String, Bytes?] = Map([
    (root + "/source.mbt", Some(@fs.read_file(root + "/source.mbt").binary())),
    (root + "/moon.pkg", None),
  ])
  require_unchanged(snapshots)
  let before = source_membership(root)
  @fs.write_file(root + "/moon.pkg", "")
  let rejected = try {
    require_unchanged(snapshots)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(source_membership(root) != before)
  snapshots[root + "/moon.pkg"] = Some(b"")
  @fs.write_file(root + "/source.mbt", "fn changed { () }\n")
  let rejected = try {
    require_unchanged(snapshots)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
