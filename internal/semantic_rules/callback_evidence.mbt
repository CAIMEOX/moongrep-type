///|
/// Moving the construction of a callback must not move a factory call or a
/// read of a mutable captured binding. Mutable objects behind stable bindings
/// remain allowed: the laws preserve callback invocations and their effects.
async fn CheckContext::stable_callback(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool {
  let node = ungroup(node)
  if node.kind is Expr_Ident {
    return self.stable_identifier(node)
  }
  guard node.kind is Expr_Function else { return false }
  let range = self.range(node)
  let pending = [node]
  while pending.pop() is Some(current) {
    if current.kind is Expr_Ident {
      guard (self.symbol_at)(current) is Some(symbol) else { return false }
      if symbol.kind == "local" {
        guard (self.binding)(symbol.id) is Some(location) &&
          self.binders.get(location) is Some(mutable_binding) else {
          return false
        }
        if mutable_binding && !range_contains(range, location) {
          return false
        }
      } else if symbol.kind != "global" {
        return false
      }
    }
    for (_, child) in current.children {
      pending.push(child)
    }
  }
  true
}

///|
fn range_contains(outer : @semantic.Range, inner : @semantic.Range) -> Bool {
  outer.file == inner.file &&
  (
    outer.start.line < inner.start.line ||
    (
      outer.start.line == inner.start.line &&
      outer.start.column <= inner.start.column
    )
  ) &&
  (
    outer.end.line > inner.end.line ||
    (outer.end.line == inner.end.line && outer.end.column >= inner.end.column)
  )
}
