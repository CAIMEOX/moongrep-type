///|
/// Check the compiler's constructor owner, not the spelling of `Some`/`Ok`.
fn CheckContext::constructor_is(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
  name : String,
) -> Bool raise {
  let node = if node.kind is Expr_Apply {
    guard @cst.child(node, "func") is Some(callee) && callee.kind is Expr_Constr else {
      return false
    }
    callee
  } else {
    node
  }
  guard node.kind is Expr_Constr else { return false }
  let fact = self.expression(node)
  guard fact.symbol_id is Some(id) &&
    self.source.index().symbol(id) is Some(symbol) else {
    return false
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
