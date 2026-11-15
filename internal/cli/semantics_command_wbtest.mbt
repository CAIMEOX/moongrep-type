///|
test "semantics uses the official IDE without an external reader" {
  guard parse_cli_command([
      "semantics", "project with spaces", "--target", "native", "--json",
    ])
    is Semantics(options) else {
    fail("expected semantics")
  }
  assert_eq(options.project, "project with spaces")
  assert_eq(options.target, Some("native"))
  assert_true(options.output_json)
  assert_true(output_json_requested(["semantics", ".", "--json"]))
  assert_false(output_json_requested(["semantics", ".", "--", "--json"]))
}

///|
test "semantics rejects removed reader flags and missing input" {
  for
    args in [
      ["semantics"],
      ["semantics", ".", "--reader", "old-reader"],
      ["semantics", ".", "--target", ""],
    ] {
    let rejected = try {
      ignore(parse_cli_command(args))
      false
    } catch {
      Usage(..) => true
      error => raise error
    }
    assert_true(rejected)
  }
}

///|
fn semantics_test_options() -> SemanticsOptions {
  { project: "project", target: Some("wasm"), output_json: true, }
}

///|
fn semantics_fixture_index(
  file : String?,
  text~ : String = "",
) -> @semantic.Index raise {
  let sources : Array[Json] = match file {
    Some(file) => [{ "path": file, "text": text }]
    None => []
  }
  @semantic.Index::from_json(
    {
      "schema_version": 1,
      "provider": "moon-ide",
      "compiler_version": "fixture",
      "position_encoding": "unicode-scalar",
      "sources": sources,
      "types": [],
      "symbols": [],
      "facts": [],
    },
    compiler_version="fixture",
  )
}

///|
async test "semantics forwards project and backend and preserves the validated index" {
  let index = semantics_fixture_index(None)
  let output = semantic_index_output(semantics_test_options(), (project, target) => {
    assert_eq(project, "project")
    assert_eq(target, Some("wasm"))
    index
  })
  assert_eq(output, index.raw_json().stringify())
}

///|
async test "semantics wraps IDE transport failures as scan input errors" {
  let error = try {
    ignore(
      semantic_index_output(semantics_test_options(), (_, _) => {
        fail("server stopped")
      }),
    )
    None
  } catch {
    ScanInput(diagnostic~) => Some(diagnostic)
    error => raise error
  }
  guard error is Some(Fields(summary~, reason=Some(reason), ..)) else {
    fail("expected source diagnostic")
  }
  assert_eq(summary, "could not load semantic index")
  assert_true(reason.contains("server stopped"))
}

///|
async test "semantics checks source freshness before publishing" {
  let directory = @fs.tmpdir(prefix="moongrep-semantics-fresh-")
  defer @fs.rmdir(directory, recursive=true)
  let file = @fs.realpath(directory) + "/source.mbt"
  @fs.write_file(file, "fn sample { 1 }\n")
  let index = semantics_fixture_index(Some(file), text="fn sample { 1 }\n")
  ignore(semantic_index_output(semantics_test_options(), (_, _) => index))
  @fs.write_file(file, "fn sample { 2 }\n")
  let stale = try {
    ignore(semantic_index_output(semantics_test_options(), (_, _) => index))
    false
  } catch {
    ScanInput(..) => true
    error => raise error
  }
  assert_true(stale)
}

///|
async test "external snapshots still require an independent active compiler version" {
  let version = semantic_compiler_version((program, args) => {
    assert_eq(program, "moonc")
    assert_eq(args, ["-v"])
    (0, "fixture-compiler\n", "")
  })
  assert_eq(version, "fixture-compiler")
  for output in [(1, "", "failed"), (0, "  ", "")] {
    let rejected = try {
      ignore(semantic_compiler_version((_, _) => output))
      false
    } catch {
      ScanInput(..) => true
      error => raise error
    }
    assert_true(rejected)
  }
}
