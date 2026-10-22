///|
/// The mapped member and, for Result, the member left untouched by this method.
fn optional_map_members(
  shape : Json,
  owner : String,
  method_name : String,
) -> (Json, Json?)? {
  match (owner, method_name, builtin_type_arguments(shape, owner)) {
    ("Option", "map", Some([value])) => Some((value, None))
    ("Result", "map", Some([value, error])) => Some((value, Some(error)))
    ("Result", "map_err", Some([value, error])) => Some((error, Some(value)))
    _ => None
  }
}

///|
fn optional_map_flow(
  owner : String,
  method_name : String,
  receiver : Json,
  intermediate : Json,
  result : Json,
  first : Json,
  second : Json,
) -> Bool {
  guard optional_map_members(receiver, owner, method_name) is Some((a, carried)) &&
    optional_map_members(intermediate, owner, method_name)
    is Some((b, carried_b)) &&
    optional_map_members(result, owner, method_name) is Some((c, carried_c)) &&
    unary_callback(first) == Some((a, b)) &&
    unary_callback(second) == Some((b, c)) else {
    return false
  }
  carried == carried_b && carried == carried_c
}

///|
/// Zero-or-one values preserve callback effects and checked errors in order.
/// Stable callback expressions prevent moving factories or mutable reads.
fn check_optional_map_fusion(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
  method_name : String,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(outer) &&
    outer.name == method_name &&
    outer.args is [second] &&
    dot_call(outer.receiver) is Some(inner) &&
    inner.name == method_name &&
    inner.args is [first] &&
    context.method_is(outer.node, owner, [method_name]) &&
    context.method_is(inner.node, owner, [method_name]) &&
    context.stable_callback(first) &&
    context.stable_callback(second) &&
    optional_map_flow(
      owner,
      method_name,
      context.shape(inner.receiver),
      context.shape(inner.node),
      context.shape(outer.node),
      context.shape(first),
      context.shape(second),
    ) else {
    return None
  }
  Some(node.loc)
}

///|
fn fusion_lambda_parameter(
  node : @untyped_cst.CstNode,
) -> @untyped_cst.CstNode? {
  unary_lambda_parts(node).map(parts => parts.0)
}

///|
/// A return inside the wrapped expression returns Option/Result from the
/// enclosing callback. Removing the wrapper would change that callback's type.
/// Returns in nested functions keep their own boundary and do not interfere.
/// In the original CST a local function contains only its declaration; later
/// statements are siblings and are still visited after skipping that body.
fn fusion_payload_keeps_return_boundary(node : @untyped_cst.CstNode) -> Bool {
  let pending = [node]
  while pending.pop() is Some(current) {
    match current.kind {
      Expr_Return => return false
      Expr_Function | Expr_LetFn => continue
      Binding_LetRec if @cst.child(current, "params") is Some(_) => continue
      _ => ()
    }
    for (_, child) in current.children {
      pending.push(child)
    }
  }
  true
}

///|
fn check_bind_map(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
) -> @basic.Location? raise {
  let ctor_name = if owner == "Option" { "Some" } else { "Ok" }
  guard dot_call(node) is Some(call) &&
    call.name == "bind" &&
    call.args is [callback] &&
    callback.kind is Expr_Function &&
    @cst.child(callback, "body") is Some(body) &&
    context.method_is(node, owner, ["bind"]) &&
    unary_callback(context.shape(callback)) is Some((input, output)) &&
    optional_map_members(context.shape(call.receiver), owner, "map")
    is Some((a, carried)) &&
    optional_map_members(context.shape(node), owner, "map")
    is Some((b, carried_b)) &&
    optional_map_members(output, owner, "map") == Some((b, carried_b)) &&
    input == a &&
    carried == carried_b else {
    return None
  }
  let wrapped = ungroup(body)
  guard wrapped.kind is Expr_Apply &&
    positional_args(wrapped) is Some([payload]) &&
    fusion_payload_keeps_return_boundary(payload) &&
    context.constructor_is(wrapped, owner, ctor_name) &&
    context.shape(wrapped) == output else {
    return None
  }
  // Some/Ok's standard constructor signature and the checked wrapper type
  // determine the payload type. Braced payloads may lack an exact typed range;
  // they do not need a second association or an enclosing-range fallback.
  // The more specific right-unit rule owns x => Some(x) / x => Ok(x).
  let payload = ungroup(payload)
  if payload.kind is Expr_Ident &&
    fusion_lambda_parameter(callback) is Some(parameter) &&
    context.symbol_id(payload) == context.symbol_id(parameter) {
    return None
  }
  Some(node.loc)
}

///|
fn check_result_map_flatten(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(flatten) &&
    flatten.name == "flatten" &&
    flatten.args.is_empty() &&
    dot_call(flatten.receiver) is Some(map) &&
    map.name == "map" &&
    map.args is [callback] &&
    context.method_is(flatten.node, "Result", ["flatten"]) &&
    context.method_is(map.node, "Result", ["map"]) &&
    builtin_type_arguments(context.shape(map.receiver), "Result")
    is Some([a, error]) &&
    builtin_type_arguments(context.shape(map.node), "Result")
    is Some([nested, outer_error]) &&
    builtin_type_arguments(nested, "Result") is Some([b, inner_error]) &&
    builtin_type_arguments(context.shape(node), "Result") == Some([b, error]) &&
    unary_callback(context.shape(callback)) == Some((a, nested)) &&
    error == outer_error &&
    error == inner_error else {
    return None
  }
  Some(node.loc)
}

///|
fn check_option_filter_fusion(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(outer) &&
    outer.name == "filter" &&
    outer.args is [second] &&
    dot_call(outer.receiver) is Some(inner) &&
    inner.name == "filter" &&
    inner.args is [first] &&
    context.method_is(outer.node, "Option", ["filter"]) &&
    context.method_is(inner.node, "Option", ["filter"]) &&
    context.stable_callback(first) &&
    context.stable_callback(second) &&
    builtin_type_arguments(context.shape(inner.receiver), "Option")
    is Some([element]) &&
    builtin_type_arguments(context.shape(inner.node), "Option") ==
    Some([element]) &&
    builtin_type_arguments(context.shape(node), "Option") == Some([element]) else {
    return None
  }
  let bool_type : Json = { "kind": "builtin", "name": "Bool" }
  guard unary_callback(context.shape(first)) == Some((element, bool_type)) &&
    unary_callback(context.shape(second)) == Some((element, bool_type)) else {
    return None
  }
  Some(node.loc)
}

///|
fn fusion_nullary_callback(shape : Json) -> Json? {
  match shape {
    {
      "kind": "function",
      "parameters": [],
      "return_type": output,
      "async": "sync",
      "error": { "kind": "none" | "typed" | "parameter", .. },
      ..
    } => Some(output)
    _ => None
  }
}

///|
fn check_option_map_default(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(default_call) &&
    default_call.name == "unwrap_or_else" &&
    default_call.args is [fallback] &&
    dot_call(default_call.receiver) is Some(map) &&
    map.name == "map" &&
    map.args is [callback] &&
    context.method_is(default_call.node, "Option", ["unwrap_or_else"]) &&
    context.method_is(map.node, "Option", ["map"]) &&
    context.stable_callback(callback) &&
    context.stable_callback(fallback) &&
    builtin_type_arguments(context.shape(map.receiver), "Option") is Some([a]) &&
    builtin_type_arguments(context.shape(map.node), "Option") is Some([b]) &&
    context.shape(node) == b &&
    unary_callback(context.shape(callback)) == Some((a, b)) &&
    fusion_nullary_callback(context.shape(fallback)) == Some(b) else {
    return None
  }
  Some(node.loc)
}
