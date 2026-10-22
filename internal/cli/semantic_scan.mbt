///|
priv struct SemanticScanContext {
  index : @semantic.Index
  view : String
}

///|
async fn load_semantic_index(path : String) -> @semantic.Index {
  let compiler_version = semantic_compiler_version(collect_semantics_process)
  let input = @fs.read_file(path).text() catch {
    err => raise new_semantics_input_error(path, "could not read index: \{err}")
  }
  let index = @semantic.Index::parse(input, compiler_version~) catch {
    err => raise new_semantics_input_error(path, "\{err}")
  }
  require_current_semantic_sources(index)
  index
}

///|
async fn scan_semantic_source(
  file : String,
  text : String,
  context : SemanticScanContext,
  plan : @rule_apply.ScanPlan,
  receive : async (ScanEvent) -> Unit,
) -> Unit {
  let canonical = @fs.realpath(file)
  let source = @semantic_source.Source::parse(
    context.index,
    file=canonical,
    text~,
    view=context.view,
  ) catch {
    err => raise new_semantics_input_error(file, "\{err}")
  }
  let source_lines = cache_source_lines(
    text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
    .replace_all(old="\u{2028}", new="\n")
    .replace_all(old="\u{2029}", new="\n"),
  )
  let roots = []
  for node in @cst.toplevel_nodes(source.root()) {
    let skip = impl_moongrep_skip_attributes(node)
    if plan.without_semantic_rules().is_empty() {
      for loc in skip.invalid_payload_locations {
        receive(Warning(InvalidMoongrepSkipPayload(file, loc)))
      }
    }
    if skip.skip_structural {
      continue
    }
    roots.push(node)
  }
  let result = @semantic_rules.apply_rules(
    source,
    plan.semantic_rules(),
    roots~,
  )
  for warning in result.warnings {
    let reason = if [
        "missing_exact_semantics", "ambiguous_semantics", "non_unique_expression_type",
        "unknown_type",
      ].contains(warning.reason) {
      skipped_reason_text(warning.reason)
    } else {
      warning.reason
    }
    receive(
      Warning(
        Semantic(file~, rule_id=warning.rule_id, loc=warning.loc, reason~),
      ),
    )
  }
  for finding in result.findings {
    receive(Hit(make_scan_hit(source_lines, { ..finding, file, })))
  }
}
