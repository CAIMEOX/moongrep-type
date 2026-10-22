///|
#cfg(target="wasm")
fn runtime_exit(code : Int32) -> Unit = "moonbitlang/async" "runtime/exit"

///|
#cfg(target="native")
extern "c" fn runtime_exit(code : Int32) -> Unit = "exit"

///|
async fn write_raw_cli_stdout(output : String) -> Unit {
  if output != "" {
    if output.strip_suffix("\n") is Some(_) {
      @stdio.stdout.write(output)
    } else {
      @stdio.stdout.write(output + "\n")
    }
  }
}

///|
async fn write_raw_cli_stderr(output : String) -> Unit {
  if output != "" {
    if output.strip_suffix("\n") is Some(_) {
      @stdio.stderr.write(output)
    } else {
      @stdio.stderr.write(output + "\n")
    }
  }
}

///|
#warnings("-alert_internal")
fn cli_errno_reason(errno : Int32) -> String {
  @os_error.errno_to_string(errno)
}

///|
async fn write_cli_stdout(output : String) -> Unit {
  write_raw_cli_stdout(output) catch {
    @os_error.OSError(errno, ..) =>
      raise CliError::output_error("standard output", cli_errno_reason(errno))
    err => raise err
  }
}

///|
async fn exit_with_cli_error(error : CliError, output_json : Bool) -> Unit {
  let exit_code = error.exit_code()
  let rendered = if output_json { error.render_json() } else { "\{error}" }
  write_raw_cli_stderr(rendered) catch {
    @os_error.OSError(_) => runtime_exit(7)
    err => raise err
  }
  runtime_exit(exit_code)
}

///|
async fn dispatch_cli(argv : Array[String], env : Map[String, String]) -> Unit {
  let command = parse_cli_command(argv, env~)
  match command {
    Scan(options) => run_scan_command(options)
    Lint(options) => run_lint_command(options)
    Semantics(options) => run_semantics_command(options)
    MapFusion(options) => run_map_fusion_command(options)
    DocsList | DocsShow(_) => write_cli_stdout(render_docs_command(command))
    DumpImpl(..) | DumpExpr(..) =>
      write_cli_stdout(render_dump_command(command))
  }
}

///|
/// Shared process entrypoint for moongrep and its compatibility commands.
pub async fn run_cli(
  argv : Array[String],
  env~ : Map[String, String] = Map([]),
) -> Unit {
  let output_json = output_json_requested(argv)
  dispatch_cli(argv, env) catch {
    CliError::Internal(..) as err => exit_with_cli_error(err, output_json)
    CliError::Usage(..) as err => exit_with_cli_error(err, output_json)
    CliError::DumpInput(..) as err => exit_with_cli_error(err, output_json)
    CliError::RuleSource(..) as err => exit_with_cli_error(err, output_json)
    CliError::RuleContent(..) as err => exit_with_cli_error(err, output_json)
    CliError::ScanInput(..) as err => exit_with_cli_error(err, output_json)
    CliError::Output(..) as err => exit_with_cli_error(err, output_json)
    err => exit_with_cli_error(CliError::internal("\{err}"), output_json)
  }
}
