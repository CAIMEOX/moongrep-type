///|
fn generated_source_fact(
  id : Int,
  kind : String,
  package_name : String,
  generated : Json,
) -> Json {
  let fact = x_fact(id, kind, package_name, 0)
  guard fact is Object(fields) else { abort("fixture fact") }
  fields["details"] = { "generated_top_level": generated }
  fact
}

///|
test "generated filtering precedes package association and preserves raw queries" {
  let text = "fn f(x : Int) -> Int {\n  let s = \"😀\"; x\n}\n"
  let source = Source::parse(
    source_fixture(text, [
      x_fact(0, "expression", "demo@wasm:normal", 0),
      generated_source_fact(1, "expression", "demo@wasm:wbtest", true),
    ]),
    file="/demo/main.mbt",
    text~,
  )
  let node = x_reference(source.root())
  debug_inspect(
    association_ids(source.facts_for_node(node)),
    content="(\"ambiguous\", [0, 1])",
  )
  debug_inspect(
    association_ids(source.facts_for_node(node, include_generated=false)),
    content="(\"associated\", [0])",
  )
  debug_inspect(source.facts().map(f => f.id), content="[0, 1]")
  debug_inspect(
    source.facts(include_generated=false).map(f => f.id),
    content="[0]",
  )
  debug_inspect(
    source.facts_for_capture(Single(node)).map(association_ids),
    content="[(\"ambiguous\", [0, 1])]",
  )
  inspect(source.index().facts().length(), content="2")
}

///|
test "only boolean true marks compiler generated evidence" {
  let text = "fn f(x : Int) -> Int {\n  let s = \"😀\"; x\n}\n"
  let source = Source::parse(
    source_fixture(text, [
      x_fact(0, "expression", "demo", 0),
      generated_source_fact(1, "expression", "demo", false),
      generated_source_fact(2, "expression", "demo", "true"),
      generated_source_fact(3, "expression", "demo", null),
      generated_source_fact(4, "expression", "demo", true),
    ]),
    file="/demo/main.mbt",
    text~,
  )
  debug_inspect(
    association_ids(
      source.facts_for_node(x_reference(source.root()), include_generated=false),
    ),
    content="(\"associated\", [0, 1, 2, 3])",
  )
}

///|
test "generated filtering cannot confer a compatible source role or package" {
  let text = "fn f(x : Int) -> Int {\n  let s = \"😀\"; x\n}\n"
  let source = Source::parse(
    source_fixture(text, [
      x_fact(0, "metadata", "demo", 0),
      generated_source_fact(1, "expression", "demo", true),
    ]),
    file="/demo/main.mbt",
    text~,
  )
  let node = x_reference(source.root())
  assert_true(source.facts_for_node(node) is Associated(_))
  debug_inspect(
    association_ids(source.facts_for_node(node, include_generated=false)),
    content="(\"ambiguous\", [0])",
  )
  let competing = Source::parse(
    source_fixture(text, [
      x_fact(0, "expression", "demo@wasm:normal", 0),
      x_fact(1, "expression", "demo@wasm:wbtest", 0),
      generated_source_fact(2, "expression", "demo@wasm:normal", true),
    ]),
    file="/demo/main.mbt",
    text~,
  )
  debug_inspect(
    association_ids(
      competing.facts_for_node(
        x_reference(competing.root()),
        include_generated=false,
      ),
    ),
    content="(\"ambiguous\", [0, 1])",
  )
}
