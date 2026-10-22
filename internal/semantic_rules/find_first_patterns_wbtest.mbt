///|
fn presence_fixture(
  pattern : String,
  ctor_name : String,
) -> CollectionRuleFixture {
  let base = collection_fixture(
    "Iter", "find_first", "Option", "is_some", 3, 4, 1,
  )
  let prefix = "fn sample() { "
  let expression = "input.find_first(factory()) is \{pattern}"
  let end_offset = prefix.length() + expression.length()
  let text = prefix + expression + " }"
  let pattern_start = prefix.length() +
    "input.find_first(factory()) is ".length()
  collection_put(base.facts[3], "node_kind", Json("Texpr_is"))
  collection_put(base.facts[3], "symbol_id", Json::null())
  collection_put(base.facts[3], "details", Json::object(Map([])))
  collection_put(base.facts[3], "location", {
    "file": "/fixture/collection_theorems.mbt",
    "start": { "line": 1, "column": prefix.length() + 1 },
    "end": { "line": 1, "column": end_offset + 1 },
  })
  base.symbols.push({
    "id": "presence",
    "kind": "constructor",
    "name": ctor_name,
    "identity": {
      "kind": "constructor",
      "owner_type": { "kind": "builtin", "name": "Option" },
    },
  })
  base.facts.push({
    "id": 4,
    "package": "fixture@wasm:normal",
    "kind": "pattern",
    "node_kind": "Tpat_constr",
    "type_id": 4,
    "symbol_id": "presence",
    "location": {
      "file": "/fixture/collection_theorems.mbt",
      "start": { "line": 1, "column": pattern_start + 1 },
      "end": { "line": 1, "column": end_offset + 1 },
    },
    "details": {},
  })
  { ..base, text, end_offset, }
}

///|
test "iterator existence accepts only builtin presence patterns" {
  for
    (pattern, name) in [
      ("None", "None"),
      ("Some(_)", "Some"),
      ("Option::None", "None"),
      ("Option::Some(_)", "Some"),
    ] {
    assert_true(
      presence_fixture(pattern, name).matches(check_iter_find_first_exists),
    )
  }
  let raising = presence_fixture("Some(_)", "Some")
  collection_put(raising.facts[1], "type_id", Json(13))
  assert_true(raising.matches(check_iter_find_first_exists))
}

///|
test "presence tests reject binders payload constraints and composite patterns" {
  for
    pattern in [
      "Some(value)", "Some(0)", "Some(None)", "Some(_ as value)", "(Some(_) | None)",
      "_",
    ] {
    assert_false(
      presence_fixture(pattern, "Some").matches(check_iter_find_first_exists),
    )
  }
}

///|
test "presence checks require standard method and constructor identities" {
  let foreign_method = presence_fixture("None", "None")
  collection_put(foreign_method.symbols[0], "identity", {
    "kind": "method",
    "name": "find_first",
    "self_type": { "kind": "named", "package": "foreign", "name": "Iter" },
  })
  assert_false(foreign_method.matches(check_iter_find_first_exists))
  let foreign_constructor = presence_fixture("Other::Some(_)", "Some")
  collection_put(foreign_constructor.symbols[2], "identity", {
    "kind": "constructor",
    "owner_type": { "kind": "named", "package": "foreign", "name": "Option" },
  })
  assert_false(foreign_constructor.matches(check_iter_find_first_exists))
  let inconsistent = presence_fixture("Some(_)", "Some")
  collection_put(inconsistent.facts[2], "type_id", Json(11))
  assert_false(inconsistent.matches(check_iter_find_first_exists))
  let wrong_result = presence_fixture("None", "None")
  collection_put(wrong_result.facts[3], "type_id", Json(0))
  assert_false(wrong_result.matches(check_iter_find_first_exists))
}

///|
test "presence checks cannot hide another typed pattern at the same range" {
  let data = presence_fixture("Some(_)", "Some")
  guard data.facts[4] is Object(fields) else { abort("pattern fixture") }
  let other = Json::object(fields.copy())
  collection_put(other, "id", Json(5))
  collection_put(other, "node_kind", Json("Tpat_with"))
  collection_put(other, "symbol_id", Json::null())
  data.facts.push(other)
  let rejected = try {
    ignore(data.matches(check_iter_find_first_exists))
    false
  } catch {
    Unavailable(_) => true
    error => raise error
  }
  assert_true(rejected)
}
