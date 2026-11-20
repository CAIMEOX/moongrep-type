///|
fn slice_root(value : @untyped_cst.CstNode) -> (@untyped_cst.CstNode, String?)? {
  match value.kind {
    Expr_Ident => Some((value, None))
    Expr_Field => {
      guard @cst.child(value, "self") is Some(root) &&
        root.kind is Expr_Ident &&
        @cst.raw_child(value, "field").bind(@cst.normalized_name) is Some(field) else {
        return None
      }
      Some((root, Some(field)))
    }
    _ => None
  }
}

///|
async fn check_slice_to_end(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard node.kind is Expr_ArrayGetSlice &&
    @cst.child(node, "self") is Some(receiver) &&
    @cst.child(node, "end") is Some(end) &&
    dot_call(ungroup(end)) is Some(length) &&
    length.name == "length" &&
    length.args.is_empty() &&
    slice_root(receiver) is Some((left, field)) &&
    slice_root(length.receiver) is Some((right, other_field)) &&
    field == other_field &&
    @cst.normalized_expr_identifier_name(left) ==
    @cst.normalized_expr_identifier_name(right) else {
    return None
  }
  // A start expression that replaces a field between the two reads could
  // change which length the original slice uses.
  if @cst.child(node, "start") is Some(start) &&
    !fixed_value(context, ungroup(start)) {
    return None
  }
  guard fixed_value(context, left) &&
    context.symbol_id(left) == context.symbol_id(right) &&
    (
      receiver.kind is Expr_Ident ||
      context.symbol_id(receiver) == context.symbol_id(length.receiver)
    ) &&
    standard_call(context, length, [
      "String", "StringView", "Bytes", "BytesView",
    ])
    is Some([]) else {
    return None
  }
  Some(node.loc)
}

///|
async fn check_builder_stream(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? {
  guard dot_call(node) is Some(call) &&
    call.name == "write_string" &&
    call.receiver.kind is Expr_Ident &&
    call.args is [template] &&
    template.kind is Expr_Interp else {
    return None
  }
  let values = []
  for (_, segment) in @cst.semantic_children(template) {
    match segment.kind {
      InterpSegment_Literal => ()
      InterpSegment_Source => {
        guard @cst.child(segment, "expr") is Some(value) &&
          value.kind is (Expr_Ident | Expr_Constant) else {
          return None
        }
        values.push(value)
      }
      _ => return None
    }
  }
  guard !values.is_empty() &&
    fixed_value(context, call.receiver) &&
    core_arguments(context.shape(call.receiver), "StringBuilder") is Some([]) &&
    (context.symbol_at)(node) is Some(symbol) &&
    symbol.kind == "global" &&
    symbol.identity
    is {
      "kind": "trait_impl",
      "package": "moonbitlang/core/builtin",
      "trait": tr,
      "self_type": owner,
      "name": "write_string",
      ..
    } &&
    builtin_owner_is(tr, "Logger") &&
    builtin_owner_is(owner, "StringBuilder") else {
    return None
  }
  for value in values {
    if !fixed_value(context, value) || !stdlib_scalar(context.shape(value)) {
      return None
    }
  }
  Some(node.loc)
}
