///|
fn fusion_test_container(owner : String, arguments : Array[Json]) -> Json {
  {
    "kind": "named",
    "path": { "kind": "builtin", "name": owner },
    "arguments": arguments,
    "named_kind": "Normal",
  }
}

///|
fn fusion_test_arrow(input : Json, output : Json) -> Json {
  {
    "kind": "function",
    "parameters": [input],
    "return_type": output,
    "error": { "kind": "typed", "type": { "kind": "builtin", "name": "Error" } },
    "async": "sync",
  }
}

///|
test "optional fusion keeps the untouched Result member and every type edge" {
  let a : Json = { "kind": "builtin", "name": "Int" }
  let b : Json = { "kind": "builtin", "name": "String" }
  let c : Json = { "kind": "builtin", "name": "Bool" }
  let error : Json = { "kind": "parameter", "owner": "sample", "index": 0 }
  let foreign_error : Json = {
    "kind": "parameter",
    "owner": "different",
    "index": 0,
  }
  for
    (owner, method_name) in [
      ("Option", "map"),
      ("Result", "map"),
      ("Result", "map_err"),
    ] {
    let wrap = value => {
      fusion_test_container(
        owner,
        if owner == "Option" {
          [value]
        } else if method_name == "map" {
          [value, error]
        } else {
          [error, value]
        },
      )
    }
    assert_true(
      optional_map_flow(
        owner,
        method_name,
        wrap(a),
        wrap(b),
        wrap(c),
        fusion_test_arrow(a, b),
        fusion_test_arrow(b, c),
      ),
    )
    assert_false(
      optional_map_flow(
        owner,
        method_name,
        wrap(a),
        wrap(b),
        wrap(c),
        fusion_test_arrow(a, c),
        fusion_test_arrow(b, c),
      ),
    )
    assert_false(
      optional_map_flow(
        owner,
        method_name,
        wrap(a),
        wrap(b),
        wrap(c),
        fusion_test_arrow(a, b),
        fusion_test_arrow(a, c),
      ),
    )
  }
  assert_false(
    optional_map_flow(
      "Result",
      "map",
      fusion_test_container("Result", [a, error]),
      fusion_test_container("Result", [b, error]),
      fusion_test_container("Result", [c, foreign_error]),
      fusion_test_arrow(a, b),
      fusion_test_arrow(b, c),
    ),
  )
  assert_false(
    optional_map_flow(
      "Result",
      "map_err",
      fusion_test_container("Result", [error, a]),
      fusion_test_container("Result", [foreign_error, b]),
      fusion_test_container("Result", [error, c]),
      fusion_test_arrow(a, b),
      fusion_test_arrow(b, c),
    ),
  )
}

///|
test "optional fusion excludes foreign containers and unknown methods" {
  let int_type : Json = { "kind": "builtin", "name": "Int" }
  let foreign : Json = {
    "kind": "named",
    "path": { "kind": "named", "package": "user/option", "name": "Option" },
    "arguments": [int_type],
    "named_kind": "Normal",
  }
  assert_true(optional_map_members(foreign, "Option", "map") is None)
  assert_true(
    optional_map_members(
      fusion_test_container("Option", [int_type]),
      "Option",
      "bind",
    )
    is None,
  )
}

///|
test "bind to map retains the original callback return boundary" {
  for
    (source, expected) in [
      ("x + 1", true),
      ("{ events.push(x); x + 1 }", true),
      ("{ if x < 0 { return None }; x + 1 }", false),
      ("{ raise problem }", true),
      ("(fn(x) { return x + 1 })(x)", true),
      ("{ fn inner(x) { return x + 1 }; inner(x) }", true),
      (
        "{ fn inner(y) { return y + 1 }; if x < 0 { return None }; inner(x) }", false,
      ),
      ("{ letrec inner = fn(y) { return y + 1 }; inner(x) }", true),
      (
        "{ letrec inner = fn(y) { return y + 1 }; if x < 0 { return None }; inner(x) }",
        false,
      ),
    ] {
    let parsed = @untyped_cst.parse_expression(source)
    assert_true(parsed.diagnostics_view().is_empty())
    assert_eq(fusion_payload_keeps_return_boundary(parsed.root()), expected)
  }
}

///|
test "bind identity exclusion identifies only the callback parameter" {
  for
    (source, expected) in [
      ("x => Some(x)", Some("x")),
      ("fn(x : Int) { Some(x + 1) }", Some("x")),
      ("_ => Some(1)", None),
    ] {
    let parsed = @untyped_cst.parse_expression(source)
    assert_true(parsed.diagnostics_view().is_empty())
    let functions = parsed.root().children.filter_map(pair => {
      if pair.1.kind is Expr_Function {
        Some(pair.1)
      } else {
        None
      }
    })
    guard functions is [callback] else { fail("expected a single lambda") }
    assert_eq(
      fusion_lambda_parameter(callback).bind(@cst.normalized_name),
      expected,
    )
  }
}
