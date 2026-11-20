///|
// Scanner-local result type. The rule model boundary is `rule_model.RuleFinding`;
// scan diagnostics stay here as warnings for the CLI renderer.
priv struct ParseWarning {
  file : String
  block_start_line : Int32?
  reason : String
}

///|
priv enum ScanWarning {
  Parse(ParseWarning)
  TaintIncomplete(@rule_apply.TaintDiagnostic)
  InvalidMoongrepSkipPayload(String, @basic.Location)
  Semantic(
    file~ : String,
    rule_id~ : String,
    loc~ : @basic.Location,
    reason~ : String,
  )
}

///|
priv struct ScanHit {
  finding : @rule_model.RuleFinding
  matched_source : String
  source_context : SourceContext
}

///|
priv enum ScanTrace {
  RuleLoaded(String)
  DirectoryEntered(String)
  PathSkipped(String)
  FileStarted(String)
  SemanticQueries(Int32)
}

///|
priv enum ScanEvent {
  Trace(ScanTrace)
  Warning(ScanWarning)
  Hit(ScanHit)
}

///|
priv enum ScanMode {
  Scan
  Lint
}

///|
async fn scan_events(
  mode : ScanMode,
  options : CliOptions,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let compiled_rules = prepare_scan_rules(mode, options)
  let scan_plan = @rule_apply.ScanPlan::from_rules(compiled_rules)
  let pending : Array[SemanticFile] = []
  if options.verbose {
    for rule in compiled_rules {
      receive(Trace(RuleLoaded(rule.rule_id)))
    }
  }
  let excludes = normalize_scan_excludes(options.excludes)
  let scan_root = normalize_scan_root(options.scan_root)
  visit_scan_sources(scan_root, excludes, options.verbose, receive, file => {
    scan_source_file(file, scan_plan, receive, pending)
  }) catch {
    CliError::Output(..) as err => raise err
    CliError::ScanInput(..) as err => raise err
    CliError::Internal(..) as err => raise err
    @os_error.OSError(_) as err =>
      raise new_scan_input_os_error(scan_root, "access scan input", err)
    err => raise new_internal_error("scan failed: \{err}")
  }
  if !scan_plan.semantic_rules().is_empty() {
    let requests = if pending.is_empty() {
      0
    } else {
      verify_semantic_files(pending, options.target, receive)
    }
    emit_scan_trace(options.verbose, receive, SemanticQueries(requests))
  }
}
