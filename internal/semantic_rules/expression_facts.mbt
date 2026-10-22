///|
/// Rule evidence describes user-written operations. Generated derive bodies can
/// reuse declaration ranges, so exclude them before association checks, keeping
/// every raw fact available through Source's default query behavior.
fn authored_facts_for_node(
  source : @semantic_source.Source,
  node : @untyped_cst.CstNode,
) -> @semantic_source.Association raise {
  let association = source.facts_for_node(node, include_generated=false)
  if association is Unmatched {
    match source.facts_for_node(node) {
      Unmatched => ()
      Associated(_) | Ambiguous(_) => raise Skip("generated_top_level")
    }
  }
  association
}

///|
/// Evidence for the source operation before conversions inserted by its
/// surrounding context. This is not the expression's effective contextual type.
/// The caller must still require one candidate and validate its symbol/type flow.
/// Keep the complete facts in Source/Index; never remove a conversion from code.
fn source_expression_facts(
  facts : Array[@semantic.Fact],
) -> Array[@semantic.Fact] {
  facts.filter(fact => {
    fact.kind == "expression" &&
    fact.node_kind.has_prefix("Texpr_") &&
    !((fact.node_kind == "Texpr_as" || fact.node_kind == "Texpr_array_as_view") &&
    fact.details is { "implicit": true, .. })
  })
}
