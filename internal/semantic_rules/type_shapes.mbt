///|
fn reference_id(value : Json) -> Int? {
  guard value is Number(number, ..) && number >= 0.0 && number <= 2147483647.0 else {
    return None
  }
  let id = number.to_int()
  if id.to_double() == number {
    Some(id)
  } else {
    None
  }
}

///|
/// Normalize only known, fully resolved types. In particular, identical handles
/// for unresolved variables are not evidence of type equality.
fn type_shape(
  index : @semantic.Index,
  id : Int,
  ancestors~ : Array[Int] = [],
) -> Json? {
  if ancestors.length() >= 128 || ancestors.contains(id) {
    return None
  }
  guard index.type_info(id) is Some(info) else { return None }
  let ancestors = [..ancestors, id]
  match info.raw {
    { "kind": "resolved_variable", "target_type": target, .. } =>
      reference_id(target).bind(id => type_shape(index, id, ancestors~))
    { "kind": "builtin", "name": String(name), .. } =>
      Some({ "kind": "builtin", "name": name })
    { "kind": "parameter", "owner": String(owner), "index": number, .. } => {
      guard reference_id(number) is Some(position) else { return None }
      Some({ "kind": "parameter", "owner": owner, "index": position })
    }
    {
      "kind": "named",
      "path": path,
      "arguments": Array(args),
      "named_kind": String(kind),
      ..
    } => {
      guard known_path(path) &&
        type_shapes(index, args, ancestors) is Some(arguments) else {
        return None
      }
      Some({
        "kind": "named",
        "path": path,
        "arguments": arguments,
        "named_kind": kind,
      })
    }
    { "kind": "trait_object", "path": path, .. } if known_path(path) =>
      Some({ "kind": "trait_object", "path": path })
    {
      "kind": "function",
      "parameters": Array(params),
      "return_type": result,
      "error": error,
      "async": String(async_kind),
      ..
    } => {
      guard type_shapes(index, params, ancestors) is Some(parameters) &&
        reference_id(result).bind(id => type_shape(index, id, ancestors~))
        is Some(return_type) &&
        error_shape(index, error, ancestors) is Some(error_type) else {
        return None
      }
      if !["sync", "async", "async_nocancel"].contains(async_kind) {
        return None
      }
      Some({
        "kind": "function",
        "parameters": parameters,
        "return_type": return_type,
        "error": error_type,
        "async": async_kind,
      })
    }
    _ => None
  }
}

///|
fn type_shapes(
  index : @semantic.Index,
  ids : Array[Json],
  ancestors : Array[Int],
) -> Array[Json]? {
  let result = []
  for value in ids {
    guard reference_id(value).bind(id => type_shape(index, id, ancestors~))
      is Some(shape) else {
      return None
    }
    result.push(shape)
  }
  Some(result)
}

///|
fn error_shape(
  index : @semantic.Index,
  error : Json,
  ancestors : Array[Int],
) -> Json? {
  match error {
    { "kind": "none", .. } => Some({ "kind": "none" })
    { "kind": "parameter", "owner": String(owner), .. } =>
      Some({ "kind": "parameter", "owner": owner })
    { "kind": "typed", "type_id": value, .. } => {
      guard reference_id(value).bind(id => type_shape(index, id, ancestors~))
        is Some(shape) else {
        return None
      }
      Some({ "kind": "typed", "type": shape })
    }
    _ => None
  }
}

///|
fn known_path(path : Json) -> Bool {
  match path {
    { "kind": "builtin", "name": String(_), .. }
    | { "kind": "named", "package": String(_), "name": String(_), .. }
    | {
      "kind": "generated",
      "package": String(_),
      "owner": Object(_),
      "name": String(_),
      "stamp": Number(_, ..),
      ..
    }
    | { "kind": "tuple", "arity": Number(_, ..), .. } => true
    { "kind": "constructor_type", "type": inner, "tag": Object(_), .. } =>
      known_path(inner)
    _ => false
  }
}

///|
fn array_element(shape : Json) -> Json? {
  match shape {
    {
      "kind": "named",
      "path": {
        "kind": "named",
        "package": "moonbitlang/core/builtin",
        "name": "Array",
        ..
      },
      "arguments": [element],
      "named_kind": "Normal",
      ..
    } => Some(element)
    _ => None
  }
}

///|
fn callback_arrow(shape : Json) -> (Json, Json)? {
  match shape {
    {
      "kind": "function",
      "parameters": [input],
      "return_type": output,
      "async": "sync",
      "error": { "kind": "none", .. },
      ..
    } => Some((input, output))
    _ => None
  }
}

///|
/// Preserve nominal type paths and generic owners. Only built-in sum types
/// qualify; an unrelated user type named Option or Result is not evidence.
fn builtin_type_arguments(shape : Json, name : String) -> Array[Json]? {
  match shape {
    {
      "kind": "named",
      "named_kind": "Normal",
      "path": { "kind": "builtin", "name": String(found), .. },
      "arguments": Array(arguments),
      ..
    } if found == name => Some(arguments)
    _ => None
  }
}

///|
/// A resolved synchronous unary arrow, including its checked error effect.
/// This is type evidence only, not evidence of purity or termination.
fn unary_callback(shape : Json) -> (Json, Json)? {
  match shape {
    {
      "kind": "function",
      "parameters": [input],
      "return_type": output,
      "async": "sync",
      "error": error,
      ..
    } if error
      is ({ "kind": "none", .. }
      | { "kind": "typed", .. }
      | { "kind": "parameter", .. }) => Some((input, output))
    _ => None
  }
}
