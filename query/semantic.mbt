///|
/// A whole-file CST tied to the exact source snapshot checked by moonc.
pub type SemanticSource = @semantic_source.Source

///|
/// Exact-range semantic facts, including explicit unmatched and ambiguous cases.
pub type SemanticAssociation = @semantic_source.Association

///|
/// Match the original CST owned by a semantic source. Captures can be passed
/// directly to `source.facts_for_capture` without reparsing or rebasing ranges.
pub fn ExprQuery::captures_from_semantic_source(
  self : ExprQuery,
  source : SemanticSource,
) -> ArrayView[Map[String, BoundValue]] {
  self.captures_from_cst(cst=source.root())
}
