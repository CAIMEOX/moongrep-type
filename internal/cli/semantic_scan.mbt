///|
priv struct SemanticFile {
  path : String
  text : String
  candidates : @semantic_rules.Candidates
}

///|
async fn select_semantic_file(
  file : String,
  text : String,
  plan : @rule_apply.ScanPlan,
  receive : async (ScanEvent) -> Unit,
) -> SemanticFile? {
  let parsed = @untyped_cst.parse_structure(text, name=file)
  let semantic_only = plan.without_semantic_rules().is_empty()
  if !parsed.diagnostics_view().is_empty() ||
    @cst.first_recovery_node(parsed.root()) is Some(_) {
    if semantic_only {
      receive(
        Warning(
          Parse({
            file,
            block_start_line: None,
            reason: "parse failed during semantic candidate selection",
          }),
        ),
      )
    }
    return None
  }
  let roots = []
  for root in @cst.toplevel_nodes(parsed.root()) {
    let skip = impl_moongrep_skip_attributes(root)
    if semantic_only {
      for loc in skip.invalid_payload_locations {
        receive(Warning(InvalidMoongrepSkipPayload(file, loc)))
      }
    }
    if !skip.skip_structural {
      roots.push(root)
    }
  }
  let candidates = @semantic_rules.Candidates::select(
    file,
    text,
    parsed.root(),
    roots,
    plan.semantic_rules(),
  )
  if candidates.is_empty() {
    None
  } else {
    Some({ path: file, text, candidates, })
  }
}

///|
async fn verify_semantic_files(
  files : Array[SemanticFile],
  target : String?,
  receive : async (ScanEvent) -> Unit,
) -> Int32 {
  let session = @ide.Session::new(target?)
  let reports = []
  for input in files {
    let report = input.candidates.verify(session) catch {
      err =>
        raise new_scan_input_error(
          input.path,
          "verify semantic candidates",
          "\{err}",
        )
    }
    reports.push((input, report))
  }
  session.validate() catch {
    err =>
      raise new_scan_input_error(
        files[0].path,
        "validate semantic inputs",
        "\{err}",
      )
  }
  for (input, report) in reports {
    for warning in report.warnings {
      let reason = if ["missing_exact_semantics", "unknown_type"].contains(
          warning.reason,
        ) {
        skipped_reason_text(warning.reason)
      } else {
        warning.reason
      }
      receive(
        Warning(
          Semantic(
            file=input.path,
            rule_id=warning.rule_id,
            loc=warning.loc,
            reason~,
          ),
        ),
      )
    }
    if !report.findings.is_empty() {
      let lines = cache_source_lines(
        input.text
        .replace_all(old="\r\n", new="\n")
        .replace_all(old="\r", new="\n")
        .replace_all(old="\u{2028}", new="\n")
        .replace_all(old="\u{2029}", new="\n"),
      )
      for finding in report.findings {
        receive(Hit(make_scan_hit(lines, finding)))
      }
    }
  }
  session.query_count()
}
