///|
/// Moving a let into a header joins two binding scopes. Collect only
/// irrefutable tuple components, rejecting duplicate binders in the new scope.
fn collect_tuple_binders(
  pattern : @untyped_cst.CstNode,
  names : Set[String],
) -> Bool {
  match pattern.kind {
    Pattern_Any => true
    Pattern_Var => {
      guard @cst.normalized_pattern_identifier_name(pattern) is Some(name) &&
        !names.contains(name) else {
        return false
      }
      names.add(name)
      true
    }
    Pattern_Tuple => {
      guard @cst.child(pattern, "body") is Some(body) else { return false }
      let items = @cst.items(body)
      items.length() >= 2 && items.all(p => collect_tuple_binders(p, names))
    }
    _ => false
  }
}

///|
async fn check_loop_tuple_unpack(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard node.kind is Expr_ForEach &&
    @cst.child(node, "pattern") is Some(header) &&
    @cst.child(node, "body") is Some(body) &&
    @cst.sequence_items(body) is [binding, ..] &&
    binding.kind is Expr_Let &&
    @cst.child(binding, "type") is None &&
    @cst.child(binding, "pattern") is Some(tuple) &&
    tuple.kind is Pattern_Tuple &&
    @cst.child(tuple, "body") is Some(parts) &&
    @cst.items(parts).length() == 2 &&
    @cst.child(binding, "expr") is Some(value) &&
    @cst.normalized_expr_identifier_name(value) is Some(name) else {
    return None
  }
  for field in ["init", "continue", "where", "else"] {
    if @cst.child(node, field) is Some(_) {
      return None
    }
  }
  let names : Set[String] = Set([])
  guard collect_tuple_binders(tuple, names) && !names.is_empty() else {
    return None
  }
  let binder = if header.kind is List_TuplePatternList {
    guard @cst.items(header) is [left, right] else { return None }
    let (binder, other) = if @cst.normalized_pattern_identifier_name(left) ==
      Some(name) {
      (left, right)
    } else {
      (right, left)
    }
    guard collect_tuple_binders(other, names) else { return None }
    binder
  } else {
    header
  }
  guard @cst.normalized_pattern_identifier_name(binder) == Some(name) &&
    context.uses_only_at(binder, [binder, value]) else {
    return None
  }
  guard (context.is_tuple_at)(value, 2) is Some(is_pair) else {
    raise Unavailable(
      "The IDE did not provide an exact expression type for the unpacked value.",
    )
  }
  if is_pair {
    Some(binding.loc)
  } else {
    None
  }
}
