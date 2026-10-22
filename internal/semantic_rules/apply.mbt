///|
pub(all) struct RuleWarning {
  rule_id : String
  loc : @basic.Location
  reason : String
}

///|
pub(all) struct RuleReport {
  findings : Array[@rule_model.RuleFinding]
  warnings : Array[RuleWarning]
}

///|
/// Apply YAML semantic rules to original nodes of a validated source. Regex
/// guards and structural matching use the same matcher as ordinary rules.
pub fn apply_rules(
  source : @semantic_source.Source,
  rules : ArrayView[@rule_model.CompiledRule],
  roots~ : Array[@untyped_cst.CstNode] = @cst.toplevel_nodes(source.root()),
) -> RuleReport raise {
  let context = CheckContext::new(source)
  let candidates : Array[@cst.ExprMatchCandidate] = []
  for root in roots {
    ignore(source.range_for_node(root))
    @cst.visit_expr_match_candidate_roots(root, fn(candidate) {
      candidates.push(candidate)
      NodeVisitContinue
    })
  }
  let report : RuleReport = { findings: [], warnings: [], }
  for rule in rules {
    guard rule.definition is Semantic(definition) else { continue }
    let reported : Map[(Int, Int), Bool] = Map([])
    let covered : Array[@basic.Location] = []
    for candidate in candidates {
      for pattern_index, pattern in definition.patterns {
        guard @rule_apply.match_plain_rule_pattern(pattern, candidate)
          is Some(matched) else {
          continue
        }
        if definition.check is IterComprehension &&
          covered.any(loc => {
            loc.start.cnum <= matched.loc.start.cnum &&
            loc.end.cnum >= matched.loc.end.cnum
          }) {
          break
        }
        let location = evaluate_semantic_check(
          context,
          definition.check,
          candidate,
        ) catch {
          Unavailable(reason) => {
            let key = (matched.loc.start.cnum, matched.loc.end.cnum)
            if !reported.contains(key) {
              reported[key] = true
              report.warnings.push({
                rule_id: rule.rule_id,
                loc: matched.loc,
                reason,
              })
            }
            None
          }
          Skip(reason) => {
            if [
                "missing_exact_semantics", "ambiguous_semantics", "non_unique_expression_type",
                "unknown_type",
              ].contains(reason) {
              let key = (matched.loc.start.cnum, matched.loc.end.cnum)
              if !reported.contains(key) {
                reported[key] = true
                report.warnings.push({
                  rule_id: rule.rule_id,
                  loc: matched.loc,
                  reason,
                })
              }
            }
            None
          }
          error => raise error
        }
        if location is Some(loc) {
          let key = (loc.start.cnum, loc.end.cnum)
          if !reported.contains(key) {
            reported[key] = true
            covered.push(loc)
            report.findings.push({
              file: source.file(),
              rule_id: rule.rule_id,
              description: rule.description,
              pattern_index,
              loc,
            })
          }
          break
        }
      }
    }
  }
  report
}

///|
fn evaluate_semantic_check(
  context : CheckContext,
  check : @rule_model.SemanticCheck,
  candidate : @cst.ExprMatchCandidate,
) -> @basic.Location? raise {
  match check {
    ArrayComprehension =>
      check_array_builder(context, candidate_items(candidate))
    _ => {
      guard candidate is Direct(node) else { return None }
      match check {
        FilterMapComprehension => check_filter_map(context, node)
        IterComprehension => check_iter_pipeline(context, node)
        CollectCount => check_collect_count(context, node)
        ArrayFilterCount => check_array_filter_count(context, node)
        IterFilterCount => check_iter_filter_count(context, node)
        IterFilterNext => check_iter_filter_next(context, node)
        IterFindFirstExists => check_iter_find_first_exists(context, node)
        IterMapFlatten => check_iter_map_flatten(context, node)
        DiscardedArrayMap => check_discarded_map(context, node)
        ConsumedIterator => check_consumed_iterator(context, node)
        ArrayMapFusion => {
          guard map_call(node) is Some(outer) &&
            map_call(outer.receiver) is Some(inner) else {
            return None
          }
          ignore(analyze_chain(context.source, outer, inner))
          Some(node.loc)
        }
        ArrayComprehension => None
      }
    }
  }
}
