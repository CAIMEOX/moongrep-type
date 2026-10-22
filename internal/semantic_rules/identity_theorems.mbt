///|
fn identity_container_arguments(shape : Json, owner : String) -> Array[Json]? {
  guard builtin_type_arguments(shape, owner) is Some(args) else { return None }
  if (owner == "Option" && args.length() == 1) ||
    (owner == "Result" && args.length() == 2) {
    Some(args)
  } else {
    None
  }
}

///|
/// Option/Result identity map preserves the payload, including references to
/// mutable payloads. This law does not apply to copying containers like Array.
fn check_map_identity(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(call) &&
    call.name == "map" &&
    call.args is [callback] &&
    context.method_is(node, owner, ["map"]) &&
    unary_lambda_parts(callback) is Some((binder, body)) &&
    body.kind is Expr_Ident &&
    context.symbol_id(binder) == context.symbol_id(body) else {
    return None
  }
  let receiver_type = context.shape(call.receiver)
  guard identity_container_arguments(receiver_type, owner) is Some(args) &&
    context.shape(node) == receiver_type &&
    unary_callback(context.shape(callback)) is Some((input, output)) &&
    input == args[0] &&
    output == args[0] &&
    context.shape(body) == args[0] else {
    return None
  }
  Some(node.loc)
}

///|
fn check_bind_identity(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(call) &&
    call.name == "bind" &&
    call.args is [callback] &&
    context.method_is(node, owner, ["bind"]) &&
    unary_lambda_parts(callback) is Some((binder, body)) &&
    body.kind is Expr_Apply &&
    positional_args(body) is Some([payload]) &&
    payload.kind is Expr_Ident &&
    context.symbol_id(binder) == context.symbol_id(payload) &&
    context.constructor_is(
      body,
      owner,
      if owner == "Option" {
        "Some"
      } else {
        "Ok"
      },
    ) else {
    return None
  }
  let receiver_type = context.shape(call.receiver)
  guard identity_container_arguments(receiver_type, owner) is Some(args) &&
    context.shape(node) == receiver_type &&
    context.shape(body) == receiver_type &&
    context.shape(payload) == args[0] &&
    unary_callback(context.shape(callback)) is Some((input, output)) &&
    input == args[0] &&
    output == receiver_type else {
    return None
  }
  Some(node.loc)
}

///|
/// Only empty source argument lists qualify. Explicit labelled arguments may
/// have effects even if a future standard-library unwrap ignores them.
fn check_constructor_unwrap(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
  ctor_name : String,
  method_name : String,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(call) &&
    call.name == method_name &&
    call.args.is_empty() &&
    context.method_is(node, owner, [method_name]) else {
    return None
  }
  let receiver = identity_constructor_receiver(call.receiver)
  guard receiver.kind is Expr_Apply &&
    positional_args(receiver) is Some([payload]) &&
    context.constructor_is(receiver, owner, ctor_name) &&
    identity_container_arguments(context.shape(receiver), owner) is Some(args) else {
    return None
  }
  let payload_type = if ctor_name == "Err" { args[1] } else { args[0] }
  guard context.shape(payload) == payload_type &&
    context.shape(node) == payload_type else {
    return None
  }
  Some(node.loc)
}

///|
/// Type annotations carry no runtime evaluation. Accept them around a known
/// constructor so Result's other type argument can be specified explicitly.
fn identity_constructor_receiver(
  node : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode {
  let node = ungroup(node)
  if node.kind is Expr_Constraint && @cst.child(node, "expr") is Some(inner) {
    identity_constructor_receiver(inner)
  } else {
    node
  }
}
