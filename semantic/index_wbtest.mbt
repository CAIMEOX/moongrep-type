///|
fn fixture_fact(id : Int, start : Int, end : Int) -> Json {
  {
    "id": Json(id),
    "package": "demo",
    "kind": "expression",
    "node_kind": "Texpr_constant",
    "location": {
      "file": "/demo/main.mbt",
      "start": { "line": 1, "column": Json(start) },
      "end": { "line": 1, "column": Json(end) },
    },
    "type_id": 0,
    "symbol_id": "demo.value",
    "details": { "implicit": false, "extension": [1, 2] },
  }
}

///|
fn fixture(text : String, facts : Array[Json]) -> Json {
  {
    "schema_version": 1,
    "compiler_version": "test-compiler",
    "position_encoding": "unicode-scalar",
    "sources": [{ "path": "/demo/main.mbt", "text": Json(text) }],
    "types": [{ "id": 0, "kind": "builtin", "name": "String", "extra": true }],
    "symbols": [
      {
        "id": "demo.value",
        "kind": "value",
        "name": "value",
        "identity": { "package": "demo" },
      },
    ],
    "facts": Json::array(facts),
    "extension": { "preserved": true },
  }
}

///|
fn rejected(value : Json) -> String {
  try {
    ignore(Index::from_json(value, compiler_version="test-compiler"))
    "accepted"
  } catch {
    error => error.to_string()
  }
}

///|
fn set_field(value : Json, key : String, replacement : Json) -> Unit {
  guard value is Object(fields) else { abort("test fixture must be an object") }
  fields[key] = replacement
}

///|
test "structured type graph and contextual type references are validated" {
  let value = fixture("x", [fixture_fact(1, 1, 2)])
  set_field(value, "types", [
    {
      "id": 0,
      "kind": "function",
      "parameters": [1],
      "return_type": 1,
      "error": { "kind": "typed", "type_id": 2 },
    },
    { "id": 1, "kind": "named", "arguments": [2] },
    { "id": 2, "kind": "builtin", "name": "Int" },
    { "id": 3, "kind": "resolved_variable", "target_type": 0 },
  ])
  inspect(rejected(value), content="accepted")
  let missing = fixture("", [])
  set_field(missing, "types", [{ "id": 0, "kind": "named", "arguments": [9] }])
  inspect(
    rejected(missing),
    content="invalid semantic index: type 0.arguments references missing type: 9",
  )
  let detail = fixture_fact(1, 1, 2)
  set_field(detail, "details", {
    "type_arguments": { "types": [{ "type_id": 7, "constraints": [] }] },
  })
  inspect(
    rejected(fixture("x", [detail])),
    content="invalid semantic index: fact 1.details.type_arguments.types.type_id references missing type: 7",
  )
}

///|
test "reserved detail symbol references cannot dangle" {
  let keys = [
    "alias_symbol_id", "target_symbol_id", "constructor_symbol_id", "method_symbol_id",
    "trait_symbol_id", "callee_symbol_id",
  ]
  let results = keys.map(key => {
    let fact = fixture_fact(1, 1, 2)
    let details : Map[String, Json] = Map([])
    details[key] = "missing"
    set_field(fact, "details", Json::object(details))
    rejected(fixture("x", [fact]))
  })
  inspect(
    Repr(results),
    content=(
      #|[
      #|  "invalid semantic index: fact 1.details.alias_symbol_id references missing symbol: missing",
      #|  "invalid semantic index: fact 1.details.target_symbol_id references missing symbol: missing",
      #|  "invalid semantic index: fact 1.details.constructor_symbol_id references missing symbol: missing",
      #|  "invalid semantic index: fact 1.details.method_symbol_id references missing symbol: missing",
      #|  "invalid semantic index: fact 1.details.trait_symbol_id references missing symbol: missing",
      #|  "invalid semantic index: fact 1.details.callee_symbol_id references missing symbol: missing",
      #|]
    ),
  )
  let valid = fixture_fact(1, 1, 2)
  set_field(valid, "details", {
    "callee_symbol_id": null,
    "target_symbol_id": "demo.value",
    "extension": { "callee_symbol_id": "not-a-reserved-path", "type_id": 99 },
  })
  inspect(rejected(fixture("x", [valid])), content="accepted")
}

///|
test "typed errors in effects and substitutions cannot dangle" {
  let effect = fixture_fact(1, 1, 2)
  set_field(effect, "details", { "error": { "kind": "typed", "type_id": 99 } })
  inspect(
    rejected(fixture("x", [effect])),
    content="invalid semantic index: fact 1.details.error.type_id references missing type: 99",
  )
  let substitution = fixture_fact(1, 1, 2)
  set_field(substitution, "details", {
    "type_arguments": {
      "types": [],
      "error": { "kind": "typed", "type_id": 99 },
    },
  })
  inspect(
    rejected(fixture("x", [substitution])),
    content="invalid semantic index: fact 1.details.type_arguments.error.type_id references missing type: 99",
  )
  let valid = fixture_fact(1, 1, 2)
  set_field(valid, "details", {
    "type_arguments": {
      "types": [],
      "error": { "kind": "typed", "type_id": 0 },
    },
    "error": { "kind": "parameter", "owner": "example" },
  })
  inspect(rejected(fixture("x", [valid])), content="accepted")
}

///|
test "field constructor and bitstring metadata type edges cannot dangle" {
  let keys = ["record_type", "field_type", "pattern_type"]
  let results = keys.map(key => {
    let fact = fixture_fact(1, 1, 2)
    let details : Map[String, Json] = Map([])
    details[key] = 99
    set_field(fact, "details", Json::object(details))
    rejected(fixture("x", [fact]))
  })
  inspect(
    Repr(results),
    content=(
      #|[
      #|  "invalid semantic index: fact 1.details.record_type references missing type: 99",
      #|  "invalid semantic index: fact 1.details.field_type references missing type: 99",
      #|  "invalid semantic index: fact 1.details.pattern_type references missing type: 99",
      #|]
    ),
  )
  let parameters = fixture_fact(1, 1, 2)
  set_field(parameters, "details", { "parameter_types": [0, 99] })
  inspect(
    rejected(fixture("x", [parameters])),
    content="invalid semantic index: fact 1.details.parameter_types references missing type: 99",
  )
  let valid = fixture_fact(1, 1, 2)
  set_field(valid, "details", {
    "record_type": 0,
    "field_type": 0,
    "pattern_type": 0,
    "parameter_types": [0],
  })
  inspect(rejected(fixture("x", [valid])), content="accepted")
}

///|
test "equal coordinates in different files remain distinct" {
  let value = fixture("x", [fixture_fact(1, 1, 2)])
  set_field(value, "sources", [
    { "path": "/demo/main.mbt", "text": "x" },
    { "path": "/demo/other.mbt", "text": "x" },
  ])
  let index = Index::from_json(value, compiler_version="test-compiler")
  let other : Range = {
    file: "/demo/other.mbt",
    start: { line: 1, column: 1, },
    end: { line: 1, column: 2, },
  }
  inspect(index.facts_for_range(other).length(), content="0")
  inspect(index.enclosing_facts(other).length(), content="0")
}

///|
test "exact range lookup retains all facts and enclosing lookup is explicit" {
  let first = fixture_fact(7, 1, 4)
  let second = fixture_fact(9, 1, 4)
  let index = Index::from_json(
    fixture("abc", [first, second]),
    compiler_version="test-compiler",
  )
  let whole : Range = {
    file: "/demo/main.mbt",
    start: { line: 1, column: 1, },
    end: { line: 1, column: 4, },
  }
  let inner : Range = {
    ..whole,
    start: { line: 1, column: 2, },
    end: { line: 1, column: 3, },
  }
  inspect(Repr(index.facts_for_range(whole).map(f => f.id)), content="[7, 9]")
  inspect(index.facts_for_range(inner).length(), content="0")
  inspect(Repr(index.enclosing_facts(inner).map(f => f.id)), content="[7, 9]")
  index.require_source("/demo/main.mbt", "abc")
  inspect(index.compiler_version(), content="test-compiler")
  inspect(index.types().length(), content="1")
  inspect(index.symbols().length(), content="1")
  inspect(index.sources().length(), content="1")
  inspect(index.facts().length(), content="2")
  guard index.type_info(0) is Some(type_info) else { fail("missing type") }
  guard type_info.raw is Object(type_fields) else { fail("missing raw type") }
  inspect(Repr(type_fields.get("extra")), content="Some(True)")
  guard index.raw_json() is Object(fields) else { fail("missing raw envelope") }
  inspect(
    Repr(fields.get("extension")),
    content=(
      #|Some(Object({ "preserved": True }))
    ),
  )
}

///|
test "source positions count Unicode scalars and strip CRLF line endings" {
  let valid = fixture("😀\r\n中文\r\n", [fixture_fact(1, 1, 2)])
  let index = Index::from_json(valid, compiler_version="test-compiler")
  inspect(
    Repr(index.facts()[0].location),
    content=(
      #|Some(
      #|  {
      #|    file: "/demo/main.mbt",
      #|    start: { line: 1, column: 1 },
      #|    end: { line: 1, column: 2 },
      #|  },
      #|)
    ),
  )
  inspect(
    rejected(fixture("😀\r\n", [fixture_fact(1, 1, 3)])),
    content="invalid semantic index: fact 1 has an invalid source range",
  )
  let last_line = fixture_fact(2, 1, 1)
  set_field(last_line, "location", {
    "file": "/demo/main.mbt",
    "start": { "line": 3, "column": 1 },
    "end": { "line": 3, "column": 1 },
  })
  inspect(
    rejected(fixture("😀\r\n中文\r\n", [last_line])),
    content="accepted",
  )
  inspect(
    Repr(source_line_lengths("a\rb\n😀\r\nc\u2028d\u2029")),
    content="[1, 1, 1, 1, 1, 0]",
  )
}

///|
test "schema and compiler compatibility are mandatory" {
  let wrong_schema = fixture("", [])
  set_field(wrong_schema, "schema_version", 2)
  inspect(
    rejected(wrong_schema),
    content="invalid semantic index: unsupported schema version: 2",
  )
  let wrong_compiler = fixture("", [])
  set_field(wrong_compiler, "compiler_version", "different")
  inspect(
    rejected(wrong_compiler),
    content="semantic compiler mismatch: expected test-compiler, found different",
  )
  let wrong_encoding = fixture("", [])
  set_field(wrong_encoding, "position_encoding", "utf16")
  inspect(
    rejected(wrong_encoding),
    content="invalid semantic index: unsupported position encoding: utf16",
  )
  let fractional = fixture("", [])
  set_field(fractional, "schema_version", 1.5)
  inspect(
    rejected(fractional),
    content="invalid semantic index: schema_version must be an integer",
  )
}

///|
test "duplicate IDs and dangling source type symbol references are rejected" {
  inspect(
    rejected(fixture("x", [fixture_fact(1, 1, 2), fixture_fact(1, 1, 2)])),
    content="invalid semantic index: duplicate fact id: 1",
  )
  let type_ref = fixture_fact(1, 1, 2)
  set_field(type_ref, "type_id", 99)
  inspect(
    rejected(fixture("x", [type_ref])),
    content="invalid semantic index: fact 1 references missing type: 99",
  )
  let symbol_ref = fixture_fact(1, 1, 2)
  set_field(symbol_ref, "symbol_id", "missing")
  inspect(
    rejected(fixture("x", [symbol_ref])),
    content="invalid semantic index: fact 1 references missing symbol: missing",
  )
  let missing_source = fixture("x", [fixture_fact(1, 1, 2)])
  set_field(missing_source, "sources", [])
  inspect(
    rejected(missing_source),
    content="invalid semantic index: fact 1 references missing source: /demo/main.mbt",
  )
  let duplicate_type = fixture("", [])
  set_field(duplicate_type, "types", [
    { "id": 0, "kind": "builtin" },
    { "id": 0, "kind": "builtin" },
  ])
  inspect(
    rejected(duplicate_type),
    content="invalid semantic index: duplicate type id: 0",
  )
  let duplicate_symbol = fixture("", [])
  let symbol : Json = {
    "id": "s",
    "kind": "value",
    "name": "s",
    "identity": null,
  }
  set_field(duplicate_symbol, "symbols", [symbol, symbol])
  inspect(
    rejected(duplicate_symbol),
    content="invalid semantic index: duplicate symbol id: s",
  )
}

///|
test "stale sources are rejected and facts without source locations are preserved" {
  let generated = fixture_fact(1, 1, 2)
  set_field(generated, "location", null)
  set_field(generated, "type_id", null)
  set_field(generated, "symbol_id", null)
  let index = Index::from_json(
    fixture("x", [generated]),
    compiler_version="test-compiler",
  )
  inspect(Repr(index.facts()[0].location), content="None")
  let stale = try {
    index.require_source("/demo/main.mbt", "y")
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(
    stale,
    content="semantic source differs from current source: /demo/main.mbt",
  )
  let missing = try {
    index.require_source("/other/main.mbt", "x")
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(missing, content="semantic source is missing: /other/main.mbt")
}
