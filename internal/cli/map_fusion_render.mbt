///|
/// The shared renderer consumes line/column coordinates, not absolute offsets.
fn semantic_render_location(location : @semantic.Range) -> @basic.Location {
  {
    start: {
      fname: location.file,
      lnum: location.start.line,
      bol: 0,
      cnum: location.start.column - 1,
    },
    end: {
      fname: location.file,
      lnum: location.end.line,
      bol: 0,
      cnum: location.end.column - 1,
    },
  }
}

///|
priv struct DisplayTypeParameter {
  owner : String
  index : Int
  name : String
} derive(FromJson)

///|
priv struct MapFusionTypeFlow {
  input_element : Json
  intermediate_element : Json
  output_element : Json
} derive(FromJson)

///|
fn type_parameter_names(index : @semantic.Index) -> Map[(String, Int), String] {
  let names : Map[(String, Int), String] = Map([])
  for info in index.types() {
    if info.kind == "parameter" {
      let parameter : DisplayTypeParameter = @json.from_json(info.raw) catch {
        _ => continue
      }
      names[(parameter.owner, parameter.index)] = parameter.name
    }
  }
  names
}

///|
fn type_path_text(path : Json) -> String {
  match path {
    { "kind": "builtin", "name": String(name), .. }
    | { "package": "moonbitlang/core/builtin", "name": String(name), .. } =>
      name
    { "package": String(package_name), "name": String(name), .. } =>
      "\{package_name}::\{name}"
    { "kind": "constructor_type", "type": inner, .. } => type_path_text(inner)
    _ => "?"
  }
}

///|
/// Presentation only: equality is established by the rule's structural types.
fn type_text(shape : Json, names : Map[(String, Int), String]) -> String {
  match shape {
    { "kind": "builtin", "name": String(name), .. } => name
    {
      "kind": "parameter",
      "owner": String(owner),
      "index": Number(position, ..),
      ..
    } =>
      names.get((owner, position.to_int())).unwrap_or("T\{position.to_int()}")
    { "kind": "named", "path": path, "arguments": Array(args), .. } => {
      let arguments = args.map(arg => type_text(arg, names)).join(", ")
      if path is { "kind": "tuple", .. } {
        "(\{arguments})"
      } else if args.is_empty() {
        type_path_text(path)
      } else {
        "\{type_path_text(path)}[\{arguments}]"
      }
    }
    { "kind": "trait_object", "path": path, .. } => "&\{type_path_text(path)}"
    {
      "kind": "function",
      "parameters": Array(params),
      "return_type": result,
      "error": error,
      "async": String(async_kind),
      ..
    } => {
      let prefix = if async_kind == "sync" { "" } else { "\{async_kind} " }
      let parameters = params.map(param => type_text(param, names)).join(", ")
      let effect = match error {
        { "kind": "none", .. } => ""
        { "kind": "parameter", .. } => " raise?"
        { "kind": "typed", "type": error_type, .. } =>
          " raise \{type_text(error_type, names)}"
        _ => " raise <unknown>"
      }
      "\{prefix}(\{parameters}) -> \{type_text(result, names)}\{effect}"
    }
    _ => "?"
  }
}

///|
fn skipped_reason_text(reason : String) -> String {
  match reason {
    "missing_exact_semantics" =>
      "No compiler expression matches this exact source range."
    "ambiguous_semantics" =>
      "Source association is ambiguous, possibly across package/test views."
    "non_unique_expression_type" =>
      "No unique expression type is available at this source range."
    "not_standard_array_map" =>
      "The call does not resolve to the standard library Array::map method."
    "different_map_symbols" => "The two calls resolve to different methods."
    "missing_type_or_source" => "Type or source information is missing."
    "different_package_views" =>
      "The expressions belong to different package/test views."
    "unknown_type" =>
      "A type is unresolved, cyclic, or unsupported by this rule."
    "not_array_type_flow" =>
      "The receiver and both results must have Array types."
    "callback_requires_sync_non_raising_unary_function" =>
      "Callbacks must be synchronous, take one argument, and have no checked error effect."
    "inconsistent_type_flow" =>
      "The callback input/output types do not compose with the array element types."
    _ => "Cannot establish this candidate: \{reason}."
  }
}

///|
fn render_map_fusion_report(
  index : @semantic.Index,
  reports : Array[(String, @semantic_rules.MapFusionReport)],
  no_color~ : Bool,
) -> String raise {
  let mut candidate_count = 0
  let mut skipped_count = 0
  for (_, report) in reports {
    candidate_count += report.candidates.length()
    skipped_count += report.skipped.length()
  }
  let lines = [
    "Array.map fusion: \{candidate_count} candidates, \{skipped_count} skipped",
  ]
  let names = type_parameter_names(index)
  if candidate_count > 0 {
    lines.push("Pattern: xs.map(g).map(f) => xs.map(x => f(g(x)))")
    for (file, report) in reports {
      guard index.source(file) is Some(source) else {
        raise new_internal_error("missing source for semantic report: \{file}")
      }
      let source_lines = cache_source_lines(
        source.text
        .replace_all(old="\r\n", new="\n")
        .replace_all(old="\r", new="\n")
        .replace_all(old="\u{2028}", new="\n")
        .replace_all(old="\u{2029}", new="\n"),
      )
      for candidate in report.candidates {
        lines.push("")
        let flow : MapFusionTypeFlow = @json.from_json(candidate.type_flow)
        let description = "Array.map fusion candidate; review required.\nTypes: Array[\{type_text(flow.input_element, names)}] -> Array[\{type_text(flow.intermediate_element, names)}] -> Array[\{type_text(flow.output_element, names)}]"
        let finding : @rule_model.RuleFinding = {
          file,
          rule_id: "array-map-fusion",
          description,
          pattern_index: 0,
          loc: semantic_render_location(candidate.outer_call.location),
        }
        lines.push(
          render_scan_hit(make_scan_hit(source_lines, finding), no_color~),
        )
      }
    }
    lines.push("")
    lines.push(
      "Review: callback purity and termination are unproven. Fusion can change side-effect order.",
    )
    lines.push(
      "Preserve callback-expression evaluation and use fresh bindings before rewriting. No source edits were made.",
    )
  }
  if skipped_count > 0 {
    lines.push("")
    lines.push("Skipped chains:")
    for (_, report) in reports {
      for skipped in report.skipped {
        lines.push(
          "  \{format_location(skipped.location.file, semantic_render_location(skipped.location))}",
        )
        lines.push("    \{skipped_reason_text(skipped.reason)}")
      }
    }
  }
  lines.join("\n")
}
