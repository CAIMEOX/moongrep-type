///|
test "theorem domains distinguish builtin sum types from namesakes" {
  let int : Json = { "kind": "builtin", "name": "Int" }
  let shape : Json = {
    "kind": "named",
    "named_kind": "Normal",
    "path": { "kind": "builtin", "name": "Option" },
    "arguments": [int],
  }
  assert_eq(builtin_type_arguments(shape, "Option"), Some([int]))
  assert_eq(builtin_type_arguments(shape, "Result"), None)
  put(shape, "path", {
    "kind": "named",
    "package": "application",
    "name": "Option",
  })
  assert_eq(builtin_type_arguments(shape, "Option"), None)
  assert_false(
    builtin_owner_is(
      { "kind": "named", "package": "application", "name": "Option" },
      "Option",
    ),
  )
  assert_true(
    builtin_owner_is({ "kind": "builtin", "name": "Option" }, "Option"),
  )
}

///|
test "unary type evidence permits resolved errors but never proves purity" {
  let int : Json = { "kind": "builtin", "name": "Int" }
  let bool : Json = { "kind": "builtin", "name": "Bool" }
  let arrow : Json = {
    "kind": "function",
    "parameters": [int],
    "return_type": bool,
    "async": "sync",
    "error": { "kind": "none" },
  }
  let errors : Array[Json] = [
    { "kind": "none" },
    { "kind": "parameter", "owner": "function" },
    { "kind": "typed", "type": { "kind": "builtin", "name": "Error" } },
  ]
  for error in errors {
    put(arrow, "error", error)
    assert_eq(unary_callback(arrow), Some((int, bool)))
  }
  put(arrow, "async", "async")
  assert_eq(unary_callback(arrow), None)
  put(arrow, "async", "sync")
  put(arrow, "parameters", [])
  assert_eq(unary_callback(arrow), None)
}
