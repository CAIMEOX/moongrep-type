///|
fn float_test_call(node : @untyped_cst.CstNode, negated : Bool) -> DotCall? {
  let expr = if negated {
    guard node.kind is Expr_Unary &&
      @cst.operator_name(node) == Some("!") &&
      @cst.child(node, "expr") is Some(arg) else {
      return None
    }
    ungroup(arg)
  } else {
    node
  }
  guard dot_call(expr) is Some(call) &&
    call.args.is_empty() &&
    (call.name == "is_nan" || call.name == "is_inf") &&
    call.receiver.kind is Expr_Ident else {
    return None
  }
  Some(call)
}

///|
async fn core_float_method(
  context : CheckContext,
  call : DotCall,
  number : String,
) -> Bool {
  guard (context.symbol_at)(call.node) is Some(symbol) else {
    raise Unavailable("The IDE could not resolve the floating-point predicate.")
  }
  guard symbol.kind == "global" &&
    symbol.identity
    is { "kind": "method", "name": String(name), "self_type": owner, .. } &&
    name == call.name else {
    return false
  }
  let pkg = if builtin_owner_is(owner, number) {
    "moonbitlang/core/builtin"
  } else if number == "Float" &&
    owner
    is {
      "kind": "named",
      "package": "moonbitlang/core/float",
      "name": "Float",
      ..
    } {
    "moonbitlang/core/float"
  } else {
    return false
  }
  (context.exports_method)(symbol, pkg, number, "is_finite", 1)
}

///|
async fn check_float_finiteness(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard node.kind is Expr_Infix &&
    infix_parts(node) is Some((op, lhs, rhs)) &&
    (op == "||" || op == "&&") &&
    float_test_call(lhs, op == "&&") is Some(first) else {
    return None
  }
  // The CST can place the second test at the head of a longer right-associative
  // chain. A parenthesized tail has its own bounds and must stay intact.
  let (second_expr, loc) = if @cst.raw_child(node, "rhs") is Some(tail) &&
    tail.kind is Expr_Infix &&
    @cst.operator_name(tail) == Some(op) &&
    @cst.raw_child(tail, "lhs") is Some(head) &&
    @cst.raw_child(node, "lhs") is Some(start) {
    (ungroup(head), start.loc.merge(head.loc))
  } else {
    (rhs, node.loc)
  }
  guard float_test_call(second_expr, op == "&&") is Some(second) &&
    first.name != second.name &&
    @cst.normalized_expr_identifier_name(first.receiver) is Some(receiver) &&
    @cst.normalized_expr_identifier_name(second.receiver) == Some(receiver) &&
    context.finite_oracles.get(node.source_span) != Some(receiver) &&
    fixed_value(context, first.receiver) &&
    context.symbol_id(first.receiver) == context.symbol_id(second.receiver) else {
    return None
  }
  let number = match context.shape(first.receiver) {
    { "kind": "builtin", "name": String(name), .. } if name == "Double" ||
      name == "Float" => name
    {
      "kind": "named",
      "path": { "package": "moonbitlang/core/float", "name": "Float", .. },
      ..
    } => "Float"
    _ => return None
  }
  guard core_float_method(context, first, number) &&
    core_float_method(context, second, number) else {
    return None
  }
  Some(loc)
}

///|
fn without_not(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  let node = ungroup(node)
  if node.kind is Expr_Unary &&
    @cst.operator_name(node) == Some("!") &&
    @cst.child(node, "expr") is Some(arg) {
    ungroup(arg)
  } else {
    node
  }
}

///|
/// Keep an independent oracle such as assert_eq(x.is_finite(), !(...)).
/// Other code in the same test remains eligible.
fn CheckContext::record_finite_comparison(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Unit {
  let (left, right) = match node.kind {
    Expr_Infix => {
      guard infix_parts(node) is Some((op, a, b)) && (op == "==" || op == "!=") else {
        return
      }
      (a, b)
    }
    Expr_Apply => {
      guard @cst.child(node, "func").bind(@cst.normalized_expr_identifier_name)
        is Some(name) &&
        (
          name == "assert_eq" ||
          name == "assert_not_eq" ||
          name.has_suffix(".assert_eq") ||
          name.has_suffix(".assert_not_eq")
        ) &&
        @cst.child(node, "arg") is Some(args) &&
        @cst.items(args) is [a, b, ..] &&
        a.kind is Argument_Positional &&
        b.kind is Argument_Positional &&
        @cst.argument_value(a) is Some(a) &&
        @cst.argument_value(b) is Some(b) else {
        return
      }
      (a, b)
    }
    _ => return
  }
  for (direct, expanded) in [(left, right), (right, left)] {
    let expanded = without_not(expanded)
    if expanded.kind is Expr_Infix &&
      dot_call(without_not(direct)) is Some(call) &&
      call.name == "is_finite" &&
      call.args.is_empty() &&
      @cst.normalized_expr_identifier_name(call.receiver) is Some(name) {
      self.finite_oracles[expanded.source_span] = name
    }
  }
}
