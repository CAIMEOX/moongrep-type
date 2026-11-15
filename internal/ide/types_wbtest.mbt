///|
fn type_test_source() -> InputSource {
  {
    path: "/fixture/types.mbt",
    text: "",
    package_name: "fixture/types",
    aliases: Map([("foreign", "other/types")]),
    type_names: Map([]),
  }
}

///|
test "IDE type syntax normalizes aliases functions errors and scoped generics" {
  let table = TypeTable::new()
  let source = type_test_source()
  let parameters : Map[String, Int32] = Map([("T", 0), ("E", 1)])
  let int = table.parse("Int", source, "scope", parameters).unwrap()
  assert_eq(table.parse("Int32", source, "scope", parameters), Some(int))
  assert_eq(
    table.parse("@moonbitlang/core/builtin.Int", source, "scope", parameters),
    Some(int),
  )
  let t = table.parse("T", source, "scope", parameters).unwrap()
  let other = table.parse("T", source, "other", parameters).unwrap()
  assert_true(t != other)
  let array = table.parse("Array[T]", source, "scope", parameters).unwrap()
  assert_true(
    table.values[array]
    is {
      "kind": "named",
      "path": { "package": "moonbitlang/core/builtin", "name": "Array", .. },
      "arguments": [value],
      ..
    } &&
    value == Json(t),
  )
  for text in ["T?", "Option[T]"] {
    let id = table.parse(text, source, "scope", parameters).unwrap()
    assert_true(
      table.values[id]
      is { "path": { "kind": "builtin", "name": "Option", .. }, .. },
    )
  }
  let callback = table
    .parse("(T) -> Int raise E", source, "scope", parameters)
    .unwrap()
  assert_true(
    table.values[callback]
    is {
      "kind": "function",
      "async": "sync",
      "error": { "kind": "typed", .. },
      ..
    },
  )
  let asynchronous = table
    .parse("async (T) -> Int", source, "scope", parameters)
    .unwrap()
  assert_true(
    table.values[asynchronous] is { "kind": "function", "async": "async", .. },
  )
  let signature = table
    .parse("fn format(value : Int) -> String", source, "scope", parameters)
    .unwrap()
  assert_true(
    table.values[signature] is { "kind": "function", "parameters": [value], .. } &&
    value == Json(int),
  )
  let foreign = table
    .parse("@foreign.Value[T]", source, "scope", parameters)
    .unwrap()
  assert_true(
    table.values[foreign]
    is { "path": { "package": "other/types", "name": "Value", .. }, .. },
  )
  assert_eq(
    table.parse("@other/types.Value[T]", source, "scope", parameters),
    Some(foreign),
  )
}

///|
test "unavailable and unsupported IDE types remain unavailable" {
  let table = TypeTable::new()
  for
    text in [
      "_", "", "this is not a type", "@missing.Value", "Array[_]", "NotDeclared",
    ] {
    assert_eq(table.parse(text, type_test_source(), "scope", Map([])), None)
  }
}

///|
test "source type declarations and explicit imports shadow prelude type names" {
  let base = type_test_source()
  let text = "pub struct Array[T](T)\n"
  let source = {
    ..base,
    text,
    type_names: type_declarations(text, base.package_name, base.aliases),
  }
  let table = TypeTable::new()
  let id = table.parse("Array[Int]", source, "scope", Map([])).unwrap()
  assert_true(
    table.values[id]
    is { "path": { "package": "fixture/types", "name": "Array", .. }, .. },
  )
}

///|
test "nested declaration type variables preserve their lexical owners" {
  let table = TypeTable::new()
  let source = type_test_source()
  let id = table
    .parse(
      "fn[X] nested(value : X) -> (T, X)",
      source,
      "outer",
      Map([("T", 0)]),
      signature_owner=Some("inner"),
    )
    .unwrap()
  guard table.values[id]
    is { "polymorphic": true, "return_type": Number(result, ..), .. } else {
    fail("generic scheme")
  }
  guard table.values[result.to_int()]
    is { "arguments": [Number(outer, ..), Number(inner, ..)], .. } else {
    fail("tuple result")
  }
  assert_true(
    table.values[outer.to_int()]
    is { "kind": "parameter", "owner": "outer", "index": 0, .. },
  )
  assert_true(
    table.values[inner.to_int()]
    is { "kind": "parameter", "owner": "inner", "index": 0, .. },
  )
  let global = table
    .parse(
      "fn[T] generic(value : T) -> T",
      source,
      "caller",
      Map([("T", 8)]),
      signature_owner=Some("definition"),
      global_signature=true,
    )
    .unwrap()
  guard table.values[global] is { "parameters": [Number(parameter, ..)], .. } else {
    fail("generic argument")
  }
  assert_true(
    table.values[parameter.to_int()]
    is { "owner": "definition", "index": 0, .. },
  )
}

///|
test "constructor query anchors preserve qualified leaf names" {
  let text = "fn f(it) { it.find_first(p) is Option::Some(_) }"
  let source = { ..type_test_source(), text, }
  let query = plan([source]).queries
    .iter()
    .find_first(q => q.node_kind == "constructor_pattern")
    .unwrap()
  let expected = "fn f(it) { it.find_first(p) is Option::".length() + 1
  assert_eq(query.anchor.start.column, expected)
  let field_text = "fn f(self) { self.value.map(x => x) }"
  let field_query = plan([{ ..type_test_source(), text: field_text, }]).queries
    .iter()
    .find_first(q => q.node_kind == "field")
    .unwrap()
  assert_eq(field_query.anchor.start.column, "fn f(self) { self.".length() + 1)
  assert_eq(field_query.anchor.end.column - field_query.anchor.start.column, 5)
}

///|
test "official CLI positions preserve scalar columns and reject invalid ranges" {
  let lines = source_lines("a🚀b\r\n第二行")
  assert_eq(lines[0].length(), 3)
  assert_eq(lines[1].length(), 3)
  let range = cli_span("1:2-1:3")
  assert_eq(range.start.column, 2)
  assert_eq(range.end.column, 3)
  for text in ["", "0:1-1:1", "1:2-1:1", "a:1-1:2", "2:1-1:2"] {
    let rejected = try {
      ignore(cli_span(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
