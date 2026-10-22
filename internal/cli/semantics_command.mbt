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
      "reader",
      action=Set,
      env="MOONGREP_SEMANTIC_READER",
      about="Semantic reader executable built for the active MoonBit compiler.",
    ),
    OptionArg(
      "target",
      action=Set,
      about="MoonBit target to pass to the reader and moon check.",
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
  guard last_cli_value(matches.values, "reader") is Some(reader) &&
    !reader.trim().is_empty() else {
    raise Usage(
      diagnostic=new_cli_diagnostic(
        "missing semantic reader",
        None,
        None,
        Some(
          "build tools/moonc-reader for the active compiler, then pass --reader or set MOONGREP_SEMANTIC_READER",
        ),
      ),
    )
  }
  let target = last_cli_value(matches.values, "target")
  if target is Some(value) && value.trim().is_empty() {
    raise new_usage_error("semantics --target must not be empty")
  }
  {
    project,
    reader,
    target,
    output_json: cli_flag_enabled(matches.flags, "json"),
  }
}

///|
fn new_semantics_input_error(source : String, reason : String) -> CliError {
  ScanInput(
    diagnostic=new_cli_diagnostic(
      "could not load semantic index",
      Some(source),
      Some(reason),
      Some(
        "check the project and use a reader built for the active moonc version",
      ),
    ),
  )
}

///|
async fn collect_semantics_process(
  executable : String,
  args : Array[String],
) -> (Int, String, String) {
  let (status, stdout, stderr) = @process.collect_output(executable, args)
  (status, stdout.text(), stderr.text())
}

///|
async fn semantic_compiler_version(
  run_process : async (String, Array[String]) -> (Int, String, String),
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
  run_process : async (String, Array[String]) -> (Int, String, String),
) -> (String, String) {
  let compiler_version = semantic_compiler_version(run_process)
  let args = ["--project", options.project]
  if options.target is Some(target) {
    args.push("--target")
    args.push(target)
  }
  let (status, output, diagnostics) = run_process(options.reader, args) catch {
    err =>
      raise new_semantics_input_error(
        options.reader,
        "could not run reader: \{err}",
      )
  }
  if status != 0 {
    let detail = diagnostics.trim()
    let reason = if detail.is_empty() {
      "reader exited with status \{status}"
    } else {
      "reader exited with status \{status}: \{detail}"
    }
    raise new_semantics_input_error(options.reader, reason)
  }
  let index = @semantic.Index::parse(output, compiler_version~) catch {
    err =>
      raise new_semantics_input_error(
        options.project,
        "invalid reader output: \{err}",
      )
  }
  require_current_semantic_sources(index)
  (index.raw_json().stringify(), diagnostics)
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
/// Runs the external reader, validates its index, and writes the complete JSON.
pub async fn run_semantics_command(options : SemanticsOptions) -> Unit {
  let (output, diagnostics) = semantic_index_output(
    options, collect_semantics_process,
  )
  if !diagnostics.trim().is_empty() {
    let message = if options.output_json {
      let record : Json = {
        "type": "warning",
        "category": "semantic_reader",
        "message": diagnostics.trim().to_owned(),
      }
      record.stringify()
    } else {
      diagnostics.trim().to_owned()
    }
    @stdio.stderr.write(message + "\n") catch {
      err => raise CliError::output_error("standard error", "\{err}")
    }
  }
  @stdio.stdout.write(output + "\n") catch {
    err => raise CliError::output_error("standard output", "\{err}")
  }
}
