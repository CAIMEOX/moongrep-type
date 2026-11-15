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
fn ide_fixture_sources(
  index : @semantic.Index,
  file : String,
) -> @semantic_source.Source raise {
  let source = index.source(file).unwrap()
  @semantic_source.Source::parse(index, file~, text=source.text)
}

///|
fn run_ide_fixture_rules(index : @semantic.Index) -> Map[String, Int32] raise {
  let rules = @compile.compile_rules(@builtin.load_semantic_rules())
  let counts : Map[String, Int32] = Map([])
  for input in index.sources() {
    let source = ide_fixture_sources(index, input.path)
    let roots = @cst.toplevel_nodes(source.root()).filter(root => {
      !@cst.attributes(root).any(attribute => {
        attribute.qualifier == Some("moongrep") && attribute.name == "skip"
      })
    })
    let report = @semantic_rules.apply_rules(source, rules[:], roots~)
    for warning in report.warnings {
      fail("\{warning.rule_id}: \{input.path}: \{warning.reason}")
    }
    for finding in report.findings {
      counts[finding.rule_id] = counts.get(finding.rule_id).unwrap_or(0) + 1
      let location = source.range_for_node(
        roots
        .iter()
        .find_first(root => {
          root.loc.start.cnum <= finding.loc.start.cnum &&
          root.loc.end.cnum >= finding.loc.end.cnum
        })
        .unwrap(),
      )
      assert_eq(location.file, input.path)
      assert_true(finding.loc.start.lnum >= 1)
      if input.path.has_suffix("/negative.mbt") {
        fail("negative source matched \{finding.rule_id}")
      }
    }
  }
  counts
}

///|
#cfg(target="native")
async test "official IDE preserves seven collection checks and all eighteen findings" {
  let root = @fs.tmpdir(prefix="moongrep-ide-collections-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("examples/semantic-rules", root)
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(root, target="wasm")
  })
  let counts = run_ide_fixture_rules(index)
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
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(root, target="wasm")
  })
  let counts = run_ide_fixture_rules(index)
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
  assert_true(
    index
    .symbols()
    .any(symbol => symbol.kind == "local" && symbol.name == "value"),
  )
}

///|
#cfg(target="native")
async test "map fusion shares the official IDE evidence and keeps review obligations" {
  let root = @fs.tmpdir(prefix="moongrep-ide-maps-")
  defer @fs.rmdir(root, recursive=true)
  copy_ide_fixture("tools/map-fusion/fixture", root)
  let index = @async.with_timeout(600000, () => {
    @provider.export_index(root, target="wasm")
  })
  let mut candidates = 0
  let mut skipped = 0
  for input in index.sources() {
    let report = @semantic_rules.find_map_fusion(
      ide_fixture_sources(index, input.path),
    )
    candidates += report.candidates.length()
    skipped += report.skipped.length()
    for candidate in report.candidates {
      assert_true(
        index
        .facts()
        .any(fact => {
          fact.id == candidate.outer_call.fact_id && fact.node_kind == "call"
        }),
      )
    }
  }
  assert_eq(candidates, 8)
  assert_eq(skipped, 4)
}
