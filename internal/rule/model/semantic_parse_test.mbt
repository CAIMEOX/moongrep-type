///|
test "semantic YAML selects a check and reuses structural guards" {
  let source =
    #|id: count
    #|description: Custom count hint.
    #|semantic:
    #|  check: collect-count
    #|  patterns:
    #|    - shape: $(it:id).collect().length()
    #|      guard:
    #|        $it: '^values$'
  let rule = @model.RawRuleSpec::from_str("/rules/count.yaml", "/rules", source)
  guard rule.definition is Semantic(spec) else {
    fail("expected semantic rule")
  }
  assert_true(spec.check is CollectCount)
  inspect(spec.patterns[0].guards["$it"], content="^values$")
}

///|
test "semantic YAML rejects unknown checks mixed modes and nested schemas" {
  let prefix = "id: custom\ndescription: Custom.\n"
  let cases = [
    ("semantic: []", "semantic must be a mapping"),
    ("semantic: {check: nope, patterns: []}", "unknown semantic.check: nope"),
    (
      "semantic: {check: collect-count, patterns: []}", "semantic.patterns must not be empty",
    ),
    (
      "semantic: {check: collect-count, patterns: [{shape: target(), then: {}}]}",
      "semantic.patterns[0] contains unsupported key then",
    ),
    (
      "semantic: {check: collect-count, patterns: [{shape: target()}], script: unsafe}",
      "semantic contains unsupported key script",
    ),
    (
      "patterns: [{shape: target()}]\nsemantic: {check: collect-count, patterns: [{shape: target()}]}",
      "semantic cannot be combined with structural or taint fields",
    ),
  ]
  for (body, expected) in cases {
    expect_invalid_rule_info(prefix + body, expected)
  }
}
