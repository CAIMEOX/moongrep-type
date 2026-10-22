///|
fn option_element(shape : Json) -> Json? {
  match shape {
    {
      "kind": "named",
      "path": { "kind": "builtin", "name": "Option", .. },
      "arguments": [element],
      ..
    } => Some(element)
    _ => None
  }
}

///|
fn CheckContext::option_constructor(
  self : CheckContext,
  node : @untyped_cst.CstNode,
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
  let fact = self.expression(node)
  guard fact.symbol_id is Some(id) &&
    self.source.index().symbol(id) is Some(symbol) else {
    return false
  }
  symbol.kind == "constructor" &&
  symbol.name == name &&
  symbol.identity
  is {
    "kind": "constructor",
    "owner_type": { "kind": "builtin", "name": "Option", .. },
    ..
  }
}

///|
fn option_branches(
  context : CheckContext,
  some : @untyped_cst.CstNode,
  none : @untyped_cst.CstNode,
) -> Bool raise {
  let some = ungroup(some)
  let none = ungroup(none)
  some.kind is Expr_Apply &&
  positional_args(some) is Some([_]) &&
  none.kind is Expr_Constr &&
  context.option_constructor(some, "Some") &&
  context.option_constructor(none, "None")
}

///|
/// A partial Some(constant) match can fail at runtime; turning it into a guard
/// would silently filter that failure. Only exhaustive payload binders qualify.
fn exhaustive_option_pattern(
  pattern : @untyped_cst.CstNode,
  name : String,
) -> Bool {
  if !(pattern.kind is Pattern_Constr) ||
    @cst.normalized_name(pattern) != Some(name) {
    return false
  }
  if name == "None" {
    return @cst.child(pattern, "params") is None
  }
  guard @cst.child(pattern, "params") is Some(params) &&
    @cst.items(params) is [payload] else {
    return false
  }
  payload.kind is (Pattern_Var | Pattern_Any)
}

///|
fn simple_filter_map_body(
  context : CheckContext,
  body : @untyped_cst.CstNode,
) -> Bool raise {
  let body = ungroup(body)
  if body.kind is Expr_If {
    guard @cst.child(body, "body") is Some(yes) &&
      @cst.child(body, "else") is Some(no) else {
      return false
    }
    return option_branches(context, yes, no)
  }
  guard body.kind is Expr_Match &&
    @cst.child(body, "expr") is Some(scrutinee) &&
    option_element(context.shape(scrutinee)) is Some(_) else {
    return false
  }
  let cases : Array[@untyped_cst.CstNode] = []
  for node in @cst.raw_children(body, "case") {
    if node.kind is Case_MatchCase {
      cases.push(node)
    } else {
      cases.append(@cst.raw_children(node, "case"))
    }
  }
  guard cases.length() == 2 else { return false }
  let mut some_body : @untyped_cst.CstNode? = None
  let mut none_body : @untyped_cst.CstNode? = None
  for case in cases {
    guard @cst.child(case, "cond") is None &&
      @cst.child(case, "pattern") is Some(pattern) &&
      pattern.kind is Pattern_Constr &&
      @cst.child(case, "body") is Some(result) else {
      return false
    }
    match @cst.normalized_name(pattern) {
      Some("Some") if exhaustive_option_pattern(pattern, "Some") =>
        some_body = Some(result)
      Some("None") if exhaustive_option_pattern(pattern, "None") =>
        none_body = Some(result)
      _ => return false
    }
  }
  match (some_body, none_body) {
    (Some(some), Some(none)) => option_branches(context, some, none)
    _ => false
  }
}

///|
fn check_filter_map(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(call) &&
    call.name == "filter_map" &&
    call.args is [callback] &&
    callback.kind is Expr_Function &&
    @cst.child(callback, "body") is Some(body) &&
    context.method_is(node, "Array", ["filter_map"]) &&
    context.simple_callback(callback) is Some((input, output)) &&
    array_element(context.shape(call.receiver)) == Some(input) &&
    option_element(output) is Some(element) &&
    array_element(context.shape(node)) == Some(element) &&
    simple_filter_map_body(context, body) else {
    return None
  }
  Some(node.loc)
}
