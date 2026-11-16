///|
/// Check the compiler's constructor owner for an expression or a pattern,
/// not the spelling of `Some`/`Ok`.
async fn CheckContext::constructor_is(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
  name : String,
) -> Bool {
  let node = if node.kind is Expr_Apply {
    guard @cst.child(node, "func") is Some(callee) && callee.kind is Expr_Constr else {
      return false
    }
    callee
  } else {
    node
  }
  guard node.kind is (Pattern_Constr | Expr_Constr) else { return false }
  guard (self.symbol_at)(node) is Some(symbol) else {
    raise Unavailable("The IDE did not resolve a unique constructor.")
  }
  symbol.kind == "constructor" &&
  symbol.name == name &&
  (match symbol.identity {
    {
      "kind": "constructor",
      "owner_type": { "kind": "builtin", "name": String(found), .. },
      ..
    } => found == owner
    _ => false
  })
}
