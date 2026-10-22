///|
priv struct DotCall {
  node : @untyped_cst.CstNode
  receiver : @untyped_cst.CstNode
  name : String
  args : Array[@untyped_cst.CstNode]
}

///|
fn positional_args(node : @untyped_cst.CstNode) -> Array[@untyped_cst.CstNode]? {
  guard @cst.child(node, "arg") is Some(list) else { return None }
  let args = []
  for argument in @cst.items(list) {
    guard argument.kind is Argument_Positional &&
      @cst.argument_value(argument) is Some(value) else {
      return None
    }
    args.push(value)
  }
  Some(args)
}

///|
fn dot_call(node : @untyped_cst.CstNode) -> DotCall? {
  guard node.kind is Expr_DotApply &&
    @cst.child(node, "self") is Some(receiver) &&
    @cst.child(node, "field").bind(@cst.normalized_name) is Some(name) &&
    positional_args(node) is Some(args) else {
    return None
  }
  if @cst.raw_child(node, "return_self").bind(@cst.bool_payload) == Some(true) {
    return None
  }
  Some({ node, receiver, name, args, })
}

///|
fn ungroup(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  match node.kind {
    Expr_Group =>
      match @cst.child(node, "body") {
        Some(body) => ungroup(body)
        None => node
      }
    Expr_Block | Expr_Sequence =>
      match @cst.sequence_items(node) {
        [item] => ungroup(item)
        _ => node
      }
    _ => node
  }
}

///|
fn candidate_items(
  candidate : @cst.ExprMatchCandidate,
) -> Array[@untyped_cst.CstNode] {
  match candidate {
    Sequence(items) => items.to_owned()
    Direct(node) if node.kind is (Expr_Block | Expr_Sequence) =>
      @cst.sequence_items(node)
    Direct(node) => [node]
  }
}

///|
fn statement_value(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  if node.kind is (Expr_Let | Expr_LetMut) &&
    @cst.child(node, "expr") is Some(value) {
    ungroup(value)
  } else {
    ungroup(node)
  }
}

///|
fn statement_call_syntax(
  statement : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode? {
  let value = statement_value(statement)
  if value.kind is Expr_DotApply {
    return Some(value)
  }
  if value.kind is Expr_Apply &&
    positional_args(value) is Some([arg]) &&
    arg.kind is Expr_DotApply {
    Some(arg)
  } else {
    None
  }
}

///|
fn CheckContext::statement_call(
  self : CheckContext,
  statement : @untyped_cst.CstNode,
) -> DotCall? raise {
  let value = statement_value(statement)
  if dot_call(value) is Some(call) {
    return Some(call)
  }
  if value.kind is Expr_Apply &&
    positional_args(value) is Some([arg]) &&
    self.builtin_value_call(value, "ignore") {
    dot_call(arg)
  } else {
    None
  }
}

///|
/// A literal one-argument lambda. Do not erase a callback expression that may
/// run a factory, or a lambda with extra statements before its result.
fn unary_lambda_parts(
  node : @untyped_cst.CstNode,
) -> (@untyped_cst.CstNode, @untyped_cst.CstNode)? {
  guard node.kind is Expr_Function &&
    @cst.child(node, "params") is Some(params) &&
    @cst.items(params) is [parameter] &&
    parameter.kind is Parameter_Positional &&
    @cst.child(parameter, "pattern") is Some(pattern) &&
    pattern.kind is Pattern_Var &&
    @cst.raw_child(pattern, "semantic_name") is Some(binder) &&
    binder.kind is Name_Binder &&
    @cst.child(node, "body") is Some(body) else {
    return None
  }
  Some((binder, ungroup(body)))
}
