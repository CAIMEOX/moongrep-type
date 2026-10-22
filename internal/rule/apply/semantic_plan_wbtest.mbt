///|
test "semantic builtins compile through the shared YAML and matcher pipeline" {
  let rules = @compile.compile_rules(@builtin.load_semantic_rules())
  inspect(rules.length(), content="27")
  let plan = ScanPlan::from_rules(rules)
  assert_false(plan.is_empty())
  inspect(plan.semantic_rules().length(), content="27")
  assert_true(plan.without_semantic_rules().is_empty())
  let relevant = plan.filter_source("xs.collect().length()").semantic_rules()
  assert_true(
    relevant.any(rule => rule.rule_id == "moonbitlang/avoid_collect_for_count"),
  )
  assert_false(
    relevant.any(rule => rule.rule_id == "moonbitlang/array_map_fusion"),
  )
}
