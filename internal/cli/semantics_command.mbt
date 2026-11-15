///|
let semantics_command : @argparse.Command = Command(
  "semantics",
  about="Export compiler types, symbols, and source mappings as JSON.",
  arg_required_else_help=true,
  flags=[
    FlagArg(
      "json",
      long="json",
      about="Write diagnostics as JSON Lines; the semantic index is always JSON.",
    ),
  ],
  options=[
    OptionArg(
      "target",
      action=Set,
      about="MoonBit backend to check before querying the official IDE.",
    ),
  ],
  positionals=[
    PositionArg(
      "project-or-file",
      about="MoonBit project directory or source file to check and export.",
      num_args=ValueRange(lower=1, upper=1),
    ),
  ],
)

///|
fn semantics_cli_options(matches : @argparse.Matches) -> SemanticsOptions raise {
  guard last_cli_value(matches.values, "project-or-file") is Some(project) &&
    !project.is_empty() else {
    raise new_usage_error("missing semantics project or file")
  }
  let target = last_cli_value(matches.values, "target")
  if target is Some(value) && value.trim().is_empty() {
    raise new_usage_error("semantics --target must not be empty")
  }
  { project, target, output_json: cli_flag_enabled(matches.flags, "json"), }
}

///|
fn new_semantics_input_error(source : String, reason : String) -> CliError {
  ScanInput(
    diagnostic=new_cli_diagnostic(
      "could not load semantic index",
      Some(source),
      Some(reason),
      Some(
        "check the project with the active MoonBit toolchain and regenerate its IDE semantic index",
      ),
    ),
  )
}

///|
async fn collect_semantics_process(
  executable : String,
  args : Array[String],
) -> (Int32, String, String) {
  let executable = @env.get_env_var("MOON_HOME")
    .map(home => home + "/bin/" + executable)
    .unwrap_or(executable)
  let (status, stdout, stderr) = @process.collect_output(executable, args)
  (status, stdout.text(), stderr.text())
}

///|
async fn semantic_compiler_version(
  run_process : async (String, Array[String]) -> (Int32, String, String),
) -> String {
  let (version_status, version_output, version_error) = run_process("moonc", [
    "-v",
  ]) catch {
    err =>
      raise new_semantics_input_error(
        "moonc",
        "could not read compiler version: \{err}",
      )
  }
  if version_status != 0 {
    raise new_semantics_input_error(
      "moonc",
      "compiler version command exited with status \{version_status}: \{version_error.trim()}",
    )
  }
  let compiler_version = version_output.trim().to_owned()
  if compiler_version.is_empty() {
    raise new_semantics_input_error(
      "moonc", "compiler version command returned no version",
    )
  }
  compiler_version
}

///|
async fn semantic_index_output(
  options : SemanticsOptions,
  generate : async (String, String?) -> @semantic.Index,
) -> String {
  let index = generate(options.project, options.target) catch {
    err =>
      raise new_semantics_input_error(
        options.project,
        "could not query the official IDE: \{err}",
      )
  }
  require_current_semantic_sources(index)
  index.raw_json().stringify()
}

///|
async fn require_current_semantic_sources(index : @semantic.Index) -> Unit {
  for source in index.sources() {
    let current = @fs.read_file(source.path).text() catch {
      err =>
        raise new_semantics_input_error(
          source.path,
          "could not read indexed source: \{err}",
        )
    }
    index.require_source(source.path, current) catch {
      err =>
        raise new_semantics_input_error(
          source.path,
          "source changed since semantic analysis: \{err}",
        )
    }
  }
}

///|
/// Queries the official language service and writes a source-validated index.
pub async fn run_semantics_command(options : SemanticsOptions) -> Unit {
  let output = semantic_index_output(options, (project, target) => {
    @ide.export_index(project, target?)
  })
  @stdio.stdout.write(output + "\n") catch {
    err => raise CliError::output_error("standard output", "\{err}")
  }
}
