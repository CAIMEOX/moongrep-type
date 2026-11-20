///|
async fn check_iter_next_loop(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard node.kind is Expr_While &&
    @cst.child(node, "cond") is Some(condition) &&
    condition.kind is Expr_Is &&
    @cst.child(condition, "pattern") is Some(pat) &&
    pat.kind is Pattern_Constr &&
    @cst.child(pat, "params") is Some(params) &&
    @cst.items(params) is [item] &&
    item.kind is (Pattern_Var | Pattern_Any) &&
    @cst.child(condition, "expr") is Some(expr) &&
    dot_call(ungroup(expr)) is Some(call) &&
    call.name == "next" &&
    call.args.is_empty() &&
    call.receiver.kind is Expr_Ident &&
    fixed_value(context, call.receiver) &&
    standard_call(context, call, ["Iter"]) is Some([_]) &&
    context.constructor_is(pat, "Option", "Some") else {
    return None
  }
  Some(@cst.raw_child(node, "kw").unwrap_or(condition).loc.merge(condition.loc))
}

///|
async fn check_direct_view_iteration(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard node.kind is Expr_ForEach &&
    @cst.child(node, "pattern") is Some(pat) &&
    pat.kind is (Pattern_Var | Pattern_Any) &&
    @cst.child(node, "expr") is Some(expr) &&
    dot_call(ungroup(expr)) is Some(call) &&
    call.name == "iter" &&
    call.args.is_empty() &&
    standard_call(context, call, ["String", "StringView", "Bytes", "BytesView"])
    is Some([]) else {
    return None
  }
  Some(call.node.loc)
}
