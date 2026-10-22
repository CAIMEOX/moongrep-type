///|
test "scan and lint accept semantic index and explicit package view" {
  for command in ["scan", "lint"] {
    let parsed = parse_cli_command([
      command, "--semantic-index", "index with spaces.json", "--semantic-view=wbtest",
    ])
    let options = match parsed {
      Scan(options) | Lint(options) => options
      _ => fail("expected scan or lint")
    }
    assert_eq(options.semantic_index, Some("index with spaces.json"))
    inspect(options.semantic_view, content="wbtest")
  }
  expect_cli_usage(["lint", "--semantic-index", ""], 2)
  expect_cli_usage(["lint", "--semantic-view", "wbtest"], 2)
  expect_cli_usage(
    ["lint", "--semantic-index", "index.json", "--semantic-view", "other"],
    2,
  )
}

///|
async test "semantic rule without an index fails before scanning" {
  guard parse_cli_command([
      "scan", "--rule", "internal/rule/lintrules/moonbitlang/avoid_collect_for_count.yaml",
      "missing-scan-root",
    ])
    is Scan(options) else {
    fail("expected scan options")
  }
  let events = []
  try
    scan_events(Scan, options, event => events.push(scan_event_summary(event)))
  catch {
    CliError::Usage(..) as error =>
      assert_true(error.to_string().contains("--semantic-index"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected missing index error")
  }
  assert_true(events.is_empty())
}
