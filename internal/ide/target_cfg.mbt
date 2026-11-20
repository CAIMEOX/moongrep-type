///|
/// Return unknown for features, platforms and unfamiliar expressions. Only a
/// definitely false predicate can exclude an authored declaration.
fn cfg_target(prop : @attribute.Prop, backend : String) -> Bool? {
  match prop {
    Labeled("target", String(name)) => {
      let targets = ["wasm", "wasm-gc", "js", "native", "llvm"]
      guard targets.contains(name) && targets.contains(backend) else {
        return None
      }
      if name != backend &&
        ["native", "llvm"].contains(name) &&
        ["native", "llvm"].contains(backend) {
        return None
      }
      Some(name == backend)
    }
    Expr(Apply({ qual: None, name, }, props)) =>
      match name {
        "not" =>
          match props {
            More(one, tail=Empty) =>
              cfg_target(one, backend).map(value => !value)
            _ => None
          }
        "any" | "all" => {
          let decisive = name == "any"
          let mut unknown = false
          for child in props {
            match cfg_target(child, backend) {
              Some(value) if value == decisive => return Some(decisive)
              None => unknown = true
              _ => ()
            }
          }
          if unknown {
            None
          } else {
            Some(!decisive)
          }
        }
        _ => None
      }
    _ => None
  }
}

///|
fn excluded_by_target(root : @untyped_cst.CstNode, backend : String) -> Bool {
  @cst.attributes(root).any(attr => {
    guard attr.qualifier is None && attr.name == "cfg" else { return false }
    let parsed = @attribute.Attribute::new(
      loc=attr.node.loc,
      (attr.name, None, attr.raw_payload),
    )
    parsed.parsed is Some(Apply(_, More(prop, tail=Empty))) &&
    cfg_target(prop, backend) == Some(false)
  })
}
