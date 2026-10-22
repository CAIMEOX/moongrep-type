///|
priv struct Fixture {
  data : Json
  types : Array[Json]
  facts : Array[Json]
  symbols : Array[Json]
  text : String
}

///|
fn fixture() -> Fixture {
  let text =
    #|fn sample(xs : Array[Int], g : (Int) -> Int, f : (Int) -> Int) -> Array[Int] {
    #|  xs.map(g).map(f)
    #|}
    #|
  let path : Json = {
    "kind": "named",
    "package": "moonbitlang/core/builtin",
    "name": "Array",
  }
  let types : Array[Json] = [
    { "id": 0, "kind": "builtin", "name": "Int" },
    {
      "id": 1,
      "kind": "named",
      "path": path,
      "arguments": [0],
      "named_kind": "Normal",
    },
    {
      "id": 2,
      "kind": "function",
      "parameters": [0],
      "return_type": 0,
      "error": { "kind": "none" },
      "async": "sync",
    },
    {
      "id": 3,
      "kind": "named",
      "path": path,
      "arguments": [4],
      "named_kind": "Normal",
    },
    { "id": 4, "kind": "resolved_variable", "target_type": 0 },
    {
      "id": 5,
      "kind": "function",
      "parameters": [4],
      "return_type": 4,
      "error": { "kind": "none" },
      "async": "sync",
    },
  ]
  let symbols : Array[Json] = [
    {
      "id": "map",
      "kind": "global",
      "name": "map",
      "identity": { "kind": "method", "self_type": path, "name": "map" },
    },
  ]
  let facts : Array[Json] = []
  for
    id, (start, end, type_id, is_call) in [
      (3, 19, 1, true),
      (3, 12, 3, true),
      (3, 5, 1, false),
      (10, 11, 2, false),
      (17, 18, 5, false),
    ] {
    facts.push({
      "id": id,
      "package": "fixture@wasm:normal",
      "kind": "expression",
      "node_kind": if is_call {
        "Texpr_apply"
      } else {
        "Texpr_ident"
      },
      "location": {
        "file": "/fixture/maps.mbt",
        "start": { "line": 2, "column": start },
        "end": { "line": 2, "column": end },
      },
      "type_id": type_id,
      "symbol_id": if is_call {
        Json::string("map")
      } else {
        Json::null()
      },
      "details": if is_call {
        { "dispatch": "resolved_symbol", "callee_symbol_id": "map" }
      } else {
        Json::object(Map([]))
      },
    })
  }
  {
    data: {
      "schema_version": 1,
      "compiler_version": "fixture",
      "position_encoding": "unicode-scalar",
      "sources": [{ "path": "/fixture/maps.mbt", "text": text }],
      "types": types,
      "symbols": symbols,
      "facts": facts,
    },
    types,
    facts,
    symbols,
    text,
  }
}

///|
fn put(value : Json, key : String, replacement : Json) -> Unit {
  guard value is Object(fields) else { abort("expected fixture object") }
  fields[key] = replacement
}

///|
fn Fixture::report(self : Fixture) -> MapFusionReport raise {
  put(self.data, "types", Json::array(self.types))
  put(self.data, "facts", Json::array(self.facts))
  put(self.data, "symbols", Json::array(self.symbols))
  let index = @semantic.Index::from_json(self.data, compiler_version="fixture")
  find_map_fusion(
    @semantic_source.Source::parse(
      index,
      file="/fixture/maps.mbt",
      text=self.text,
    ),
  )
}

///|
test "map fusion joins evidence and compares types rather than handles" {
  let report = fixture().report()
  inspect(report.skipped.length(), content="0")
  inspect(report.candidates.length(), content="1")
  let candidate = report.candidates[0]
  inspect(candidate.receiver.text, content="xs")
  inspect(candidate.outer_call.text, content="xs.map(g).map(f)")
  inspect(candidate.first_callback.text, content="g")
  inspect(candidate.second_callback.text, content="f")
  inspect(candidate.first_callback.fact_id, content="3")
  inspect(candidate.second_callback.fact_id, content="4")
  inspect(candidate.outer_call.location.start.column, content="3")
  inspect(candidate.outer_call.location.end.column, content="19")
  inspect(
    candidate.type_flow.stringify(),
    content="{\"input_element\":{\"kind\":\"builtin\",\"name\":\"Int\"},\"intermediate_element\":{\"kind\":\"builtin\",\"name\":\"Int\"},\"output_element\":{\"kind\":\"builtin\",\"name\":\"Int\"}}",
  )
}

///|
test "map fusion rejects unresolved and cyclic types even at identical handles" {
  let unresolved = fixture()
  unresolved.types[0] = {
    "id": 0,
    "kind": "unresolved",
    "owner": "f",
    "variable": 0,
  }
  inspect(unresolved.report().skipped[0].reason, content="unknown_type")
  let cyclic = fixture()
  cyclic.types[4] = { "id": 4, "kind": "resolved_variable", "target_type": 4 }
  inspect(cyclic.report().skipped[0].reason, content="unknown_type")
}

///|
test "map fusion checks generic ownership and every edge of the type flow" {
  let data = fixture()
  data.types[0] = {
    "id": 0,
    "kind": "parameter",
    "owner": "first",
    "index": 0,
    "name": "T",
  }
  inspect(data.report().candidates.length(), content="1")
  data.types.push({
    "id": 6,
    "kind": "parameter",
    "owner": "other",
    "index": 0,
    "name": "T",
  })
  put(data.types[5], "return_type", Json::number(6))
  inspect(data.report().skipped[0].reason, content="inconsistent_type_flow")
  put(data.types[5], "return_type", Json::number(4))
  put(data.types[5], "parameters", Json::array([Json::number(6)]))
  inspect(data.report().skipped[0].reason, content="inconsistent_type_flow")
}

///|
test "map fusion requires authoritative method identity and direct dispatch" {
  let data = fixture()
  put(data.symbols[0], "identity", {
    "kind": "method",
    "name": "map",
    "self_type": {
      "kind": "named",
      "package": "user/collections",
      "name": "Array",
    },
  })
  inspect(data.report().skipped[0].reason, content="not_standard_array_map")
  let indirect = fixture()
  put(indirect.facts[0], "details", {
    "dispatch": "binding",
    "callee_symbol_id": "map",
  })
  inspect(indirect.report().skipped[0].reason, content="not_standard_array_map")
}

///|
test "map fusion fails closed on missing facts duplicates and package views" {
  let missing = fixture()
  ignore(missing.facts.pop())
  inspect(missing.report().skipped[0].reason, content="missing_exact_semantics")
  let duplicate = fixture()
  guard duplicate.facts[4] is Object(fields) else { abort("fixture") }
  let copy = Json::object(fields.copy())
  put(copy, "id", Json::number(5))
  duplicate.facts.push(copy)
  inspect(
    duplicate.report().skipped[0].reason,
    content="non_unique_expression_type",
  )
  put(copy, "package", Json::string("fixture@wasm:wbtest"))
  inspect(duplicate.report().skipped[0].reason, content="ambiguous_semantics")
}

///|
test "map fusion excludes raising and async callbacks" {
  let data = fixture()
  data.types.push({ "id": 6, "kind": "builtin", "name": "Error" })
  put(data.types[2], "error", { "kind": "typed", "type_id": 6 })
  inspect(
    data.report().skipped[0].reason,
    content="callback_requires_sync_non_raising_unary_function",
  )
  put(data.types[2], "error", { "kind": "none" })
  put(data.types[2], "async", Json::string("async"))
  inspect(
    data.report().skipped[0].reason,
    content="callback_requires_sync_non_raising_unary_function",
  )
}

///|
test "eager map fusion preserves pure results but can reorder observable effects" {
  let g = (x : Int) => x + 1
  let f = (x : Int) => x * 2
  let values = [1, 2, 3]
  debug_inspect(values.map(g).map(f), content="[4, 6, 8]")
  assert_eq(values.map(g).map(f), values.map(x => f(g(x))))
  let events = []
  let g_effect = (x : Int) => {
    events.push("g\{x}")
    x
  }
  let f_effect = (x : Int) => {
    events.push("f\{x}")
    x
  }
  ignore([1, 2].map(g_effect).map(f_effect))
  debug_inspect(events, content="[\"g1\", \"g2\", \"f1\", \"f2\"]")
  events.clear()
  ignore([1, 2].map(x => f_effect(g_effect(x))))
  debug_inspect(events, content="[\"g1\", \"f1\", \"g2\", \"f2\"]")
}
