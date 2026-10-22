///|
/// Moving the construction of a callback must not move a factory call or a
/// read of a mutable captured binding. Mutable objects behind stable bindings
/// remain allowed: the laws preserve callback invocations and their effects.
fn CheckContext::stable_callback(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool raise {
  let node = ungroup(node)
  if node.kind is Expr_Ident {
    return self.stable_identifier(node)
  }
  guard node.kind is Expr_Function else { return false }
  let range = self.source.range_for_node(node)
  let pending = [node]
  while pending.pop() is Some(current) {
    if current.kind is Expr_Ident {
      let id = self.symbol_id(current)
      guard self.source.index().symbol(id) is Some(symbol) else { return false }
      if symbol.kind == "local" {
        guard self.facts_by_symbol.get(id) is Some(facts) else { return false }
        let mut bound = false
        for fact in facts {
          if fact.kind == "binding" && fact.location is Some(location) {
            bound = true
            if self.mutable_bindings.contains(location) &&
              !range_contains(range, location) {
              return false
            }
          }
        }
        guard bound else { return false }
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
