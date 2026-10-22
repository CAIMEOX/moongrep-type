///|
priv struct IdentityTheoremFixture {
  data : Json
  facts : Array[Json]
  symbols : Array[Json]
  owner : String
  operation : String
  text : String
}

///|
fn identity_test_node(
  root : @untyped_cst.CstNode,
  predicate : (@untyped_cst.CstNode) -> Bool,
) -> @untyped_cst.CstNode {
  let pending = [root]
  while pending.pop() is Some(node) {
    if predicate(node) {
      return node
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  abort("missing identity test node")
}

///|
fn identity_theorem_fixture(
  owner : String,
  operation : String,
) -> IdentityTheoremFixture raise {
  let ctor_name = if operation == "unwrap_err" {
    "Err"
  } else if owner == "Option" {
    "Some"
  } else {
    "Ok"
  }
  let expression = match operation {
    "map" => "value.map(x => x)"
    "bind" => "value.bind(x => \{ctor_name}(x))"
    _ => "\{ctor_name}(value).\{operation}()"
  }
  let text = "fn example(value) { \{expression} }\n"
  let payload_type = if operation == "unwrap_err" { 1 } else { 0 }
  let args : Array[Json] = if owner == "Option" { [0] } else { [0, 1] }
  let types : Array[Json] = [
    { "id": 0, "kind": "builtin", "name": "Int" },
    { "id": 1, "kind": "builtin", "name": "String" },
    {
      "id": 2,
      "kind": "named",
      "named_kind": "Normal",
      "path": { "kind": "builtin", "name": owner },
      "arguments": args,
    },
    {
      "id": 3,
      "kind": "function",
      "parameters": [0],
      "return_type": if operation == "bind" {
        2
      } else {
        0
      },
      "error": { "kind": "none" },
      "async": "sync",
    },
    {
      "id": 4,
      "kind": "function",
      "parameters": [payload_type],
      "return_type": 2,
      "error": { "kind": "none" },
      "async": "sync",
    },
    {
      "id": 5,
      "kind": "named",
      "named_kind": "Normal",
      "path": { "kind": "builtin", "name": "Result" },
      "arguments": [0, 0],
    },
  ]
  let symbols : Array[Json] = [
    {
      "id": "method",
      "kind": "global",
      "name": operation,
      "identity": {
        "kind": "method",
        "name": operation,
        "self_type": { "kind": "builtin", "name": owner },
      },
    },
    {
      "id": "binder",
      "kind": "local",
      "name": "x",
      "identity": { "kind": "local", "owner": "example", "stamp": 1 },
    },
    {
      "id": "other",
      "kind": "local",
      "name": "x",
      "identity": { "kind": "local", "owner": "example", "stamp": 2 },
    },
    {
      "id": "constructor",
      "kind": "constructor",
      "name": ctor_name,
      "identity": {
        "kind": "constructor",
        "owner_type": { "kind": "builtin", "name": owner },
      },
    },
  ]
  let facts : Array[Json] = []
  let data : Json = {
    "schema_version": 1,
    "compiler_version": "fixture",
    "position_encoding": "unicode-scalar",
    "sources": [{ "path": "/fixture/identity.mbt", "text": text }],
    "types": types,
    "symbols": symbols,
    "facts": facts,
  }
  let source = @semantic_source.Source::parse(
    @semantic.Index::from_json(data, compiler_version="fixture"),
    file="/fixture/identity.mbt",
    text~,
  )
  let call_node = identity_test_node(source.root(), node => {
    node.kind is Expr_DotApply
  })
  let call = dot_call(call_node).unwrap()
  let add = fn(
    node,
    kind : String,
    node_kind : String,
    type_id : Int,
    symbol_id : String?,
  ) raise {
    facts.push({
      "id": facts.length(),
      "package": "fixture@wasm:normal",
      "kind": kind,
      "node_kind": node_kind,
      "type_id": type_id,
      "location": range_json(source.range_for_node(node)),
      "symbol_id": match symbol_id {
        Some(id) => Json::string(id)
        None => Json::null()
      },
      "details": if symbol_id == Some("method") {
        { "dispatch": "resolved_symbol", "callee_symbol_id": "method" }
      } else {
        Json::object(Map([]))
      },
    })
  }
  let is_unwrap = operation == "unwrap" || operation == "unwrap_err"
  add(
    call_node,
    "expression",
    "Texpr_apply",
    if is_unwrap {
      payload_type
    } else {
      2
    },
    Some("method"),
  )
  add(
    call.receiver,
    "expression",
    if is_unwrap {
      "Texpr_constr"
    } else {
      "Texpr_ident"
    },
    2,
    None,
  )
  if is_unwrap {
    let payload = positional_args(call.receiver).unwrap()[0]
    add(payload, "expression", "Texpr_ident", payload_type, None)
    add(
      @cst.child(call.receiver, "func").unwrap(),
      "expression",
      "Texpr_constr",
      4,
      Some("constructor"),
    )
  } else {
    let callback = call.args[0]
    let (binder, body) = unary_lambda_parts(callback).unwrap()
    add(callback, "expression", "Texpr_function", 3, None)
    add(binder, "binding", "Param", 0, Some("binder"))
    if operation == "map" {
      add(body, "expression", "Texpr_ident", 0, Some("binder"))
    } else {
      let payload = positional_args(body).unwrap()[0]
      add(payload, "expression", "Texpr_ident", 0, Some("binder"))
      add(
        @cst.child(body, "func").unwrap(),
        "expression",
        "Texpr_constr",
        4,
        Some("constructor"),
      )
      add(body, "expression", "Texpr_constr", 2, None)
    }
    // Nightly exports both Param and binder facts at the same Name_Binder.
    add(binder, "binding", "binder", 0, Some("binder"))
    put(facts[facts.length() - 1], "type_id", Json::null())
  }
  put(data, "facts", Json::array(facts))
  { data, facts, symbols, owner, operation, text, }
}

///|
fn IdentityTheoremFixture::matches(self : IdentityTheoremFixture) -> Bool raise {
  let source = @semantic_source.Source::parse(
    @semantic.Index::from_json(self.data, compiler_version="fixture"),
    file="/fixture/identity.mbt",
    text=self.text,
  )
  let context = CheckContext::new(source)
  let node = identity_test_node(source.root(), node => {
    node.kind is Expr_DotApply
  })
  let location = match self.operation {
    "map" => check_map_identity(context, node, self.owner)
    "bind" => check_bind_identity(context, node, self.owner)
    "unwrap" =>
      check_constructor_unwrap(
        context,
        node,
        self.owner,
        if self.owner == "Option" {
          "Some"
        } else {
          "Ok"
        },
        "unwrap",
      )
    _ =>
      check_constructor_unwrap(context, node, self.owner, "Err", "unwrap_err")
  }
  location is Some(_)
}

///|
test "identity theorems check all seven Option and Result laws" {
  for
    (owner, operation) in [
      ("Option", "map"),
      ("Result", "map"),
      ("Option", "bind"),
      ("Result", "bind"),
      ("Option", "unwrap"),
      ("Result", "unwrap"),
      ("Result", "unwrap_err"),
    ] {
    assert_true(identity_theorem_fixture(owner, operation).matches())
  }
}

///|
test "identity lambda equality uses binder identity rather than spelling" {
  for operation in ["map", "bind"] {
    let fixture = identity_theorem_fixture("Option", operation)
    put(fixture.facts[4], "symbol_id", Json::string("other"))
    assert_false(fixture.matches())
  }
}

///|
test "identity laws preserve the entire Result type including its error" {
  for operation in ["map", "bind"] {
    let fixture = identity_theorem_fixture("Result", operation)
    put(fixture.facts[0], "type_id", Json::number(5))
    assert_false(fixture.matches())
  }
}

///|
test "identity constructor laws reject foreign Some Ok and Err" {
  for
    (owner, operation) in [
      ("Option", "bind"),
      ("Result", "bind"),
      ("Option", "unwrap"),
      ("Result", "unwrap"),
      ("Result", "unwrap_err"),
    ] {
    let fixture = identity_theorem_fixture(owner, operation)
    put(fixture.symbols[3], "identity", {
      "kind": "constructor",
      "owner_type": { "kind": "named", "package": "foreign", "name": owner },
    })
    assert_false(fixture.matches())
  }
}

///|
test "identity syntax excludes effects extra arguments and block shadowing" {
  for
    expression in [
      "value.unwrap(msg=record())", "value.unwrap(loc=location())", "value.unwrap(record())",
    ] {
    let parsed = @untyped_cst.parse_expression(expression)
    assert_true(parsed.diagnostics_view().is_empty())
    let node = identity_test_node(parsed.root(), node => {
      node.kind is Expr_DotApply
    })
    assert_false(
      dot_call(node).map(call => call.args.is_empty()).unwrap_or(false),
    )
  }
  for
    expression in [
      "x => { print(x); x }", "x => { let x = x + 1; x }", "factory()",
    ] {
    let parsed = @untyped_cst.parse_expression(expression)
    assert_true(parsed.diagnostics_view().is_empty())
    let node = @cst.child(parsed.root(), "expr").unwrap()
    assert_false(
      unary_lambda_parts(node)
      .map(parts => parts.1.kind is Expr_Ident)
      .unwrap_or(false),
    )
  }
}
