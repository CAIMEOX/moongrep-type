///|
test "scan and lint select a backend without indexing flags" {
  for command in ["scan", "lint"] {
    let parsed = parse_cli_command([command, ".", "--target=native"])
    let options = match parsed {
      Scan(opts) | Lint(opts) => opts
      _ => fail("scan options")
    }
    assert_eq(options.target, Some("native"))
    expect_cli_usage([command, ".", "--target=all"], 2)
    expect_cli_usage([command, ".", "--semantic-index=old.json"], 2)
  }
}

///|
async test "an enabled semantic rule with no candidates never invokes the compiler" {
  let dir = @fs.tmpdir(prefix="moongrep-candidates-empty-")
  defer @fs.rmdir(dir, recursive=true)
  // No manifest and an unbound name would fail a check.
  @fs.write_file(
    dir + "/unrelated.mbt",
    "fn unused() -> Int { undefined_name(1) }",
  )
  guard parse_cli_command([
      "scan", dir, "--rule", "internal/rule/lintrules/moonbitlang/array_filter_count.yaml",
    ])
    is Scan(options) else {
    fail("scan options")
  }
  let events = []
  scan_events(Scan, options, e => events.push(scan_event_summary(e)))
  assert_true(events.is_empty())
  let candidate = "fn unused() -> Int { missing.filter(p).length() }"
  @fs.write_file(dir + "/unrelated.mbt", "#moongrep.skip\n" + candidate)
  scan_events(Scan, options, e => events.push(scan_event_summary(e)))
  @fs.write_file(dir + "/unrelated.mbt", candidate)
  scan_events(Scan, { ..options, disabled_rules: ["array_filter_count"], }, e => {
    events.push(scan_event_summary(e))
  })
  assert_true(events.is_empty())
  assert_false(@fs.exists(dir + "/_build"))
}
