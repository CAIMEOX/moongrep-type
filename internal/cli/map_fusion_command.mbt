///|
pub(all) struct MapFusionOptions {
  index_file : String
  no_color : Bool
  output_json : Bool
}

///|
let map_fusion_command : @argparse.Command = Command(
  "map-fusion",
  about="Find Array.map fusion candidates in a checked semantic index.",
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
      "index",
      action=Set,
      about="Semantic index JSON produced by moongrep semantics.",
    ),
  ],
)

///|
fn map_fusion_cli_options(
  matches : @argparse.Matches,
  env : Map[String, String],
) -> MapFusionOptions raise {
  guard last_cli_value(matches.values, "index") is Some(index_file) &&
    !index_file.trim().is_empty() else {
    raise new_usage_error("missing map-fusion --index")
  }
  {
    index_file,
    no_color: no_color_enabled(env),
    output_json: cli_flag_enabled(matches.flags, "json"),
  }
}

///|
priv struct JsonMapFusionFile {
  file : String
  report : Json
} derive(ToJson)

///|
priv struct JsonMapFusionOutput {
  schema_version : Int
  compiler_version : String
  position_encoding : String
  files : Array[JsonMapFusionFile]
} derive(ToJson)

///|
async fn run_map_fusion_command(options : MapFusionOptions) -> Unit {
  let index = load_semantic_index(options.index_file)
  let reports : Array[(String, @semantic_rules.MapFusionReport)] = []
  for file in index.sources() {
    let source = @semantic_source.Source::parse(
      index,
      file=file.path,
      text=file.text,
    ) catch {
      err => raise new_semantics_input_error(file.path, "\{err}")
    }
    reports.push((file.path, @semantic_rules.find_map_fusion(source)))
  }
  let output = if options.output_json {
    let output : JsonMapFusionOutput = {
      schema_version: 1,
      compiler_version: index.compiler_version(),
      position_encoding: "unicode-scalar",
      files: reports.map(pair => { file: pair.0, report: pair.1.to_json(), }),
    }
    ToJson::to_json(output).stringify()
  } else {
    render_map_fusion_report(index, reports, no_color=options.no_color)
  }
  // Keep both output modes atomic with respect to source freshness checks.
  require_current_semantic_sources(index)
  write_scan_stdout(output + "\n")
}
