///|
async fn check_iterator_literal(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  match node.kind {
    Expr_Apply => {
      guard @cst.child(node, "func") is Some(callee) &&
        callee.kind is Expr_Method &&
        @cst.raw_child(callee, "field").bind(@cst.normalized_name) is Some(name) &&
        positional_args(node) is Some(args) &&
        (match (name, args) {
          ("empty", []) | ("singleton", [_]) => true
          _ => false
        }) &&
        context.method_is(callee, "Iter", [name]) &&
        container_element(context.shape(node), "Iter") is Some(_) else {
        return None
      }
    }
    Expr_DotApply => {
      guard dot_call(node) is Some(call) &&
        call.name == "iter" &&
        call.args.is_empty() &&
        ordinary_array_items(call.receiver) is Some(_) &&
        standard_call(context, call, ["Array"]) is Some([element]) &&
        container_element(context.shape(node), "Iter") == Some(element) else {
        return None
      }
    }
    _ => return None
  }
  Some(node.loc)
}
