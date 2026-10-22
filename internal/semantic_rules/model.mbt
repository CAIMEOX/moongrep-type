///|
pub(all) struct ExpressionEvidence {
  location : @semantic.Range
  text : String
  fact_id : Int
  type_id : Int
} derive(Debug)

///|
/// A type-compatible candidate, not a proof that fusion preserves effects.
pub(all) struct MapFusionCandidate {
  package_name : String
  map_symbol : @semantic.SymbolInfo
  receiver : ExpressionEvidence
  inner_call : ExpressionEvidence
  outer_call : ExpressionEvidence
  first_callback : ExpressionEvidence
  second_callback : ExpressionEvidence
  type_flow : Json
} derive(Debug)

///|
pub(all) struct SkippedCandidate {
  location : @semantic.Range
  reason : String
} derive(Debug)

///|
pub(all) struct MapFusionReport {
  candidates : Array[MapFusionCandidate]
  skipped : Array[SkippedCandidate]
} derive(Debug)

///|
pub extend ExpressionEvidence with Debug::{to_repr}

///|
pub extend MapFusionCandidate with Debug::{to_repr}

///|
pub extend SkippedCandidate with Debug::{to_repr}

///|
pub extend MapFusionReport with Debug::{to_repr}

///|
fn range_json(range : @semantic.Range) -> Json {
  {
    "file": range.file,
    "start": { "line": range.start.line, "column": range.start.column },
    "end": { "line": range.end.line, "column": range.end.column },
  }
}

///|
fn ExpressionEvidence::to_json(self : ExpressionEvidence) -> Json {
  {
    "location": range_json(self.location),
    "text": self.text,
    "fact_id": self.fact_id,
    "type_id": self.type_id,
  }
}

///|
pub fn MapFusionReport::to_json(self : MapFusionReport) -> Json {
  {
    "rule": "array-map-fusion",
    "law": "map f ∘ map g = map (f ∘ g)",
    "template": "xs.map(g).map(f) => xs.map(x => f(g(x)))",
    "candidates": self.candidates.map(candidate => {
      (
        {
          "status": "requires_review",
          "location": range_json(candidate.outer_call.location),
          "package": candidate.package_name,
          "map_symbol": candidate.map_symbol.raw,
          "receiver": candidate.receiver.to_json(),
          "inner_call": candidate.inner_call.to_json(),
          "outer_call": candidate.outer_call.to_json(),
          "first_callback": candidate.first_callback.to_json(),
          "second_callback": candidate.second_callback.to_json(),
          "type_flow": candidate.type_flow,
        } : Json)
    }),
    "skipped": self.skipped.map(skipped => {
      (
        { "location": range_json(skipped.location), "reason": skipped.reason } :
        Json)
    }),
    "rewrite_obligations": [
      "Establish that both callbacks are pure and total; non-raising types do not prove this.",
      "Preserve receiver and callback-expression evaluation and captured bindings.",
      "Use fresh names for generated bindings; this report contains no source edit.",
    ],
  }
}
