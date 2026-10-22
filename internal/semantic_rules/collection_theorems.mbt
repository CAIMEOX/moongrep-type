///|
/// The filtered array is immediately discarded after counting its elements.
/// Both forms evaluate the predicate once per input, in the same order.
fn check_array_filter_count(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(length) &&
    length.name == "length" &&
    length.args.is_empty() &&
    dot_call(length.receiver) is Some(filter) &&
    filter.name == "filter" &&
    filter.args is [predicate] &&
    context.method_is(length.node, "Array", ["length"]) &&
    context.method_is(filter.node, "Array", ["filter"]) &&
    array_element(context.shape(filter.receiver)) is Some(element) &&
    array_element(context.shape(filter.node)) == Some(element) &&
    unary_callback(context.shape(predicate)) is Some((input, output)) &&
    input == element &&
    output == ({ "kind": "builtin", "name": "Bool" } : Json) &&
    context.shape(node) == ({ "kind": "builtin", "name": "Int" } : Json) else {
    return None
  }
  Some(node.loc)
}

///|
fn check_iter_filter_count(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(count) &&
    count.name == "count" &&
    count.args.is_empty() &&
    dot_call(count.receiver) is Some(filter) &&
    filter.name == "filter" &&
    filter.args is [predicate] &&
    context.method_is(count.node, "Iter", ["count"]) &&
    context.method_is(filter.node, "Iter", ["filter"]) &&
    container_element(context.shape(filter.receiver), "Iter") is Some(element) &&
    container_element(context.shape(filter.node), "Iter") == Some(element) &&
    callback_arrow(context.shape(predicate)) is Some((input, output)) &&
    input == element &&
    output == ({ "kind": "builtin", "name": "Bool" } : Json) &&
    context.shape(node) == ({ "kind": "builtin", "name": "Int" } : Json) else {
    return None
  }
  Some(node.loc)
}

///|
/// Unlike collecting before looking for a match, these forms stop after exactly
/// the same successful pull, including when the predicate has side effects.
fn check_iter_filter_next(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(next) &&
    next.name == "next" &&
    next.args.is_empty() &&
    dot_call(next.receiver) is Some(filter) &&
    filter.name == "filter" &&
    filter.args is [predicate] &&
    context.method_is(next.node, "Iter", ["next"]) &&
    context.method_is(filter.node, "Iter", ["filter"]) &&
    container_element(context.shape(filter.receiver), "Iter") is Some(element) &&
    container_element(context.shape(filter.node), "Iter") == Some(element) &&
    callback_arrow(context.shape(predicate)) is Some((input, output)) &&
    input == element &&
    output == ({ "kind": "builtin", "name": "Bool" } : Json) &&
    builtin_type_arguments(context.shape(node), "Option") == Some([element]) else {
    return None
  }
  Some(node.loc)
}

///|
fn check_iter_find_first_exists(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(exists) &&
    ["is_some", "is_none"].contains(exists.name) &&
    exists.args.is_empty() &&
    dot_call(exists.receiver) is Some(find) &&
    find.name == "find_first" &&
    find.args is [predicate] &&
    context.method_is(exists.node, "Option", ["is_some", "is_none"]) &&
    context.method_is(find.node, "Iter", ["find_first"]) &&
    container_element(context.shape(find.receiver), "Iter") is Some(element) &&
    builtin_type_arguments(context.shape(find.node), "Option") ==
    Some([element]) &&
    unary_callback(context.shape(predicate)) is Some((input, output)) &&
    input == element &&
    output == ({ "kind": "builtin", "name": "Bool" } : Json) &&
    context.shape(node) == ({ "kind": "builtin", "name": "Bool" } : Json) else {
    return None
  }
  Some(node.loc)
}

///|
/// Iter's lazy map and flatten already interleave in flat_map order. Neither
/// source nor callback evaluation moves, and the callback is not duplicated.
fn check_iter_map_flatten(
  context : CheckContext,
  node : @untyped_cst.CstNode,
) -> @basic.Location? raise {
  guard dot_call(node) is Some(flatten) &&
    flatten.name == "flatten" &&
    flatten.args.is_empty() &&
    dot_call(flatten.receiver) is Some(map) &&
    map.name == "map" &&
    map.args is [transform] &&
    context.method_is(flatten.node, "Iter", ["flatten"]) &&
    context.method_is(map.node, "Iter", ["map"]) &&
    container_element(context.shape(map.receiver), "Iter")
    is Some(input_element) &&
    container_element(context.shape(map.node), "Iter") is Some(inner_iter) &&
    container_element(inner_iter, "Iter") is Some(output_element) &&
    container_element(context.shape(node), "Iter") == Some(output_element) &&
    callback_arrow(context.shape(transform)) is Some((input, output)) &&
    input == input_element &&
    output == inner_iter else {
    return None
  }
  Some(node.loc)
}
