///|
async fn core_scalar_equality(
  context : CheckContext,
  expr : @untyped_cst.CstNode,
) -> Bool {
  guard (context.symbol_at)(expr) is Some(symbol) else {
    raise Unavailable("The IDE could not resolve the equality operator.")
  }
  symbol.kind == "global" &&
  symbol.identity
  is {
    "kind": "trait_impl",
    "package": "moonbitlang/core/builtin",
    "trait": trait_path,
    "name": "equal",
    ..
  } &&
  builtin_owner_is(trait_path, "Eq")
}

///|
async fn check_repeated_classifier(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard node.kind is Expr_Infix && @cst.operator_name(node) == Some("||") else {
    return None
  }
  let alternatives : LiteralAlternatives = { numbers: [], strings: Set([]), }
  let pending = [node]
  let subjects = []
  let comparisons = []
  let mut name = None
  while pending.pop() is Some(branch) {
    let (subject, pattern) = if branch.kind is Expr_Is {
      guard @cst.child(branch, "expr") is Some(subject) &&
        @cst.child(branch, "pattern") is Some(pat) else {
        return None
      }
      (ungroup(subject), pat)
    } else {
      guard infix_parts(branch) is Some((op, left, right)) else { return None }
      if op == "||" {
        pending.push(right)
        pending.push(left)
        continue
      }
      guard op == "==" && right.kind is Expr_Constant else { return None }
      comparisons.push(branch)
      (left, right)
    }
    guard @cst.normalized_expr_identifier_name(subject) is Some(found) &&
      (name is None || name == Some(found)) &&
      alternatives.add(pattern) else {
      return None
    }
    name = Some(found)
    subjects.push(subject)
  }
  // A mixed expression, a binding pattern or overlapping literals need no IDE process.
  guard subjects is [first, .. rest] &&
    fixed_value(context, first) &&
    alternatives.fits(context.shape(first)) else {
    return None
  }
  let id = context.symbol_id(first)
  for other in rest {
    if context.symbol_id(other) != id {
      return None
    }
  }
  for comparison in comparisons {
    if !core_scalar_equality(context, comparison) {
      return None
    }
  }
  Some(node.loc)
}
