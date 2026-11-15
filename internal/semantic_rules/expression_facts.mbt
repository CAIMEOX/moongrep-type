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
/// IDE facts describe authored source operations directly. There are no
/// compiler-inserted wrapper expressions to collapse or private node tags.
fn source_expression_facts(
  facts : Array[@semantic.Fact],
) -> Array[@semantic.Fact] {
  facts.filter(fact => fact.kind == "expression")
}
