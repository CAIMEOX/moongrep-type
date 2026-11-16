///|
test "map fusion reuses CLI options and NO_COLOR" {
  match
    parse_cli_command(["map-fusion", "project with spaces", "--json"], env={
      "NO_COLOR": "1",
    }) {
    MapFusion(options) => {
      inspect(options.path, content="project with spaces")
      assert_true(options.no_color)
      assert_true(options.output_json)
    }
    _ => fail("expected map-fusion command")
  }
  match parse_cli_command(["map-fusion", "last"]) {
    MapFusion(options) => {
      inspect(options.path, content="last")
      assert_false(options.no_color)
      assert_false(options.output_json)
    }
    _ => fail("expected map-fusion command")
  }
}

///|
test "map fusion reuses usage errors and JSON diagnostic selection" {
  expect_cli_usage(["map-fusion", "--json"], 2)
  expect_cli_usage(["map-fusion", "--index", ""], 2)
  expect_cli_usage(["map-fusion", "--index"], 2)
  expect_cli_usage(["map-fusion", "--index", "index.json", "--unknown"], 2)
  expect_cli_usage(["map-fusion", "one", "two"], 2)
  assert_true(output_json_requested(["map-fusion", "--json"]))
  assert_false(output_json_requested(["map-fusion", "--", "--json"]))
}
