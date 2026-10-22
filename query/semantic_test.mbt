///|
test "query captures retain the CST identity used by semantic facts" {
  let file = "/fixture/query.mbt"
  let text = "fn f(x : Int) -> Int {\n  consume(x)\n}\n"
  let data : Json = {
    "schema_version": 1,
    "compiler_version": "query-test",
    "position_encoding": "unicode-scalar",
    "sources": [{ "path": file, "text": text }],
    "types": [{ "id": 0, "kind": "builtin", "name": "Int" }],
    "symbols": [
      {
        "id": "x",
        "kind": "local",
        "name": "x",
        "identity": { "owner": "f", "stamp": 0 },
      },
    ],
    "facts": [
      {
        "id": 0,
        "package": "fixture@wasm:normal",
        "kind": "expression",
        "node_kind": "Texpr_ident",
        "location": {
          "file": file,
          "start": { "line": 2, "column": 11 },
          "end": { "line": 2, "column": 12 },
        },
        "type_id": 0,
        "symbol_id": "x",
        "details": {},
      },
    ],
  }
  let index = @semantic.Index::from_json(data, compiler_version="query-test")
  let source = @query.SemanticSource::parse(index, file~, text~)
  let query = @query.ExprQuery::ExprQuery("consume($(value:exp))")
  let captures = query.captures_from_semantic_source(source)
  inspect(captures.length(), content="1")
  let associations = source.facts_for_capture(captures[0]["value"])
  let signatures = associations.map(fn(association) {
    match association {
      Associated(facts) =>
        facts.map(fact => (fact.kind, fact.type_id, fact.symbol_id))
      Unmatched | Ambiguous(_) => []
    }
  })
  debug_inspect(
    signatures,
    content="[[(\"expression\", Some(0), Some(\"x\"))]]",
  )
}
