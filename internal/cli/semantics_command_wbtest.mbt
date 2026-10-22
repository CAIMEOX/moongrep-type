///|
test "semantics args select explicit reader and preserve path arguments" {
  match
    parse_cli_command([
      "semantics", "project with spaces/file.mbt", "--reader", "reader with spaces",
      "--target", "wasm-gc", "--json",
    ]) {
    Semantics(options) => {
      inspect(options.project, content="project with spaces/file.mbt")
      inspect(options.reader, content="reader with spaces")
      assert_eq(options.target, Some("wasm-gc"))
      assert_true(options.output_json)
    }
    _ => fail("expected semantics command")
  }
}

///|
test "semantics reader environment fallback and command line precedence" {
  let env = { "MOONGREP_SEMANTIC_READER": "env-reader" }
  match parse_cli_command(["semantics", "."], env~) {
    Semantics(options) => {
      inspect(options.reader, content="env-reader")
      assert_true(options.target is None)
      assert_false(options.output_json)
    }
    _ => fail("expected semantics command")
  }
  match
    parse_cli_command(["semantics", ".", "--reader=explicit-reader"], env~) {
    Semantics(options) => inspect(options.reader, content="explicit-reader")
    _ => fail("expected semantics command")
  }
}

///|
test "semantics rejects missing reader and invalid argument combinations" {
  expect_cli_usage(["semantics", "."], 2)
  expect_cli_usage(["semantics", ".", "--reader", ""], 2)
  expect_cli_usage(["semantics", ".", "--reader"], 2)
  expect_cli_usage(["semantics", "--reader", "reader"], 2)
  expect_cli_usage(["semantics", "a", "b", "--reader", "reader"], 2)
  expect_cli_usage(["semantics", ".", "--reader", "reader", "--target", ""], 2)
}

///|
test "semantics JSON diagnostics respect the option terminator" {
  assert_true(output_json_requested(["semantics", ".", "--json"]))
  assert_false(output_json_requested(["semantics", "--", "--json"]))
  assert_true(
    semantics_command.render_help().contains("MOONGREP_SEMANTIC_READER"),
  )
}

///|
fn semantics_test_options() -> SemanticsOptions {
  {
    project: "project;with spaces",
    reader: "reader with spaces",
    target: Some("native"),
    output_json: true,
  }
}

///|
async test "semantics reader failure preserves status and diagnostic without accepting stdout" {
  let calls : Array[(String, Array[String])] = []
  let options = semantics_test_options()
  try
    semantic_index_output(options, (executable, args) => {
      calls.push((executable, args))
      if executable == "moonc" {
        (0, "test-compiler (test-date)\n", "")
      } else {
        (9, "{}", "compiler artifact is incompatible\n")
      }
    })
  catch {
    CliError::ScanInput(..) as err => {
      assert_eq(err.exit_code(), 6)
      assert_true(err.to_string().contains("reader exited with status 9"))
      assert_true(err.to_string().contains("compiler artifact is incompatible"))
    }
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected reader failure")
  }
  assert_eq(calls, [
    ("moonc", ["-v"]),
    (
      "reader with spaces",
      ["--project", "project;with spaces", "--target", "native"],
    ),
  ])
}

///|
async test "semantics rejects malformed successful reader output" {
  try
    semantic_index_output(semantics_test_options(), (executable, _) => {
      if executable == "moonc" {
        (0, "test-compiler\n", "")
      } else {
        (0, "not a semantic index", "")
      }
    })
  catch {
    CliError::ScanInput(..) as err =>
      assert_true(err.to_string().contains("invalid reader output"))
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected schema validation failure")
  }
}

///|
async test "semantics stops before reader when compiler version fails" {
  let calls : Array[String] = []
  try
    semantic_index_output(semantics_test_options(), (executable, _) => {
      calls.push(executable)
      (4, "", "version unavailable")
    })
  catch {
    CliError::ScanInput(..) as err =>
      assert_true(
        err
        .to_string()
        .contains("compiler version command exited with status 4"),
      )
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected version failure")
  }
  assert_eq(calls, ["moonc"])
}

///|
async test "semantics reports executable launch failures as scan input errors" {
  try
    semantic_index_output(semantics_test_options(), (executable, _) => {
      if executable == "moonc" {
        (0, "test-compiler", "")
      } else {
        fail("reader executable missing")
      }
    })
  catch {
    CliError::ScanInput(..) as err => {
      assert_eq(err.exit_code(), 6)
      assert_true(err.to_string().contains("could not run reader"))
    }
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected launch failure")
  }
}

///|
fn semantics_empty_index(compiler_version : String) -> String {
  let value : Json = {
    "schema_version": 1,
    "compiler_version": compiler_version,
    "position_encoding": "unicode-scalar",
    "sources": [],
    "types": [],
    "symbols": [],
    "facts": [],
  }
  value.stringify()
}

///|
async test "semantics accepts a validated snapshot and preserves reader diagnostics" {
  let expected = semantics_empty_index("test-compiler (test-date)")
  let (output, diagnostics) = semantic_index_output(semantics_test_options(), (
    executable,
    _,
  ) => {
    if executable == "moonc" {
      (0, "test-compiler (test-date)\n", "")
    } else {
      (0, expected + "\n", "reader warning\n")
    }
  })
  assert_eq(@json.parse(output), @json.parse(expected))
  inspect(diagnostics, content="reader warning\n")
}

///|
async test "semantics rejects reader compiler identity mismatch" {
  try
    semantic_index_output(semantics_test_options(), (executable, _) => {
      if executable == "moonc" {
        (0, "active-compiler", "")
      } else {
        (0, semantics_empty_index("different-compiler"), "")
      }
    })
  catch {
    CliError::ScanInput(..) as err => {
      assert_true(err.to_string().contains("invalid reader output"))
      assert_true(err.to_string().contains("different-compiler"))
    }
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected compiler mismatch")
  }
}

///|
async test "semantics compares indexed source against the current file" {
  let path = @fs.realpath("e2etests/testdata/semantics/mock-reader.mjs")
  let current = @fs.read_file(path).text()
  let snapshot : Json = {
    "schema_version": 1,
    "compiler_version": "test-compiler",
    "position_encoding": "unicode-scalar",
    "sources": [{ "path": path, "text": current }],
    "types": [],
    "symbols": [],
    "facts": [],
  }
  let (output, _) = semantic_index_output(semantics_test_options(), (
    executable,
    _,
  ) => {
    if executable == "moonc" {
      (0, "test-compiler", "")
    } else {
      (0, snapshot.stringify(), "")
    }
  })
  assert_eq(@json.parse(output), snapshot)
  guard snapshot is Object(fields) else { fail("expected test snapshot") }
  fields["sources"] = [{ "path": path, "text": "changed source" }]
  try
    semantic_index_output(semantics_test_options(), (executable, _) => {
      if executable == "moonc" {
        (0, "test-compiler", "")
      } else {
        (0, snapshot.stringify(), "")
      }
    })
  catch {
    CliError::ScanInput(..) as err => {
      assert_eq(err.exit_code(), 6)
      assert_true(
        err.to_string().contains("source changed since semantic analysis"),
      )
    }
    err => fail("unexpected error: \{err}")
  } noraise {
    _ => fail("expected stale source failure")
  }
}
