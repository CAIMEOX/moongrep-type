///|
/// A callback named by #locals can be called in its function body. Capturing
/// it in the closure suggested by a loop or match rewrite is an escape.
fn CheckContext::record_local_callbacks(
  self : CheckContext,
  decl : @untyped_cst.CstNode,
) -> Unit {
  guard @cst.child(decl, "params") is Some(params) else { return }
  for attr in @cst.attributes(decl) {
    guard attr.qualifier is None && attr.name == "locals" else { continue }
    let parsed = @attribute.Attribute::new(
      loc=attr.node.loc,
      (attr.name, None, attr.raw_payload),
    )
    let names : Set[String] = Set([])
    let known = match parsed.parsed {
      Some(Apply(_, props)) =>
        for prop in props {
          guard prop is Expr(Ident({ qual: None, name, })) else { break false }
          names.add(name)
        } nobreak {
          true
        }
      _ => false
    }
    for param in @cst.items(params) {
      guard @cst.child(param, "pattern") is Some(pattern) &&
        @cst.normalized_pattern_identifier_name(pattern) is Some(name) &&
        (!known || names.contains(name)) else {
        continue
      }
      self.local_callbacks.add(self.range(pattern).start)
    }
  }
}

///|
async fn CheckContext::can_capture_callback(
  self : CheckContext,
  callee : @untyped_cst.CstNode,
) -> Bool {
  guard !self.local_callbacks.is_empty() else { return true }
  guard (self.symbol_at)(callee) is Some(symbol) else {
    raise Unavailable("The IDE could not resolve the callback binding.")
  }
  guard symbol.kind == "local" else { return true }
  guard (self.binding)(symbol.id) is Some(binding) else {
    raise Unavailable("The IDE could not locate the callback declaration.")
  }
  binding.file != self.file || !self.local_callbacks.contains(binding.start)
}
