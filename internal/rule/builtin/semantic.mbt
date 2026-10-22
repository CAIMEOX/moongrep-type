///|
/// Optional semantic builtins. The CLI enables them only with a checked index.
pub fn load_semantic_rules() -> Array[RawRuleSpec] raise {
  let sources : Array[(String, String)] = [
    (
      "prefer_array_comprehension", @moonbitlang_rules.prefer_array_comprehension_yaml,
    ),
    (
      "prefer_filter_map_comprehension", @moonbitlang_rules.prefer_filter_map_comprehension_yaml,
    ),
    (
      "prefer_iter_comprehension", @moonbitlang_rules.prefer_iter_comprehension_yaml,
    ),
    ("avoid_collect_for_count", @moonbitlang_rules.avoid_collect_for_count_yaml),
    ("discarded_array_map", @moonbitlang_rules.discarded_array_map_yaml),
    ("consumed_iterator", @moonbitlang_rules.consumed_iterator_yaml),
    ("array_map_fusion", @moonbitlang_rules.array_map_fusion_yaml),
    ("array_filter_count", @moonbitlang_rules.array_filter_count_yaml),
    ("iter_filter_count", @moonbitlang_rules.iter_filter_count_yaml),
    ("iter_filter_next", @moonbitlang_rules.iter_filter_next_yaml),
    ("iter_find_first_exists", @moonbitlang_rules.iter_find_first_exists_yaml),
    ("iter_map_flatten", @moonbitlang_rules.iter_map_flatten_yaml),
    ("option_map_fusion", @moonbitlang_rules.option_map_fusion_yaml),
    ("result_map_fusion", @moonbitlang_rules.result_map_fusion_yaml),
    ("result_map_err_fusion", @moonbitlang_rules.result_map_err_fusion_yaml),
    ("option_bind_map", @moonbitlang_rules.option_bind_map_yaml),
    ("result_bind_map", @moonbitlang_rules.result_bind_map_yaml),
    ("result_map_flatten", @moonbitlang_rules.result_map_flatten_yaml),
    ("option_filter_fusion", @moonbitlang_rules.option_filter_fusion_yaml),
    ("option_map_default", @moonbitlang_rules.option_map_default_yaml),
  ]
  sources.map(fn(source) raise {
    @model.RawRuleSpec::from_str(
      "builtin/moonbitlang/\{source.0}.yaml",
      builtin_rules_root,
      source.1,
    )
  })
}
