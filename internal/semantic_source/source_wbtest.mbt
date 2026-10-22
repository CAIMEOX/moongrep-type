///|
fn source_fixture(text : String, facts : Array[Json]) -> @semantic.Index raise {
  @semantic.Index::from_json(
    {
      "schema_version": 1,
      "compiler_version": "test-compiler",
      "position_encoding": "unicode-scalar",
      "sources": [{ "path": "/demo/main.mbt", "text": Json(text) }],
      "types": [
        { "id": 0, "kind": "builtin", "name": "Int" },
        { "id": 1, "kind": "builtin", "name": "Double" },
      ],
      "symbols": [],
      "facts": Json::array(facts),
    },
    compiler_version="test-compiler",
  )
}

///|
fn x_fact(
  id : Int,
  kind : String,
  package_name : String,
  type_id : Int,
) -> Json {
  {
    "id": Json(id),
    "package": Json(package_name),
    "kind": Json(kind),
    "node_kind": "Texpr_ident",
    "location": {
      "file": "/demo/main.mbt",
      "start": { "line": 2, "column": 16 },
      "end": { "line": 2, "column": 17 },
    },
    "type_id": Json(type_id),
    "symbol_id": null,
    "details": { "implicit": Json(type_id == 1) },
  }
}

///|
fn x_reference(root : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  let pending = [root]
  while pending.pop() is Some(node) {
    if @cst.normalized_expr_identifier_name(node) == Some("x") {
      return node
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  abort("test source must contain x reference")
}

///|
fn association_ids(value : Association) -> (String, Array[Int]) {
  match value {
    Unmatched => ("unmatched", [])
    Associated(facts) => ("associated", facts.map(f => f.id))
    Ambiguous(facts) => ("ambiguous", facts.map(f => f.id))
  }
}

///|
test "whole-file CST facts retain implicit types and Unicode scalar CRLF ranges" {
  let text = "fn f(x : Int) -> Int {\r\n  let s = \"😀\"; x\r\n}\r\n"
  let index = source_fixture(text, [
    x_fact(0, "expression", "demo", 0),
    x_fact(1, "expression", "demo", 1),
  ])
  let source = Source::parse(index, file="/demo/main.mbt", text~)
  let node = x_reference(source.root())
  let range = source.range_for_node(node)
  inspect(
    Repr(
      (range.start.line, range.start.column, range.end.line, range.end.column),
    ),
    content="(2, 16, 2, 17)",
  )
  inspect(
    Repr(association_ids(source.facts_for_node(node))),
    content="(\"associated\", [0, 1])",
  )
  inspect(
    Repr(source.facts_for_capture(Single(node)).map(association_ids)),
    content="[(\"associated\", [0, 1])]",
  )
  inspect(
    Repr(source.facts_for_capture(Multiple([node, node])).map(association_ids)),
    content="[(\"associated\", [0, 1]), (\"associated\", [0, 1])]",
  )
  inspect(source.facts_for_capture(Multiple([])).length(), content="0")
  inspect(
    Repr(association_ids(source.facts_for_node(source.root()))),
    content="(\"unmatched\", [])",
  )
}

///|
test "exact candidates with unknown role or differing packages remain ambiguous" {
  let text = "fn f(x : Int) -> Int {\n  let s = \"😀\"; x\n}\n"
  let unknown = Source::parse(
    source_fixture(text, [x_fact(0, "metadata", "demo", 0)]),
    file="/demo/main.mbt",
    text~,
  )
  inspect(
    Repr(association_ids(unknown.facts_for_node(x_reference(unknown.root())))),
    content="(\"ambiguous\", [0])",
  )
  let different = Source::parse(
    source_fixture(text, [
      x_fact(0, "expression", "demo", 0),
      x_fact(1, "expression", "another", 0),
    ]),
    file="/demo/main.mbt",
    text~,
  )
  inspect(
    Repr(
      association_ids(different.facts_for_node(x_reference(different.root()))),
    ),
    content="(\"ambiguous\", [0, 1])",
  )
}

///|
test "identical spans from another parse cannot acquire facts" {
  let text = "fn f(x : Int) -> Int {\n  let s = \"😀\"; x\n}\n"
  let source = Source::parse(
    source_fixture(text, [x_fact(0, "expression", "demo", 0)]),
    file="/demo/main.mbt",
    text~,
  )
  let other = @untyped_cst.parse_structure(text, name="/demo/main.mbt")
  let result = try {
    ignore(source.facts_for_node(x_reference(other.root())))
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(result, content="CST node does not belong to this semantic source")
}

///|
test "source freshness and syntax are checked before linking" {
  let index = source_fixture("fn f { 1 }", [])
  let stale = try {
    ignore(Source::parse(index, file="/demo/main.mbt", text="fn f { 2 }"))
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(
    stale,
    content="semantic source differs from current source: /demo/main.mbt",
  )
  let broken = "fn f {"
  let result = try {
    ignore(
      Source::parse(
        source_fixture(broken, []),
        file="/demo/main.mbt",
        text=broken,
      ),
    )
    "accepted"
  } catch {
    SourceError::InvalidSource(_) => "parse rejected"
    error => error.to_string()
  }
  inspect(result, content="parse rejected")
}
