///|
fn mark_generated_fact(fact : Json, generated : Json) -> Unit {
  guard fact is { "details": Object(details), .. } else {
    abort("fixture fact")
  }
  details["generated_top_level"] = generated
}

///|
fn duplicate_generated_fact(fact : Json, id : Int) -> Json {
  guard fact is Object(fields) else { abort("fixture fact") }
  let copy = Json::object(fields.copy())
  put(copy, "id", Json(id))
  guard fact is { "details": Object(details), .. } else {
    abort("fixture details")
  }
  put(copy, "details", Json::object(details.copy()))
  mark_generated_fact(copy, true)
  copy
}

///|
test "generated expression overlap is excluded in both rule evidence entrypoints" {
  let identity = identity_theorem_fixture("Option", "map")
  let generated = duplicate_generated_fact(
    identity.facts[0],
    identity.facts.length(),
  )
  put(generated, "package", Json("fixture@wasm:wbtest"))
  identity.facts.push(generated)
  assert_true(identity.matches())
  let maps = fixture()
  let generated = duplicate_generated_fact(maps.facts[0], maps.facts.length())
  put(generated, "package", Json("fixture@wasm:wbtest"))
  maps.facts.push(generated)
  let report = maps.report()
  inspect(report.candidates.length(), content="1")
  inspect(report.skipped.length(), content="0")
  inspect(report.candidates[0].outer_call.fact_id, content="0")
}

///|
test "generated-only evidence is distinguishable from missing evidence" {
  let identity = identity_theorem_fixture("Option", "map")
  for fact in identity.facts {
    mark_generated_fact(fact, true)
  }
  let reason = try {
    ignore(identity.matches())
    "accepted"
  } catch {
    Skip(reason) => reason
    error => raise error
  }
  inspect(reason, content="generated_top_level")
  let maps = fixture()
  for fact in maps.facts {
    mark_generated_fact(fact, true)
  }
  inspect(maps.report().candidates.length(), content="0")
  inspect(maps.report().skipped[0].reason, content="generated_top_level")
}

///|
test "generated references cannot contaminate authored symbol identity or uses" {
  let data = identity_theorem_fixture("Option", "map")
  let binding = duplicate_generated_fact(data.facts[3], data.facts.length())
  put(binding, "symbol_id", Json("other"))
  data.facts.push(binding)
  assert_true(data.matches())
  let source = @semantic_source.Source::parse(
    @semantic.Index::from_json(data.data, compiler_version="fixture"),
    file="/fixture/identity.mbt",
    text=data.text,
  )
  let context = CheckContext::new(source)
  assert_false(context.facts_by_symbol.contains("other"))
  assert_true(source.facts().any(f => f.symbol_id == Some("other")))
}

///|
test "generated filtering retains authored conversion and malformed flag evidence" {
  for generated in [Json::boolean(false), Json::string("true"), Json::null()] {
    let maps = fixture()
    let copy = duplicate_generated_fact(maps.facts[0], maps.facts.length())
    mark_generated_fact(copy, generated)
    maps.facts.push(copy)
    assert_eq(maps.report().skipped[0].reason, "non_unique_expression_type")
  }
  let maps = fixture()
  let wrapper = conversion_fact(maps.facts[0], 5, "Texpr_as", 0)
  mark_generated_fact(wrapper, false)
  maps.facts.push(wrapper)
  maps.facts.push(duplicate_generated_fact(maps.facts[0], 6))
  assert_eq(maps.report().candidates.length(), 1)
}
