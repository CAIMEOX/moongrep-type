///|
fn check_array_builder(
  context : CheckContext,
  items : Array[@untyped_cst.CstNode],
) -> @basic.Location? raise {
  guard items is [binding, iteration, result] &&
    binding.kind is Expr_Let &&
    @cst.child(binding, "expr") is Some(initializer) &&
    initializer.kind is Expr_Array &&
    @cst.child(binding, "pattern") is Some(binder) &&
    binder.kind is Pattern_Var &&
    iteration.kind is Expr_ForEach &&
    result.kind is Expr_Ident &&
    @cst.child(iteration, "body") is Some(body) else {
    return None
  }
  for label in ["init", "continue", "else", "where", "label"] {
    if @cst.child(iteration, label) is Some(_) {
      return None
    }
  }
  guard @cst.child(initializer, "body") is Some(elements) &&
    @cst.items(elements).is_empty() else {
    return None
  }
  let body = ungroup(body)
  let pushed = if body.kind is Expr_If {
    guard @cst.child(body, "body") is Some(then_body) &&
      @cst.child(body, "cond") is Some(condition) &&
      no_abrupt_control(condition) else {
      return None
    }
    if @cst.child(body, "else") is Some(other) &&
      !(ungroup(other).kind is Expr_Unit) {
      return None
    }
    ungroup(then_body)
  } else {
    body
  }
  guard dot_call(pushed) is Some(push) &&
    push.name == "push" &&
    push.args is [value] &&
    push.receiver.kind is Expr_Ident &&
    no_abrupt_control(value) else {
    return None
  }
  guard context.method_is(push.node, "Array", ["push"]) &&
    array_element(context.shape(initializer)) is Some(element) &&
    array_element(context.shape(result)) == Some(element) &&
    context.shape(value) == element else {
    return None
  }
  let id = context.symbol_id(binder)
  guard context.symbol_id(push.receiver) == id &&
    context.symbol_id(result) == id &&
    context.uses_only_at(id, [binder, push.receiver, result]) else {
    return None
  }
  Some(binding.loc.merge(result.loc))
}

///|
fn check_collect_count(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(length) &&
    length.name == "length" &&
    length.args.is_empty() &&
    dot_call(length.receiver) is Some(collect) &&
    collect.args.is_empty() &&
    context.method_is(length.node, "Array", ["length"]) &&
    context.method_is(collect.node, "Iter", ["collect", "to_array"]) &&
    container_element(context.shape(collect.receiver), "Iter") is Some(element) &&
    array_element(context.shape(collect.node)) == Some(element) &&
    context.shape(node) == ({ "kind": "builtin", "name": "Int" } : Json) else {
    return None
  }
  Some(node.loc)
}

///|
fn check_discarded_map(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard node.kind is Expr_Apply &&
    positional_args(node) is Some([mapped]) &&
    dot_call(mapped) is Some(call) &&
    call.name == "map" &&
    call.args.length() == 1 &&
    context.builtin_value_call(node, "ignore") &&
    context.method_is(mapped, "Array", ["map"]) &&
    array_element(context.shape(mapped)) is Some(_) else {
    return None
  }
  Some(node.loc)
}

///|
fn check_iter_pipeline(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(outer) else { return None }
  let is_collected = ["collect", "to_array"].contains(outer.name)
  let map = if is_collected {
    guard outer.args.is_empty() &&
      context.method_is(node, "Iter", ["collect", "to_array"]) &&
      dot_call(outer.receiver) is Some(map) else {
      return None
    }
    map
  } else {
    outer
  }
  guard map.name == "map" &&
    map.args is [transform] &&
    dot_call(map.receiver) is Some(filter) &&
    filter.name == "filter" &&
    filter.args is [predicate] &&
    context.method_is(map.node, "Iter", ["map"]) &&
    context.method_is(filter.node, "Iter", ["filter"]) &&
    context.stable_identifier(filter.receiver) &&
    container_element(context.shape(filter.receiver), "Iter") is Some(a) &&
    container_element(context.shape(filter.node), "Iter") == Some(a) &&
    container_element(context.shape(map.node), "Iter") is Some(b) &&
    context.simple_callback(predicate) is Some((p_input, p_output)) &&
    context.simple_callback(transform) is Some((f_input, f_output)) else {
    return None
  }
  guard p_input == a &&
    f_input == a &&
    f_output == b &&
    p_output == ({ "kind": "builtin", "name": "Bool" } : Json) else {
    return None
  }
  if is_collected && array_element(context.shape(node)) != Some(b) {
    return None
  }
  Some(node.loc)
}

///|
fn check_consumed_iterator(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard context.previous.get(node.source_span) is Some((previous, current)) &&
    context.statement_call(current) is Some(later) &&
    later.node.source_span == node.source_span &&
    context.statement_call(previous) is Some(earlier) &&
    earlier.args.is_empty() &&
    later.args.is_empty() &&
    context.method_is(earlier.node, "Iter", [
      "count", "to_array", "collect", "last",
    ]) &&
    context.method_is(later.node, "Iter", [
      "count", "to_array", "collect", "last",
    ]) &&
    context.stable_identifier(earlier.receiver) &&
    context.stable_identifier(later.receiver) &&
    context.symbol_id(earlier.receiver) == context.symbol_id(later.receiver) &&
    container_element(context.shape(later.receiver), "Iter") is Some(_) else {
    return None
  }
  Some(node.loc)
}
