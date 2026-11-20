///|
priv struct StdlibArm {
  pattern : @untyped_cst.CstNode
  payload : @untyped_cst.CstNode?
  body : @untyped_cst.CstNode
}

///|
fn stdlib_arm(node : @untyped_cst.CstNode) -> StdlibArm? {
  guard @cst.child(node, "cond") is None &&
    @cst.child(node, "pattern") is Some(pattern) &&
    pattern.kind is Pattern_Constr &&
    @cst.child(node, "body") is Some(body) else {
    return None
  }
  let payload = if @cst.child(pattern, "params") is Some(params) {
    guard @cst.items(params) is [p] && p.kind is (Pattern_Var | Pattern_Any) else {
      return None
    }
    Some(p)
  } else {
    None
  }
  Some({ pattern, payload, body: ungroup(body), })
}

///|
async fn same_payload(
  context : CheckContext,
  binder : @untyped_cst.CstNode,
  value : @untyped_cst.CstNode,
) -> Bool {
  binder.kind is Pattern_Var &&
  value.kind is Expr_Ident &&
  context.symbol_id(binder) == context.symbol_id(value)
}

///|
async fn constructor_argument(
  context : CheckContext,
  value : @untyped_cst.CstNode,
  owner : String,
  name : String,
) -> @untyped_cst.CstNode? {
  guard value.kind is Expr_Apply &&
    positional_args(value) is Some([arg]) &&
    context.constructor_is(value, owner, name) else {
    return None
  }
  Some(ungroup(arg))
}

///|
async fn forwarded_arm(
  context : CheckContext,
  arm : StdlibArm,
  owner : String,
  name : String,
) -> Bool {
  if name == "None" {
    arm.payload is None && context.constructor_is(arm.body, owner, name)
  } else {
    arm.payload is Some(binder) &&
    constructor_argument(context, arm.body, owner, name) is Some(arg) &&
    same_payload(context, binder, arg)
  }
}

///|
async fn applied_payload(
  context : CheckContext,
  expr : @untyped_cst.CstNode,
  binder : @untyped_cst.CstNode,
  input : Json,
) -> Json? {
  guard expr.kind is Expr_Apply &&
    @cst.child(expr, "func") is Some(callee) &&
    callee.kind is Expr_Ident &&
    positional_args(expr) is Some([arg]) &&
    same_payload(context, binder, arg) &&
    unary_callback(context.shape(callee)) is Some((parameter, output)) &&
    parameter == input else {
    return None
  }
  Some(output)
}

///|
/// The suggested closure keeps calls and arithmetic inside the selected arm.
/// Restrict its body to a named synchronous call or a primitive binary expression.
async fn mapped_payload(
  context : CheckContext,
  expr : @untyped_cst.CstNode,
  binder : @untyped_cst.CstNode,
  input : Json,
) -> Bool {
  if expr.kind is Expr_Apply {
    return applied_payload(context, expr, binder, input) is Some(_)
  }
  guard stdlib_scalar(input) &&
    infix_parts(expr) is Some((op, left, right)) &&
    ["+", "-", "*", "==", "!=", "<", "<=", ">", ">="].contains(op) else {
    return false
  }
  (right.kind is Expr_Constant && same_payload(context, binder, left)) ||
  (left.kind is Expr_Constant && same_payload(context, binder, right))
}

///|
async fn checked_fallback(
  context : CheckContext,
  expr : @untyped_cst.CstNode,
  input : Json,
  lazy_default : Bool,
) -> Bool {
  if !lazy_default {
    return context.shape(expr) == input
  }
  guard expr.kind is Expr_Apply &&
    positional_args(expr) is Some([]) &&
    @cst.child(expr, "func") is Some(callee) &&
    callee.kind is Expr_Ident else {
    return false
  }
  context.shape(callee)
  is {
    "kind": "function",
    "parameters": [],
    "return_type": output,
    "async": "sync",
    ..
  } &&
  output == input
}

///|
async fn standard_match(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  check : @rule_model.StdlibCheck,
  owner : String,
) -> Bool {
  guard node.kind is Expr_Match &&
    @cst.child(node, "expr") is Some(source) &&
    match_cases(node) is [first, second] &&
    stdlib_arm(first) is Some(a) &&
    stdlib_arm(second) is Some(b) else {
    return false
  }
  let (success, failure) = if owner == "Option" {
    ("Some", "None")
  } else {
    ("Ok", "Err")
  }
  let (selected, other) = if check is MatchResultMapErr {
    (failure, success)
  } else {
    (success, failure)
  }
  let (hit, miss) = if @cst.normalized_name(a.pattern) == Some(selected) {
    (a, b)
  } else {
    (b, a)
  }
  if check is (MatchOptionUnwrapOr | MatchResultUnwrapOr) &&
    !fixed_value(context, miss.body) {
    return false
  }
  guard @cst.normalized_name(hit.pattern) == Some(selected) &&
    @cst.normalized_name(miss.pattern) == Some(other) &&
    hit.payload is Some(binder) &&
    binder.kind is Pattern_Var &&
    identity_container_arguments(context.shape(source), owner) is Some(args) &&
    context.constructor_is(hit.pattern, owner, selected) &&
    context.constructor_is(miss.pattern, owner, other) else {
    return false
  }
  let input = if check is MatchResultMapErr { args[1] } else { args[0] }
  match check {
    MatchOptionMap | MatchResultMap | MatchResultMapErr =>
      constructor_argument(context, hit.body, owner, selected) is Some(expr) &&
      mapped_payload(context, expr, binder, input) &&
      forwarded_arm(context, miss, owner, other)
    MatchOptionBind | MatchResultBind => {
      guard applied_payload(context, hit.body, binder, input) is Some(out) &&
        identity_container_arguments(out, owner) is Some(result_args) &&
        (owner == "Option" || result_args[1] == args[1]) else {
        return false
      }
      forwarded_arm(context, miss, owner, other)
    }
    MatchResultToOption =>
      miss.payload is Some({ kind: Pattern_Any, .. }) &&
      context.constructor_is(miss.body, "Option", "None") &&
      constructor_argument(context, hit.body, "Option", "Some") is Some(arg) &&
      same_payload(context, binder, arg)
    MatchOptionUnwrapOr
    | MatchResultUnwrapOr
    | MatchOptionUnwrapOrElse
    | MatchResultUnwrapOrElse =>
      (miss.payload is None || miss.payload is Some({ kind: Pattern_Any, .. })) &&
      same_payload(context, binder, hit.body) &&
      checked_fallback(
        context,
        miss.body,
        input,
        check is (MatchOptionUnwrapOrElse | MatchResultUnwrapOrElse),
      )
    _ => false
  }
}
