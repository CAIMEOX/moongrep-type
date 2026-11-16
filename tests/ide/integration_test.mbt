///|
async fn copy_ide_fixture(source : String, destination : String) -> Unit {
  @fs.mkdir(destination, recursive=true, allow_exist=true)
  for name in @fs.readdir(source) {
    if name.has_prefix(".") ||
      ["_build", "target", "node_modules"].contains(name) ||
      name.has_suffix("_test.mbt") ||
      name.has_suffix("_wbtest.mbt") {
      continue
    }
    let input = source + "/" + name
    let output = destination + "/" + name
    if @fs.kind(input) is Directory {
      copy_ide_fixture(input, output)
    } else if name.has_suffix(".mbt") ||
      name == "moon.mod" ||
      name == "moon.pkg" {
      @fs.write_file(output, @fs.read_file(input))
    }
  }
}

///|
async fn candidate_file(
  file : String,
  rules : Array[@rule_model.CompiledRule],
) -> @semantic_rules.Candidates {
  let text = @fs.read_file(file).text()
  let tree = @untyped_cst.parse_structure(text, name=file).root()
  let roots = @cst.toplevel_nodes(tree).filter(root => {
    !@cst.attributes(root).any(a => {
      a.qualifier == Some("moongrep") && a.name == "skip" && a.raw_payload == ""
    })
  })
  @semantic_rules.Candidates::select(file, text, tree, roots, rules[:])
}

///|
async fn fixture_files(root : String) -> Array[String] {
  let files = []
  for name in @fs.readdir(root, sort=true) {
    if name.has_prefix(".") ||
      ["_build", "target", "node_modules"].contains(name) {
      continue
    }
    let path = root + "/" + name
    if @fs.kind(path) is Directory {
      files.append(fixture_files(path))
    } else if name.has_suffix(".mbt") || name.has_suffix(".mbtx") {
      files.push(path)
    }
  }
  files
}

///|
async fn run_ide_fixture_rules(
  files : Array[String],
  session : @provider.Session,
  only? : String,
) -> Map[String, Int32] {
  let loaded = @builtin.load_semantic_rules()
  let rules = @compile.compile_rules(
    loaded.filter(r => only is None || only == Some(r.rule_id)),
  )
  let counts : Map[String, Int32] = Map([])
  let candidates = []
  for file in files {
    candidates.push(candidate_file(file, rules))
  }
  for i, candidate in candidates {
    let result = candidate.verify(session)
    for warning in result.warnings {
      fail("\{warning.rule_id}: \{files[i]}: \{warning.reason}")
    }
    for finding in result.findings {
      assert_eq(finding.file, files[i])
      assert_true(
        finding.loc.start.lnum >= 1 &&
        finding.loc.start.cnum < finding.loc.end.cnum,
      )
      if files[i].has_suffix("/negative.mbt") {
        fail("negative source matched " + finding.rule_id)
      }
      counts[finding.rule_id] = counts.get(finding.rule_id).unwrap_or(0) + 1
    }
  }
  session.validate()
  counts
}

///|
#cfg(target="native")
async test "official IDE preserves seven collection checks and all eighteen findings" {
  let root = @fs.tmpdir(prefix="moongrep-ide-collections-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/semantic-rules", root)
  let session = @provider.Session::new(target="wasm")
  let counts = run_ide_fixture_rules(fixture_files(root), session)
  for
    (name, expected) in [
      ("prefer_array_comprehension", 6),
      ("prefer_filter_map_comprehension", 2),
      ("prefer_iter_comprehension", 3),
      ("avoid_collect_for_count", 3),
      ("discarded_array_map", 1),
      ("consumed_iterator", 2),
      ("array_map_fusion", 1),
    ] {
    assert_eq(counts.get("moonbitlang/" + name), Some(expected), msg=name)
  }
  assert_eq(counts.length(), 7)
}

///|
#cfg(target="native")
async test "official IDE preserves twenty theorems forty findings and source identity" {
  let root = @fs.tmpdir(prefix="moongrep-ide-theorems-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/semantic-theorems", root)
  let session = @provider.Session::new(target="wasm")
  let counts = run_ide_fixture_rules(fixture_files(root), session)
  for
    (name, expected) in [
      ("array_filter_count", 4),
      ("iter_filter_count", 1),
      ("iter_filter_next", 1),
      ("iter_find_first_exists", 10),
      ("iter_map_flatten", 2),
      ("option_map_fusion", 3),
      ("result_map_fusion", 1),
      ("result_map_err_fusion", 1),
      ("option_bind_map", 3),
      ("result_bind_map", 1),
      ("result_map_flatten", 2),
      ("option_filter_fusion", 1),
      ("option_map_default", 1),
      ("option_map_identity", 1),
      ("result_map_identity", 2),
      ("option_bind_identity", 2),
      ("result_bind_identity", 1),
      ("option_unwrap_some", 1),
      ("result_unwrap_ok", 1),
      ("result_unwrap_err", 1),
    ] {
    assert_eq(counts.get("moonbitlang/" + name), Some(expected), msg=name)
  }
  assert_eq(counts.length(), 20)
}

///|
#cfg(target="native")
async test "map fusion shares the official IDE evidence and keeps review obligations" {
  let root = @fs.tmpdir(prefix="moongrep-ide-maps-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("tools/map-fusion/fixture", root)
  let session = @provider.Session::new(target="wasm")
  let rules = @compile.compile_rules(
    @builtin.load_semantic_rules().filter(r => {
      r.rule_id == "moonbitlang/array_map_fusion"
    }),
  )
  let mut candidates = 0
  let mut skipped = 0
  for file in fixture_files(root) {
    let report = candidate_file(file, rules).map_fusion(session)
    candidates += report.candidates.length()
    skipped += report.skipped.length()
    for hit in report.candidates {
      assert_true(hit.outer_call.text.contains(".map("))
    }
  }
  session.validate()
  assert_eq(candidates, 8)
  assert_eq(skipped, 4)
}
