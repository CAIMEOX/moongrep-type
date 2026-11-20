///|
fn push_to_array(node : @untyped_cst.CstNode, name : String) -> DotCall? {
  guard dot_call(node) is Some(call) &&
    call.name == "push" &&
    call.args is [value] &&
    no_abrupt_control(value) &&
    @cst.normalized_expr_identifier_name(call.receiver) == Some(name) else {
    return None
  }
  Some(call)
}

///|
/// Only the two inserts and the iteration may observe this array. In
/// particular, a returned or captured array can expose its reserved capacity.
async fn check_conditional_array_spread(
  context : CheckContext,
  statements : Array[@untyped_cst.CstNode],
) -> @basic.Location? {
  guard statements is [binding, branch, append, iteration, ..] &&
    binding.kind is Expr_Let &&
    @cst.child(binding, "pattern") is Some(binder) &&
    @cst.normalized_pattern_identifier_name(binder) is Some(name) &&
    @cst.child(binding, "expr") is Some(initial) &&
    ordinary_array_items(initial) is Some([]) &&
    branch.kind is Expr_If &&
    @cst.child(branch, "else") is None &&
    @cst.child(branch, "cond") is Some(condition) &&
    no_abrupt_control(condition) &&
    @cst.child(branch, "body") is Some(body) &&
    push_to_array(ungroup(body), name) is Some(optional) &&
    push_to_array(append, name) is Some(required) &&
    iteration.kind is Expr_ForEach &&
    @cst.child(iteration, "expr") is Some(source) &&
    @cst.normalized_expr_identifier_name(source) == Some(name) else {
    return None
  }
  guard context.uses_only_at(binder, [
      binder,
      optional.receiver,
      required.receiver,
      source,
    ]) &&
    context.method_is(optional.node, "Array", ["push"]) &&
    context.method_is(required.node, "Array", ["push"]) &&
    array_element(context.shape(initial)) is Some(element) &&
    context.shape(optional.args[0]) == element &&
    context.shape(required.args[0]) == element else {
    return None
  }
  Some(binding.loc.merge(append.loc))
}
