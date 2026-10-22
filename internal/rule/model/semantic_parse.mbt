///|
fn expect_semantic_rule(
  doc : Map[String, @yaml.Yaml],
  path : String,
) -> SemanticRuleSpec raise {
  guard doc.get("semantic") is Some(Map(body)) else {
    raise invalid_rule(path~, info="semantic must be a mapping")
  }
  ensure_allowed_keys(path, "semantic", body, ["check", "patterns"])
  let check = match body.get("check") {
    Some(String("array-comprehension")) => ArrayComprehension
    Some(String("filter-map-comprehension")) => FilterMapComprehension
    Some(String("iter-comprehension")) => IterComprehension
    Some(String("collect-count")) => CollectCount
    Some(String("discarded-array-map")) => DiscardedArrayMap
    Some(String("consumed-iterator")) => ConsumedIterator
    Some(String("array-map-fusion")) => ArrayMapFusion
    Some(String("array-filter-count")) => ArrayFilterCount
    Some(String("iter-filter-count")) => IterFilterCount
    Some(String("iter-filter-next")) => IterFilterNext
    Some(String("iter-find-first-exists")) => IterFindFirstExists
    Some(String("iter-map-flatten")) => IterMapFlatten
    Some(String(name)) =>
      raise invalid_rule(path~, info="unknown semantic.check: \{name}")
    _ =>
      raise invalid_rule(
        path~,
        info="semantic.check must name a supported check",
      )
  }
  let patterns = parse_rule_clause_array(
    expect_yaml_array(body, path, "patterns"),
    path,
    "semantic.patterns",
    allow_guard=true,
    allow_match_mode=false,
  )
  if patterns.is_empty() {
    raise invalid_rule(path~, info="semantic.patterns must not be empty")
  }
  { check, patterns, }
}
