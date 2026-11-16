///|
pub(all) struct MapFusionOptions {
  path : String
  target : String?
  no_color : Bool
  output_json : Bool
}

///|
let map_fusion_command : @argparse.Command = Command(
  "map-fusion",
  about="Find and explain Array.map fusion candidates in MoonBit source.",
  arg_required_else_help=true,
  flags=[
    FlagArg(
      "json",
      long="json",
      about="Write the full report as JSON and diagnostics as JSON Lines.",
    ),
  ],
  options=[
    OptionArg(
      "target",
      action=Set,
      about="MoonBit backend for checking semantic candidates.",
    ),
  ],
  positionals=[
    PositionArg(
      "path",
      about="Source file or directory to scan.",
      num_args=ValueRange(lower=1, upper=1),
    ),
  ],
)

///|
fn map_fusion_cli_options(
  matches : @argparse.Matches,
  env : Map[String, String],
) -> MapFusionOptions raise {
  guard last_cli_value(matches.values, "path") is Some(path) &&
    !path.trim().is_empty() else {
    raise new_usage_error("missing map-fusion source path")
  }
  {
    path,
    target: semantic_target(matches),
    no_color: no_color_enabled(env),
    output_json: cli_flag_enabled(matches.flags, "json"),
  }
}

///|
async fn run_map_fusion_command(options : MapFusionOptions) -> Unit {
  let rules = @rule_compile.compile_rules(
    @rule_builtin.load_semantic_rules().filter(rule => {
      rule.rule_id == "moonbitlang/array_map_fusion"
    }),
  )
  let plan = @rule_apply.ScanPlan::from_rules(rules)
  let pending = []
  let receive : async (ScanEvent) -> Unit = event => {
    if event is Warning(warning) {
      let rendered = if options.output_json {
        render_scan_warning_json(warning)
      } else {
        render_scan_warning(warning)
      }
      write_scan_stderr(rendered + "\n")
    }
  }
  visit_scan_sources(normalize_scan_root(options.path), [], false, receive, file => {
    let text = read_text_file(file)
    let file_plan = plan.filter_source(text)
    if !file_plan.is_empty() &&
      select_semantic_file(file, text, file_plan, receive) is Some(input) {
      pending.push(input)
    }
  })
  let target = options.target
  let session = @ide.Session::new(target?)
  let reports = []
  for input in pending {
    let report = input.candidates.map_fusion(session) catch {
      err =>
        raise new_scan_input_error(input.path, "verify map fusion", "\{err}")
    }
    reports.push((input.path, input.text, report))
  }
  session.validate() catch {
    err =>
      raise new_scan_input_error(
        options.path,
        "validate semantic inputs",
        "\{err}",
      )
  }
  let output = if options.output_json {
    (
      {
        "schema_version": 2,
        "position_encoding": "unicode-scalar",
        "files": reports.map(item => {
          ({ "file": item.0, "report": item.2.to_json() } : Json)
        }),
      } : Json).stringify()
  } else {
    render_map_fusion_report(
      reports,
      session.parameter_names(),
      no_color=options.no_color,
    )
  }
  write_scan_stdout(output + "\n")
}
