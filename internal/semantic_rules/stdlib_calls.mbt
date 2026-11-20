///|
/// A receiver must have the core type itself. An imported namesake or a method
/// reached through an implicit conversion does not establish the target API.
fn core_arguments(shape : Json, owner : String) -> Array[Json]? {
  match shape {
    { "kind": "builtin", "name": String(name), .. } if owner == name => Some([])
    {
      "kind": "named",
      "path": path,
      "named_kind": "Normal",
      "arguments": Array(args),
      ..
    } if builtin_owner_is(path, owner) => Some(args)
    _ => None
  }
}

///|
async fn standard_call(
  context : CheckContext,
  call : DotCall,
  owners : Array[String],
) -> Array[Json]? {
  guard (context.symbol_at)(call.node) is Some(symbol) else {
    raise Unavailable("The IDE could not resolve the method.")
  }
  guard symbol.kind == "global" &&
    symbol.identity
    is { "kind": "method", "self_type": owner, "name": String(name), .. } &&
    name == call.name else {
    return None
  }
  for name in owners {
    if builtin_owner_is(owner, name) {
      return core_arguments(context.shape(call.receiver), name)
    }
  }
  None
}

///|
fn stdlib_scalar(shape : Json) -> Bool {
  guard shape is { "kind": "builtin", "name": String(name), .. } else {
    return false
  }
  [
    "Bool", "Char", "Byte", "Int", "UInt", "Int16", "UInt16", "Int64", "UInt64",
    "Float", "Double", "String", "Bytes",
  ].contains(name)
}

///|
/// Moving this value across a lookup (or out of a conditional branch) must
/// neither run user code nor change the value read from a mutable binding.
async fn fixed_value(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool {
  match node.kind {
    Expr_Constant => stdlib_scalar(context.shape(node))
    Expr_Ident => {
      guard (context.symbol_at)(node) is Some(symbol) &&
        symbol.kind == "local" &&
        (context.binding)(symbol.id) is Some(loc) else {
        return false
      }
      context.binders.get(loc) == Some(false)
    }
    _ => false
  }
}

///|
fn infix_parts(
  node : @untyped_cst.CstNode,
) -> (String, @untyped_cst.CstNode, @untyped_cst.CstNode)? {
  let node = ungroup(node)
  guard node.kind is Expr_Infix &&
    @cst.operator_name(node) is Some(op) &&
    @cst.child(node, "lhs") is Some(left) &&
    @cst.child(node, "rhs") is Some(right) else {
    return None
  }
  Some((op, ungroup(left), ungroup(right)))
}

///|
fn zero_literal(context : CheckContext, node : @untyped_cst.CstNode) -> Bool {
  node.kind is Expr_Constant && @cst.source_text(node, context.text) == "0"
}

///|
async fn length_test(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool {
  guard infix_parts(node) is Some((op, lhs, rhs)) else { return false }
  let receiver_call = if ["==", "!=", ">"].contains(op) &&
    zero_literal(context, rhs) {
    lhs
  } else if ["==", "!=", "<"].contains(op) && zero_literal(context, lhs) {
    rhs
  } else {
    return false
  }
  guard dot_call(receiver_call) is Some(call) &&
    call.name == "length" &&
    call.args.is_empty() else {
    return false
  }
  standard_call(context, call, [
    "Array", "ArrayView", "ReadOnlyArray", "FixedArray", "Map", "String", "StringView",
    "Bytes", "BytesView",
  ])
  is Some(_)
}

///|
async fn presence_test(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  check : @rule_model.StdlibCheck,
) -> Bool {
  let (inner, pattern) = if node.kind is Expr_Is {
    guard @cst.child(node, "expr") is Some(inner) &&
      @cst.child(node, "pattern") is Some(pat) &&
      pat.kind is Pattern_Constr else {
      return false
    }
    if @cst.child(pat, "params") is Some(ps) &&
      !(@cst.items(ps) is [{ kind: Pattern_Any, .. }]) {
      return false
    }
    (inner, Some(pat))
  } else {
    guard dot_call(node) is Some(outer) &&
      ["is_some", "is_none"].contains(outer.name) &&
      outer.args.is_empty() else {
      return false
    }
    (outer.receiver, None)
  }
  guard dot_call(ungroup(inner)) is Some(call) && call.args is [arg] else {
    return false
  }
  let (method_name, owners) = match check {
    StringFindContains => ("find", ["String", "StringView"])
    StringStripPrefixTest => ("strip_prefix", ["String", "StringView"])
    StringStripSuffixTest => ("strip_suffix", ["String", "StringView"])
    MapGetContains => ("get", ["Map"])
    ArraySearchContains =>
      ("search", ["Array", "ArrayView", "ReadOnlyArray", "FixedArray"])
    ArraySearchByAny => ("search_by", ["Array", "ArrayView", "ReadOnlyArray"])
    _ => return false
  }
  guard call.name == method_name &&
    standard_call(context, call, owners) is Some(args) else {
    return false
  }
  if pattern is Some(pat) {
    guard option_presence_pattern(context, pat) else { return false }
  } else {
    guard context.method_is(node, "Option", ["is_some", "is_none"]) else {
      return false
    }
  }
  guard option_element(context.shape(call.node)) is Some(value) else {
    return false
  }
  match check {
    MapGetContains => args is [_, v] && value == v
    StringFindContains => value == ({ "kind": "builtin", "name": "Int" } : Json)
    StringStripPrefixTest | StringStripSuffixTest =>
      core_arguments(value, "StringView") is Some([])
    ArraySearchContains =>
      args is [element] &&
      stdlib_scalar(element) &&
      value == ({ "kind": "builtin", "name": "Int" } : Json)
    ArraySearchByAny =>
      args is [element] &&
      value == ({ "kind": "builtin", "name": "Int" } : Json) &&
      unary_callback(context.shape(arg)) is Some((input, output)) &&
      input == element &&
      output == ({ "kind": "builtin", "name": "Bool" } : Json)
    _ => false
  }
}

///|
async fn iter_drop_next(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool {
  guard dot_call(node) is Some(next) &&
    next.name == "next" &&
    next.args.is_empty() &&
    dot_call(next.receiver) is Some(drop) &&
    drop.name == "drop" &&
    drop.args is [arg] &&
    arg.kind is Expr_Constant &&
    @cst.constant(arg) is Some({ kind: Constant_Int, .. }) else {
    return false
  }
  let spelling = @cst.source_text(arg, context.text)
  guard spelling.iter().all(c => c >= '0' && c <= '9') else { return false }
  let offset = @string.parse_int(spelling) catch { _ => return false }
  guard offset >= 0 &&
    standard_call(context, drop, ["Iter"]) is Some([element]) &&
    context.method_is(node, "Iter", ["next"]) else {
    return false
  }
  option_element(context.shape(node)) == Some(element)
}

///|
async fn map_get_default(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool {
  guard dot_call(node) is Some(outer) &&
    outer.name == "unwrap_or" &&
    outer.args is [fallback] &&
    dot_call(outer.receiver) is Some(get) &&
    get.name == "get" &&
    get.args.length() == 1 &&
    fallback.kind is (Expr_Constant | Expr_Ident) &&
    standard_call(context, get, ["Map"]) is Some([_, value]) &&
    context.method_is(node, "Option", ["unwrap_or"]) &&
    fixed_value(context, fallback) else {
    return false
  }
  option_element(context.shape(get.node)) == Some(value) &&
  context.shape(fallback) == value &&
  context.shape(node) == value
}

///|
async fn check_standard_library(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  check : @rule_model.StdlibCheck,
) -> @basic.Location? {
  let matches = match check {
    CollectionIsEmpty => length_test(context, node)
    StringFindContains
    | StringStripPrefixTest
    | StringStripSuffixTest
    | MapGetContains
    | ArraySearchContains
    | ArraySearchByAny => presence_test(context, node, check)
    IterDropNext => iter_drop_next(context, node)
    MapGetDefault => map_get_default(context, node)
  }
  if matches {
    Some(node.loc)
  } else {
    None
  }
}
