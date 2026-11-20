///|
fn int_atom(node : @untyped_cst.CstNode) -> Bool {
  node.kind is Expr_Ident ||
  (
    node.kind is Expr_Constant &&
    @cst.constant(node)
    is Some(
      {
        kind: Constant_Int
        | Constant_UInt
        | Constant_Int64
        | Constant_UInt64
        | Constant_Byte,
        ..
      },
    )
  )
}

///|
fn same_int_term(
  context : CheckContext,
  one : @untyped_cst.CstNode,
  other : @untyped_cst.CstNode,
) -> Bool {
  @cst.source_text(one, context.text) == @cst.source_text(other, context.text) &&
  (
    int_atom(one) ||
    (
      infix_parts(one) is Some((op, a, b)) &&
      (op == "+" || op == "-") &&
      int_atom(a) &&
      int_atom(b)
    )
  )
}

///|
async fn checked_int_atom(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  copy : @untyped_cst.CstNode,
  ty : Json,
) -> Bool {
  guard context.shape(node) == ty else { return false }
  if node.kind is Expr_Ident {
    (context.symbol_at)(node) is Some(symbol) &&
    symbol.kind == "local" &&
    context.symbol_id(copy) == symbol.id
  } else {
    context.shape(copy) == ty
  }
}

///|
async fn checked_int_term(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  copy : @untyped_cst.CstNode,
  ty : Json,
) -> Bool {
  if int_atom(node) {
    return checked_int_atom(context, node, copy, ty)
  }
  guard infix_parts(node) is Some((op, a, b)) &&
    infix_parts(copy) is Some((_, c, d)) &&
    checked_int_atom(context, a, c, ty) &&
    checked_int_atom(context, b, d, ty) else {
    return false
  }
  if op == "+" {
    context.core_trait_method(node, "Add", "add") is Some(_)
  } else {
    context.core_trait_method(node, "Sub", "sub") is Some(_)
  }
}

///|
async fn check_integer_extremum(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  minimum~ : Bool,
) -> Bool {
  guard node.kind is Expr_If &&
    @cst.child(node, "cond") is Some(cond) &&
    infix_parts(cond) is Some((op, left, right)) &&
    @cst.child(node, "body") is Some(body) else {
    return false
  }
  let comparison = match op {
    "<" => "op_lt"
    "<=" => "op_le"
    ">" => "op_gt"
    ">=" => "op_ge"
    _ => return false
  }
  let (selected, other) = if (op == "<" || op == "<=") == minimum {
    (left, right)
  } else {
    (right, left)
  }
  if @cst.source_text(left, context.text) ==
    @cst.source_text(right, context.text) {
    return false
  }
  let body = ungroup(body)
  let otherwise = @cst.child(node, "else").map(ungroup)
  let choice = if otherwise is Some(fallback) {
    guard same_int_term(context, other, fallback) else { return false }
    body
  } else {
    // An unconditional write is only interchangeable with the conditional
    // update for an actual mutable local, never a field or a container slot.
    guard body.kind is Expr_Assign &&
      @cst.operator_name(body) == Some("=") &&
      other.kind is Expr_Ident &&
      @cst.name_node(body).bind(@cst.normalized_name) ==
      @cst.normalized_expr_identifier_name(other) &&
      @cst.child(body, "rhs") is Some(rhs) else {
      return false
    }
    ungroup(rhs)
  }
  guard same_int_term(context, selected, choice) else { return false }
  let shape = (context.shape_at)(other)
  if shape is Some(known) &&
    !(known is { "kind": "builtin", "name": String(n), .. } &&
    ["Byte", "UInt16", "Int", "UInt", "Int64", "UInt64"].contains(n)) {
    return false
  }
  guard context.core_trait_method(ungroup(cond), "Compare", comparison)
    is Some(witness) else {
    return false
  }
  guard shape is Some({ "kind": "builtin", "name": String(name), .. } as ty) else {
    raise Unavailable(
      "The IDE could not determine the integer type at the comparison.",
    )
  }
  guard context.shape(selected) == ty &&
    checked_int_term(context, selected, choice, ty) else {
    return false
  }
  let owner = match name {
    "Int" => "Int32"
    "UInt" => "UInt32"
    _ => name
  }
  guard (context.exports_method)(
    witness,
    "moonbitlang/core/builtin",
    owner,
    if minimum {
      "min"
    } else {
      "max"
    },
    2,
  ) else {
    return false
  }
  if otherwise is Some(fallback) {
    checked_int_term(context, other, fallback, ty)
  } else {
    let id = context.symbol_id(other)
    context.symbol_id(body) == id &&
    (context.binding)(id) is Some(loc) &&
    context.binders.get(loc) == Some(true)
  }
}
