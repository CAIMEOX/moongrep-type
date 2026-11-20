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
priv struct Match {
  candidate : @cst.ExprMatchCandidate
  check : @rule_model.SemanticCheck
  rule_id : String
  description : String
  enclosing_method : String?
  pattern_index : Int32
  loc : @basic.Location
}

///|
/// Original syntax and only the candidates accepted by enabled YAML shapes and guards.
pub struct Candidates {
  priv file : String
  priv text : String
  priv tree : @untyped_cst.CstNode
  priv matches : Array[Match]
}

///|
pub fn Candidates::select(
  file : String,
  text : String,
  tree : @untyped_cst.CstNode,
  roots : Array[@untyped_cst.CstNode],
  rules : ArrayView[@rule_model.CompiledRule],
) -> Candidates {
  let matches : Array[Match] = []
  let nodes : Array[(@cst.ExprMatchCandidate, String?)] = []
  for root in roots {
    let enclosing_method = @cst.raw_child(root, "method").bind(
      @cst.normalized_name,
    )
    @cst.visit_expr_match_candidate_roots(root, candidate => {
      nodes.push((candidate, enclosing_method))
      NodeVisitContinue
    })
  }
  for rule in rules {
    guard rule.definition is Semantic(definition) else { continue }
    for (candidate, enclosing_method) in nodes {
      if candidate is Sequence(_) &&
        !(definition.check is (ArrayComprehension | ConditionalArraySpread)) {
        continue
      }
      for pattern_index, pattern in definition.patterns {
        guard @rule_apply.match_plain_rule_pattern(pattern, candidate)
          is Some(matched) else {
          continue
        }
        matches.push({
          candidate,
          check: definition.check,
          rule_id: rule.rule_id,
          description: rule.description,
          enclosing_method,
          pattern_index,
          loc: matched.loc,
        })
        break
      }
    }
  }
  { file, text, tree, matches, }
}

///|
pub fn Candidates::is_empty(self : Candidates) -> Bool {
  self.matches.is_empty()
}

///|
priv suberror InactiveFile

///|
async fn Candidates::context(
  self : Candidates,
  session : @ide.Session,
) -> CheckContext {
  let path = @fs.realpath(self.file)
  // Even a YAML match can be rejected using only syntax. Share the first
  // real demand for project information across every verifier in this file.
  let checked = @async.Lazy::Lazy(() => {
    guard session.file(self.file, self.text, self.tree) is Some(file) else {
      raise InactiveFile
    }
    guard file.path() == path else {
      fail("candidate source path changed: \{self.file}")
    }
    file
  })
  async fn active(node : @untyped_cst.CstNode) -> @ide.CheckedFile {
    let file = checked.wait()
    if file.excludes(node) {
      raise Skip("inactive_declaration")
    }
    file
  }
  let context : CheckContext = {
    file: path,
    text: self.text,
    package_name: () => checked.wait().package_name(),
    shape_at: node => {
      let file = active(node)
      file.type_at(node).bind(id => type_shape(i => file.raw_type(i), id))
    },
    is_tuple_at: (node, arity) => active(node).is_tuple_at(node, arity),
    call_header_at: node => {
      let file = active(node)
      file.type_at(node).bind(id => file.raw_type(id)).bind(function_header)
    },
    symbol_at: node => active(node).symbol_at(node),
    exports_method: (witness, pkg, owner, name, arity) => {
      checked.wait().exports_method(witness, pkg, owner, name, arity)
    },
    binding: id => checked.wait().binding(id),
    references: node => active(node).references(node),
    binders: {},
    local_callbacks: Set([]),
    finite_oracles: {},
    sum_uses: Map([]),
    previous: {},
  }
  context.inspect_syntax(
    self.tree,
    finite_checks=self.matches.any(hit => hit.check is Stdlib(FloatFiniteness)),
  )
  context
}

///|
priv enum Outcome {
  Finding(@basic.Location)
  Warning(String)
  Rejected
}

///|
async fn verify_match(context : CheckContext, hit : Match) -> Outcome {
  try {
    match evaluate_semantic_check(context, hit.check, hit.candidate) {
      Some(loc) => {
        if hit.check is Stdlib(check) &&
          hit.enclosing_method == Some(check.suggested_method()) {
          let pkg = (context.package_name)()
          if pkg.has_prefix("moonbitlang/core/builtin@") ||
            (
              check is FloatFiniteness &&
              pkg.has_prefix("moonbitlang/core/float@")
            ) {
            return Rejected
          }
        }
        Finding(loc)
      }
      None => Rejected
    }
  } catch {
    Unavailable(reason) => Warning(reason)
    Skip(reason) =>
      if [
          "missing_exact_semantics", "ambiguous_semantics", "non_unique_expression_type",
          "unknown_type",
        ].contains(reason) {
        Warning(reason)
      } else {
        Rejected
      }
    e => raise e
  }
}

///|
pub async fn Candidates::verify(
  self : Candidates,
  session : @ide.Session,
) -> RuleReport {
  let report : RuleReport = { findings: [], warnings: [], }
  if self.matches.is_empty() {
    return report
  }
  let context = self.context(session)
  let jobs : Array[async () -> Outcome] = self.matches.map(hit => {
    () => verify_match(context, hit)
  })
  let outcomes = @async.all(jobs[:], max_concurrent=4) catch {
    InactiveFile => return report
    err => raise err
  }
  let seen : Set[(String, Int32, Int32)] = Set([])
  let covered : Map[String, Array[@basic.Location]] = Map([])
  for i, hit in self.matches {
    let prefer_outer = hit.check is (IterComprehension | RepeatedClassifier)
    if prefer_outer &&
      covered.get(hit.rule_id) is Some(outer) &&
      outer.any(loc => {
        loc.start.cnum <= hit.loc.start.cnum && loc.end.cnum >= hit.loc.end.cnum
      }) {
      continue
    }
    match outcomes[i] {
      Finding(loc) => {
        let key = (hit.rule_id, loc.start.cnum, loc.end.cnum)
        if seen.contains(key) {
          continue
        }
        seen.add(key)
        if prefer_outer {
          if covered.get(hit.rule_id) is Some(locs) {
            locs.push(loc)
          } else {
            covered[hit.rule_id] = [loc]
          }
        }
        report.findings.push({
          file: self.file,
          rule_id: hit.rule_id,
          description: hit.description,
          pattern_index: hit.pattern_index,
          loc,
        })
      }
      Warning(reason) => {
        let key = (hit.rule_id, hit.loc.start.cnum, hit.loc.end.cnum)
        if !seen.contains(key) {
          seen.add(key)
          report.warnings.push({ rule_id: hit.rule_id, loc: hit.loc, reason, })
        }
      }
      Rejected => ()
    }
  }
  report
}

///|
async fn evaluate_semantic_check(
  context : CheckContext,
  check : @rule_model.SemanticCheck,
  candidate : @cst.ExprMatchCandidate,
) -> @basic.Location? {
  match check {
    ConditionalArraySpread =>
      check_conditional_array_spread(context, candidate_items(candidate))
    ArrayComprehension =>
      check_array_builder(context, candidate_items(candidate))
    _ => {
      guard candidate is Direct(node) else { return None }
      match check {
        Stdlib(check) => check_standard_library(context, node, check)
        LoopTupleUnpack => check_loop_tuple_unpack(context, node)
        RepeatedClassifier => check_repeated_classifier(context, node)
        IteratorLiteral => check_iterator_literal(context, node)
        FilterMapComprehension => check_filter_map(context, node)
        IterComprehension => check_iter_pipeline(context, node)
        CollectCount => check_collect_count(context, node)
        ArrayFilterCount => check_array_filter_count(context, node)
        IterFilterCount => check_iter_filter_count(context, node)
        IterFilterNext => check_iter_filter_next(context, node)
        IterFindFirstExists => check_iter_find_first_exists(context, node)
        IterMapFlatten => check_iter_map_flatten(context, node)
        OptionMapFusion =>
          check_optional_map_fusion(context, node, "Option", "map")
        ResultMapFusion =>
          check_optional_map_fusion(context, node, "Result", "map")
        ResultMapErrFusion =>
          check_optional_map_fusion(context, node, "Result", "map_err")
        OptionBindMap => check_bind_map(context, node, "Option")
        ResultBindMap => check_bind_map(context, node, "Result")
        ResultMapFlatten => check_result_map_flatten(context, node)
        OptionFilterFusion => check_option_filter_fusion(context, node)
        OptionMapDefault => check_option_map_default(context, node)
        OptionMapIdentity => check_map_identity(context, node, "Option")
        ResultMapIdentity => check_map_identity(context, node, "Result")
        OptionBindIdentity => check_bind_identity(context, node, "Option")
        ResultBindIdentity => check_bind_identity(context, node, "Result")
        OptionUnwrapSome =>
          check_constructor_unwrap(context, node, "Option", "Some", "unwrap")
        ResultUnwrapOk =>
          check_constructor_unwrap(context, node, "Result", "Ok", "unwrap")
        ResultUnwrapErr =>
          check_constructor_unwrap(context, node, "Result", "Err", "unwrap_err")
        DiscardedArrayMap => check_discarded_map(context, node)
        ConsumedIterator => check_consumed_iterator(context, node)
        ArrayMapFusion => {
          guard map_call(node) is Some(outer) &&
            map_call(outer.receiver) is Some(inner) else {
            return None
          }
          ignore(analyze_chain(context, outer, inner))
          Some(node.loc)
        }
        ArrayComprehension | ConditionalArraySpread => None
      }
    }
  }
}
