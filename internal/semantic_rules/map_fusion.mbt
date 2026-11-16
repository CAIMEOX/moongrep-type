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
async fn array_map_symbol(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @semantic.SymbolInfo {
  guard (context.symbol_at)(node) is Some(symbol) else {
    raise Skip("missing_exact_semantics")
  }
  guard symbol.kind == "global" &&
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
fn CheckContext::evidence(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> ExpressionEvidence {
  { location: self.range(node), text: @cst.source_text(node, self.text), }
}

///|
async fn analyze_chain(
  context : CheckContext,
  outer : MapCall,
  inner : MapCall,
) -> MapFusionCandidate {
  let symbol = array_map_symbol(context, outer.call)
  guard array_map_symbol(context, inner.call).id == symbol.id else {
    raise Skip("different_map_symbols")
  }
  let shapes = []
  for
    node in [
      inner.receiver,
      inner.call,
      outer.call,
      inner.callback,
      outer.callback,
    ] {
    guard (context.shape_at)(node) is Some(shape) else {
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
    package_name: (context.package_name)(),
    map_symbol: symbol,
    receiver: context.evidence(inner.receiver),
    inner_call: context.evidence(inner.call),
    outer_call: context.evidence(outer.call),
    first_callback: context.evidence(inner.callback),
    second_callback: context.evidence(outer.callback),
    type_flow: {
      "input_element": a,
      "intermediate_element": b,
      "output_element": c,
    },
  }
}

///|
pub async fn Candidates::map_fusion(
  self : Candidates,
  session : @ide.Session,
) -> MapFusionReport {
  let report : MapFusionReport = { candidates: [], skipped: [], }
  if self.matches.is_empty() {
    return report
  }
  let context = self.context(session)
  let jobs : Array[async () -> Result[MapFusionCandidate, SkippedCandidate]] = []
  let seen : Set[(Int32, Int32)] = Set([])
  for hit in self.matches {
    if hit.check is ArrayMapFusion &&
      hit.candidate is Direct(node) &&
      map_call(node) is Some(outer) &&
      map_call(outer.receiver) is Some(inner) &&
      !seen.contains(node.source_span) {
      seen.add(node.source_span)
      jobs.push(() => {
        Ok(analyze_chain(context, outer, inner)) catch {
          Skip(reason) => Err({ location: context.range(node), reason, })
          e => raise e
        }
      })
    }
  }
  let outcomes = @async.all(jobs[:], max_concurrent=4) catch {
    InactiveFile => return report
    err => raise err
  }
  for result in outcomes {
    match result {
      Ok(candidate) => report.candidates.push(candidate)
      Err(skipped) => report.skipped.push(skipped)
    }
  }
  report
}
