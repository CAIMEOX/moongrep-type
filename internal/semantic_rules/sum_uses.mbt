///|
/// Record the immediate consumer of a map/bind result. An enclosing match or
/// method elsewhere in the expression tells us nothing about this value.
fn CheckContext::record_sum_use(
  self : CheckContext,
  parent : @untyped_cst.CstNode,
) -> Unit {
  let operand = match parent.kind {
    Expr_Match | Expr_Is => @cst.child(parent, "expr")
    Expr_DotApply => @cst.child(parent, "self")
    _ => return
  }
  guard operand is Some(operand) else { return }
  let operand = ungroup(operand)
  guard operand.kind is Expr_DotApply &&
    @cst.child(operand, "field").bind(@cst.normalized_name)
    is (Some("map") | Some("bind")) else {
    return
  }
  self.sum_uses[operand.source_span] = parent
}

///|
/// Reconstructing a variant can change physical_equal even when both its tag
/// and its payload are identical. Prove that the consumer sees only those two.
async fn CheckContext::consumes_sum(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
) -> Bool {
  guard self.sum_uses.get(node.source_span) is Some(parent) else {
    return false
  }
  let patterns = match parent.kind {
    Expr_Is => {
      guard @cst.child(parent, "pattern") is Some(pattern) else { return false }
      [pattern]
    }
    Expr_Match => {
      let cases = match_cases(parent)
      guard !cases.is_empty() else { return false }
      let patterns = []
      for arm in cases {
        guard @cst.child(arm, "pattern") is Some(pattern) else { return false }
        patterns.push(pattern)
      }
      patterns
    }
    Expr_DotApply => {
      let names = if owner == "Option" {
        ["unwrap", "unwrap_or", "unwrap_or_else", "is_some", "is_none"]
      } else {
        [
          "unwrap", "unwrap_err", "unwrap_or", "unwrap_or_else", "is_ok", "is_err",
        ]
      }
      guard dot_call(parent) is Some(call) && names.contains(call.name) else {
        return false
      }
      return self.method_is(parent, owner, names)
    }
    _ => return false
  }
  for pattern in patterns {
    if pattern.kind is Pattern_Any {
      continue
    }
    guard pattern.kind is Pattern_Constr else { return false }
    let (first, second) = if owner == "Option" {
      ("Some", "None")
    } else {
      ("Ok", "Err")
    }
    guard self.constructor_is(pattern, owner, first) ||
      self.constructor_is(pattern, owner, second) else {
      return false
    }
  }
  true
}
