///|
fn conversion_fact(
  inner : Json,
  id : Int,
  node_kind : String,
  type_id : Int,
  implicit~ : Json = Json::boolean(true),
) -> Json {
  guard inner is Object(fields) else { abort("fixture expression") }
  let fact = Json::object(fields.copy())
  put(fact, "id", Json(id))
  put(fact, "node_kind", Json(node_kind))
  put(fact, "type_id", Json(type_id))
  put(fact, "symbol_id", Json::null())
  put(fact, "details", { "implicit": implicit })
  fact
}

///|
fn add_conversion_types(types : Array[Json]) -> Unit {
  types.push({
    "id": 6,
    "kind": "trait_object",
    "path": {
      "kind": "named",
      "package": "moonbitlang/core/debug",
      "name": "Debug",
    },
  })
  types.push({
    "id": 7,
    "kind": "named",
    "path": {
      "kind": "named",
      "package": "moonbitlang/core/builtin",
      "name": "ArrayView",
    },
    "arguments": [0],
    "named_kind": "Normal",
  })
}

///|
test "implicit trait conversion retains identity evidence and every raw fact" {
  let data = identity_theorem_fixture("Option", "map")
  guard data.data is { "types": Array(types), .. } else { abort("types") }
  add_conversion_types(types)
  data.facts.push(
    conversion_fact(data.facts[0], data.facts.length(), "Texpr_as", 6),
  )
  assert_true(data.matches())
  let source = @semantic_source.Source::parse(
    @semantic.Index::from_json(data.data, compiler_version="fixture"),
    file="/fixture/identity.mbt",
    text=data.text,
  )
  let node = identity_test_node(source.root(), node => {
    node.kind is Expr_DotApply
  })
  guard source.facts_for_node(node) is Associated(facts) else {
    abort("associated")
  }
  assert_eq(facts.length(), 2)
  assert_true(facts.any(f => f.node_kind == "Texpr_as" && f.type_id == Some(6)))
  assert_true(
    facts.any(f => f.node_kind == "Texpr_apply" && f.type_id == Some(2)),
  )
  assert_eq(CheckContext::new(source).expression(node).node_kind, "Texpr_apply")
}

///|
test "map fusion selects the source call before known implicit conversions" {
  for kind in ["Texpr_as", "Texpr_array_as_view"] {
    let data = fixture()
    add_conversion_types(data.types)
    let inner = data.facts[0]
    data.facts[0] = conversion_fact(
      inner,
      5,
      kind,
      if kind == "Texpr_as" {
        6
      } else {
        7
      },
    )
    data.facts.push(inner)
    let report = data.report()
    assert_eq(report.candidates.length(), 1)
    assert_eq(report.skipped.length(), 0)
    assert_eq(report.candidates[0].outer_call.fact_id, 0)
    assert_eq(report.candidates[0].outer_call.type_id, 1)
  }
  let layered = fixture()
  add_conversion_types(layered.types)
  layered.facts.push(
    conversion_fact(layered.facts[0], 5, "Texpr_array_as_view", 7),
  )
  layered.facts.push(conversion_fact(layered.facts[0], 6, "Texpr_as", 6))
  assert_eq(layered.report().candidates.length(), 1)
}

///|
test "explicit unknown and malformed conversions cannot hide ambiguity" {
  for kind in ["Texpr_as", "Texpr_array_as_view"] {
    for implicit in [Json::boolean(false), Json::string("true"), Json::null()] {
      let data = fixture()
      data.facts.push(conversion_fact(data.facts[0], 5, kind, 0, implicit~))
      assert_eq(data.report().skipped[0].reason, "non_unique_expression_type")
    }
    let data = fixture()
    let missing = conversion_fact(data.facts[0], 5, kind, 0)
    put(missing, "details", Json::object(Map([])))
    data.facts.push(missing)
    assert_eq(data.report().skipped[0].reason, "non_unique_expression_type")
  }
  for kind in ["Texpr_ident", "Texpr_apply", "Texpr_future_conversion"] {
    let data = fixture()
    data.facts.push(conversion_fact(data.facts[0], 5, kind, 0))
    assert_eq(data.report().skipped[0].reason, "non_unique_expression_type")
  }
}

///|
test "conversions cannot manufacture a source expression or merge competing expressions" {
  let missing = fixture()
  missing.facts[0] = conversion_fact(missing.facts[0], 0, "Texpr_as", 0)
  assert_eq(missing.report().skipped[0].reason, "non_unique_expression_type")
  let multiple = fixture()
  guard multiple.facts[0] is Object(fields) else { abort("fixture") }
  let duplicate = Json::object(fields.copy())
  put(duplicate, "id", Json(5))
  multiple.facts.push(duplicate)
  multiple.facts.push(conversion_fact(multiple.facts[0], 6, "Texpr_as", 0))
  assert_eq(multiple.report().skipped[0].reason, "non_unique_expression_type")
}

///|
test "implicit conversions never override package view ambiguity" {
  let data = fixture()
  let wrapper = conversion_fact(data.facts[0], 5, "Texpr_as", 0)
  put(wrapper, "package", Json("fixture@wasm:wbtest"))
  data.facts.push(wrapper)
  assert_eq(data.report().skipped[0].reason, "ambiguous_semantics")
}
