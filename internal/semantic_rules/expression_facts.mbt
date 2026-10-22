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
