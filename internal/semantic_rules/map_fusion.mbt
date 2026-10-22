///|
priv suberror NotCandidate {
  Skip(String)
}

///|
priv struct MapCall {
  call : @untyped_cst.CstNode
  receiver : @untyped_cst.CstNode
  callback : @untyped_cst.CstNode
}

///|
fn map_call(node : @untyped_cst.CstNode) -> MapCall? {
  guard node.kind is Expr_DotApply &&
    @cst.child(node, "field").bind(@cst.normalized_name) == Some("map") &&
    @cst.child(node, "self") is Some(receiver) &&
    @cst.child(node, "arg") is Some(args) &&
    @cst.items(args) is [arg] &&
    arg.kind is Argument_Positional &&
    @cst.argument_value(arg) is Some(callback) else {
    return None
  }
  if @cst.raw_child(node, "return_self").bind(@cst.bool_payload) == Some(true) {
    return None
  }
  Some({ call: node, receiver, callback, })
}

///|
fn expression_fact(
  source : @semantic_source.Source,
  node : @untyped_cst.CstNode,
) -> @semantic.Fact raise {
  let facts = match source.facts_for_node(node) {
    Unmatched => raise Skip("missing_exact_semantics")
    Ambiguous(_) => raise Skip("ambiguous_semantics")
    // `function_body` is auxiliary function metadata at the lambda's range.
    // Only actual typed expression nodes compete for this CST expression.
    Associated(facts) =>
      facts.filter(fact => {
        fact.kind == "expression" && fact.node_kind.has_prefix("Texpr_")
      })
  }
  guard facts is [fact] && fact.type_id is Some(_) else {
    raise Skip("non_unique_expression_type")
  }
  fact
}

///|
fn array_map_symbol(
  index : @semantic.Index,
  fact : @semantic.Fact,
) -> @semantic.SymbolInfo raise NotCandidate {
  guard fact.node_kind == "Texpr_apply" &&
    fact.details
    is { "dispatch": "resolved_symbol", "callee_symbol_id": String(id), .. } &&
    fact.symbol_id == Some(id) &&
    index.symbol(id) is Some(symbol) &&
    symbol.kind == "global" &&
    symbol.identity
    is {
      "kind": "method",
      "name": "map",
      "self_type": {
        "kind": "named",
        "package": "moonbitlang/core/builtin",
        "name": "Array",
        ..
      },
      ..
    } else {
    raise Skip("not_standard_array_map")
  }
  symbol
}

///|
fn evidence(
  source : @semantic_source.Source,
  node : @untyped_cst.CstNode,
  fact : @semantic.Fact,
) -> ExpressionEvidence raise {
  guard fact.type_id is Some(type_id) &&
    source.index().source(source.file()) is Some(file) else {
    raise Skip("missing_type_or_source")
  }
  {
    location: source.range_for_node(node),
    text: @cst.source_text(node, file.text),
    fact_id: fact.id,
    type_id,
  }
}

///|
fn analyze_chain(
  source : @semantic_source.Source,
  outer : MapCall,
  inner : MapCall,
) -> MapFusionCandidate raise {
  let index = source.index()
  let outer_fact = expression_fact(source, outer.call)
  let inner_fact = expression_fact(source, inner.call)
  let symbol = array_map_symbol(index, outer_fact)
  guard array_map_symbol(index, inner_fact).id == symbol.id else {
    raise Skip("different_map_symbols")
  }
  let input_fact = expression_fact(source, inner.receiver)
  let first_fact = expression_fact(source, inner.callback)
  let second_fact = expression_fact(source, outer.callback)
  let facts = [input_fact, inner_fact, outer_fact, first_fact, second_fact]
  let shapes : Array[Json] = []
  for fact in facts {
    if fact.package_name != outer_fact.package_name {
      raise Skip("different_package_views")
    }
    guard fact.type_id.bind(id => type_shape(index, id)) is Some(shape) else {
      raise Skip("unknown_type")
    }
    shapes.push(shape)
  }
  guard array_element(shapes[0]) is Some(a) &&
    array_element(shapes[1]) is Some(b) &&
    array_element(shapes[2]) is Some(c) else {
    raise Skip("not_array_type_flow")
  }
  guard callback_arrow(shapes[3]) is Some((g_input, g_output)) &&
    callback_arrow(shapes[4]) is Some((f_input, f_output)) else {
    raise Skip("callback_requires_sync_non_raising_unary_function")
  }
  if a != g_input || b != g_output || b != f_input || c != f_output {
    raise Skip("inconsistent_type_flow")
  }
  {
    package_name: outer_fact.package_name,
    map_symbol: symbol,
    receiver: evidence(source, inner.receiver, input_fact),
    inner_call: evidence(source, inner.call, inner_fact),
    outer_call: evidence(source, outer.call, outer_fact),
    first_callback: evidence(source, inner.callback, first_fact),
    second_callback: evidence(source, outer.callback, second_fact),
    type_flow: {
      "input_element": a,
      "intermediate_element": b,
      "output_element": c,
    },
  }
}

///|
/// Recognize adjacent Array.map calls using exact CST/semantic joins. Unknown or
/// ambiguous facts yield explicit skipped results. No result authorizes an edit.
pub fn find_map_fusion(
  source : @semantic_source.Source,
) -> MapFusionReport raise {
  let chains : Array[(MapCall, MapCall)] = []
  let seen : Map[(Int, Int), Bool] = Map([])
  @cst.visit_expr_match_candidate_roots(source.root(), fn(candidate) {
    if candidate is Direct(node) &&
      map_call(node) is Some(outer) &&
      map_call(outer.receiver) is Some(inner) &&
      !seen.contains(node.source_span) {
      seen[node.source_span] = true
      chains.push((outer, inner))
    }
    NodeVisitContinue
  })
  let report : MapFusionReport = { candidates: [], skipped: [], }
  for (outer, inner) in chains {
    report.candidates.push(analyze_chain(source, outer, inner)) catch {
      Skip(reason) =>
        report.skipped.push({
          location: source.range_for_node(outer.call),
          reason,
        })
      error => raise error
    }
  }
  report
}
