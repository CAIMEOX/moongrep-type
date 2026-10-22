///|
test "filter-map comprehension excludes partial payload patterns" {
  let parsed = @untyped_cst.parse_expression(
    "fn(x) { match x { Some(value) => 1; Some(0) => 2; Some(_) => 3; None => 4 } }",
  )
  assert_true(parsed.diagnostics_view().is_empty())
  let signatures = []
  let pending = [parsed.root()]
  while pending.pop() is Some(node) {
    if node.kind is Pattern_Constr {
      signatures.push(
        (
          node.source_span.0,
          exhaustive_option_pattern(node, "Some") ||
          exhaustive_option_pattern(node, "None"),
        ),
      )
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  signatures.sort_by((a, b) => a.0.compare(b.0))
  debug_inspect(
    signatures.map(pair => pair.1),
    content="[true, false, true, true]",
  )
}
