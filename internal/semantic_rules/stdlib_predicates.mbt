///|
fn loop_test_and_exit(
  body : @untyped_cst.CstNode,
  all_values : Bool,
) -> (@untyped_cst.CstNode, @untyped_cst.CstNode)? {
  let body = ungroup(body)
  guard @cst.child(body, "cond") is Some(cond) else { return None }
  let (predicate, branch) = match body.kind {
    Expr_If => {
      guard @cst.child(body, "else") is None &&
        @cst.child(body, "body") is Some(branch) else {
        return None
      }
      let condition = ungroup(cond)
      if all_values {
        guard condition.kind is Expr_Unary &&
          @cst.operator_name(condition) == Some("!") &&
          @cst.child(condition, "expr") is Some(pred) else {
          return None
        }
        (pred, branch)
      } else {
        (condition, branch)
      }
    }
    Expr_Guard if all_values => {
      guard @cst.child(body, "body") is None &&
        @cst.child(body, "else") is Some(branch) &&
        @cst.raw_child(body, "exclamation").bind(@cst.bool_payload) !=
        Some(true) else {
        return None
      }
      (cond, branch)
    }
    _ => return None
  }
  let exit = ungroup(branch)
  guard exit.kind is Expr_Break &&
    @cst.child(exit, "label") is None &&
    @cst.child(exit, "expr") is Some(result) else {
    return None
  }
  Some((ungroup(predicate), ungroup(result)))
}

///|
async fn short_circuit_loop(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  check : @rule_model.StdlibCheck,
) -> Bool {
  guard node.kind is Expr_ForEach &&
    @cst.child(node, "pattern") is Some(binder) &&
    binder.kind is Pattern_Var &&
    @cst.child(node, "expr") is Some(source) &&
    @cst.child(node, "body") is Some(body) &&
    @cst.child(node, "else") is Some(other) else {
    return false
  }
  for label in ["init", "continue", "where", "label"] {
    if @cst.child(node, label) is Some(_) {
      return false
    }
  }
  guard loop_test_and_exit(body, check is LoopAll) is Some((predicate, hit)) else {
    return false
  }
  let miss = ungroup(other)
  if check is LoopFindFirst {
    guard hit.kind is Expr_Apply &&
      positional_args(hit) is Some([arg]) &&
      arg.kind is Expr_Ident &&
      miss.kind is Expr_Constr else {
      return false
    }
  } else {
    let (yes, no) = if check is LoopAll {
      ("false", "true")
    } else {
      ("true", "false")
    }
    guard hit.kind is Expr_Constant &&
      miss.kind is Expr_Constant &&
      @cst.source_text(hit, context.text) == yes &&
      @cst.source_text(miss, context.text) == no else {
      return false
    }
  }
  let source_shape = context.shape(source)
  let types = if check is LoopFindFirst {
    ["Iter"]
  } else {
    ["Array", "ArrayView", "ReadOnlyArray", "FixedArray", "Iter"]
  }
  let element_type = for owner in types {
    if core_arguments(source_shape, owner) is Some([element]) {
      break Some(element)
    }
  } nobreak {
    None
  }
  guard element_type is Some(element) else { return false }
  if check is LoopFindFirst {
    guard constructor_argument(context, hit, "Option", "Some") is Some(arg) &&
      same_payload(context, binder, arg) &&
      context.constructor_is(miss, "Option", "None") else {
      return false
    }
  }
  if predicate.kind is Expr_Apply {
    applied_payload(context, predicate, binder, element) ==
    Some({ "kind": "builtin", "name": "Bool" })
  } else {
    infix_parts(predicate) is Some((op, _, _)) &&
    ["==", "!=", "<", "<=", ">", ">="].contains(op) &&
    mapped_payload(context, predicate, binder, element)
  }
}

///|
/// Normalize both spellings of an inclusive bound to (bound literal, identifier, lower?).
fn ascii_bound(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> (String, @untyped_cst.CstNode, Bool)? {
  guard infix_parts(node) is Some((op, left, right)) &&
    (op == "<=" || op == ">=") else {
    return None
  }
  let (literal, variable, lower) = if left.kind is Expr_Constant &&
    right.kind is Expr_Ident {
    (left, right, op == "<=")
  } else if right.kind is Expr_Constant && left.kind is Expr_Ident {
    (right, left, op == ">=")
  } else {
    return None
  }
  Some((@cst.source_text(literal, context.text), variable, lower))
}

///|
async fn ascii_interval(
  context : CheckContext,
  node : @untyped_cst.CstNode,
  low : String,
  high : String,
) -> Bool {
  let receiver = if node.kind is Expr_Is {
    guard @cst.child(node, "expr") is Some(value) &&
      @cst.child(node, "pattern") is Some(pat) else {
      return false
    }
    let range = if pat.kind is Pattern_Tuple &&
      @cst.raw_child(pat, "pattern_group") is Some(_) {
      guard @cst.child(pat, "body") is Some(group) &&
        @cst.items(group) is [item] else {
        return false
      }
      item
    } else {
      pat
    }
    guard range.kind is Pattern_Range &&
      @cst.raw_child(range, "range_kind")
      is Some({ kind: RangeKind_Inclusive, .. }) &&
      @cst.child(range, "lhs") is Some(lhs) &&
      @cst.child(range, "rhs") is Some(rhs) &&
      @cst.source_text(lhs, context.text) == low &&
      @cst.source_text(rhs, context.text) == high else {
      return false
    }
    value
  } else {
    guard infix_parts(node) is Some(("&&", left, right)) &&
      ascii_bound(context, left) is Some((a, x, from)) &&
      ascii_bound(context, right) is Some((b, y, to)) &&
      from != to &&
      (if from { a == low && b == high } else { a == high && b == low }) &&
      context.stable_identifier(x) &&
      context.symbol_id(x) == context.symbol_id(y) else {
      return false
    }
    x
  }
  context.shape(receiver) == ({ "kind": "builtin", "name": "Char" } : Json)
}
