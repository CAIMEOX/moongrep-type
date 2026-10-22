///|
test "map fusion reuses CLI options and NO_COLOR" {
  match
    parse_cli_command(
      ["map-fusion", "--index=project with spaces/index.json", "--json"],
      env={ "NO_COLOR": "1" },
    ) {
    MapFusion(options) => {
      inspect(options.index_file, content="project with spaces/index.json")
      assert_true(options.no_color)
      assert_true(options.output_json)
    }
    _ => fail("expected map-fusion command")
  }
  match parse_cli_command(["map-fusion", "--index", "last"]) {
    MapFusion(options) => {
      inspect(options.index_file, content="last")
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
  expect_cli_usage(["map-fusion", "--index", "first", "--index", "last"], 2)
  assert_true(output_json_requested(["map-fusion", "--json"]))
  assert_false(output_json_requested(["map-fusion", "--", "--json"]))
}
