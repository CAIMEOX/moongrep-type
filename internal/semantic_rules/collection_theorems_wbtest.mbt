///|
priv struct CollectionRuleFixture {
  text : String
  end_offset : Int
  types : Array[Json]
  symbols : Array[Json]
  facts : Array[Json]
}

///|
fn collection_type_path(name : String) -> Json {
  if name == "Option" {
    { "kind": "builtin", "name": name }
  } else {
    { "kind": "named", "package": "moonbitlang/core/builtin", "name": name }
  }
}

///|
fn collection_fixture(
  owner : String,
  inner : String,
  outer_owner : String,
  outer : String,
  receiver_type : Int,
  intermediate_type : Int,
  result_type : Int,
  callback_type~ : Int = 5,
) -> CollectionRuleFixture {
  let expression = "input.\{inner}(factory()).\{outer}()"
  let text = "fn sample() { \{expression} }"
  let start = "fn sample() { ".length()
  let inner_end = start + "input.\{inner}(factory())".length()
  let callback_start = start + "input.\{inner}(".length()
  let types : Array[Json] = [
    { "id": 0, "kind": "builtin", "name": "Int" },
    { "id": 1, "kind": "builtin", "name": "Bool" },
  ]
  for id, (name, argument) in [("Array", 0), ("Iter", 0), ("Option", 0)] {
    types.push({
      "id": id + 2,
      "kind": "named",
      "path": collection_type_path(name),
      "arguments": [argument],
      "named_kind": "Normal",
    })
  }
  types.push({
    "id": 5,
    "kind": "function",
    "parameters": [0],
    "return_type": 1,
    "error": { "kind": "none" },
    "async": "sync",
  })
  types.push({
    "id": 6,
    "kind": "named",
    "path": collection_type_path("Iter"),
    "arguments": [3],
    "named_kind": "Normal",
  })
  types.push({
    "id": 7,
    "kind": "function",
    "parameters": [0],
    "return_type": 3,
    "error": { "kind": "none" },
    "async": "sync",
  })
  types.push({ "id": 8, "kind": "builtin", "name": "String" })
  for id, name in ["Array", "Iter", "Option"] {
    types.push({
      "id": id + 9,
      "kind": "named",
      "path": collection_type_path(name),
      "arguments": [8],
      "named_kind": "Normal",
    })
  }
  types.push({
    "id": 12,
    "kind": "function",
    "parameters": [8],
    "return_type": 1,
    "error": { "kind": "none" },
    "async": "sync",
  })
  types.push({
    "id": 13,
    "kind": "function",
    "parameters": [0],
    "return_type": 1,
    "error": { "kind": "typed", "type_id": 14 },
    "async": "sync",
  })
  types.push({
    "id": 14,
    "kind": "named",
    "path": { "kind": "named", "package": "fixture", "name": "Failure" },
    "arguments": [],
    "named_kind": "Normal",
  })
  let symbols : Array[Json] = []
  for id, (method_owner, name) in [(owner, inner), (outer_owner, outer)] {
    symbols.push({
      "id": "method:\{id}",
      "kind": "global",
      "name": name,
      "identity": {
        "kind": "method",
        "self_type": collection_type_path(method_owner),
        "name": name,
      },
    })
  }
  let facts : Array[Json] = []
  for
    id, (offset, end_offset, type_id, symbol) in [
      (start, start + "input".length(), receiver_type, None),
      (
        callback_start,
        callback_start + "factory()".length(),
        callback_type,
        None,
      ),
      (start, inner_end, intermediate_type, Some("method:0")),
      (start, start + expression.length(), result_type, Some("method:1")),
    ] {
    facts.push({
      "id": id,
      "package": "fixture@wasm:normal",
      "kind": "expression",
      "node_kind": if id == 0 {
        "Texpr_ident"
      } else {
        "Texpr_apply"
      },
      "location": {
        "file": "/fixture/collection_theorems.mbt",
        "start": { "line": 1, "column": offset + 1 },
        "end": { "line": 1, "column": end_offset + 1 },
      },
      "type_id": type_id,
      "symbol_id": match symbol {
        Some(id) => Json::string(id)
        None => Json::null()
      },
      "details": match symbol {
        Some(id) => { "dispatch": "resolved_symbol", "callee_symbol_id": id }
        None => Json::object(Map([]))
      },
    })
  }
  { text, end_offset: start + expression.length(), types, symbols, facts, }
}

///|
fn collection_put(value : Json, key : String, replacement : Json) -> Unit {
  guard value is Object(fields) else {
    abort("expected collection fixture object")
  }
  fields[key] = replacement
}

///|
fn CollectionRuleFixture::matches(
  self : CollectionRuleFixture,
  check : (CheckContext, @untyped_cst.CstNode) -> @basic.Location? raise,
) -> Bool raise {
  let data : Json = {
    "schema_version": 1,
    "compiler_version": "fixture",
    "position_encoding": "unicode-scalar",
    "sources": [
      { "path": "/fixture/collection_theorems.mbt", "text": self.text },
    ],
    "types": self.types,
    "symbols": self.symbols,
    "facts": self.facts,
  }
  let source = @semantic_source.Source::parse(
    @semantic.Index::from_json(data, compiler_version="fixture"),
    file="/fixture/collection_theorems.mbt",
    text=self.text,
  )
  let context = CheckContext::new(source)
  let pending = [source.root()]
  while pending.pop() is Some(node) {
    if node.kind is Expr_DotApply && node.source_span.1 == self.end_offset {
      return check(context, node) is Some(_)
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  abort("missing collection fixture call")
}

///|
test "collection theorems accept callback factories and checked errors where supported" {
  inspect(
    collection_fixture("Array", "filter", "Array", "length", 2, 2, 0).matches(
      check_array_filter_count,
    ),
    content="true",
  )
  inspect(
    collection_fixture(
      "Array",
      "filter",
      "Array",
      "length",
      2,
      2,
      0,
      callback_type=13,
    ).matches(check_array_filter_count),
    content="true",
  )
  inspect(
    collection_fixture("Iter", "filter", "Iter", "count", 3, 3, 0).matches(
      check_iter_filter_count,
    ),
    content="true",
  )
  inspect(
    collection_fixture("Iter", "filter", "Iter", "next", 3, 3, 4).matches(
      check_iter_filter_next,
    ),
    content="true",
  )
  inspect(
    collection_fixture(
      "Iter",
      "find_first",
      "Option",
      "is_some",
      3,
      4,
      1,
      callback_type=13,
    ).matches(check_iter_find_first_exists),
    content="true",
  )
  inspect(
    collection_fixture("Iter", "find_first", "Option", "is_none", 3, 4, 1).matches(
      check_iter_find_first_exists,
    ),
    content="true",
  )
  inspect(
    collection_fixture(
      "Iter",
      "map",
      "Iter",
      "flatten",
      3,
      6,
      3,
      callback_type=7,
    ).matches(check_iter_map_flatten),
    content="true",
  )
}

///|
test "collection theorems reject lookalike methods and incorrect type flow" {
  let foreign = collection_fixture(
    "Array", "filter", "Array", "length", 2, 2, 0,
  )
  collection_put(foreign.symbols[0], "identity", {
    "kind": "method",
    "self_type": { "kind": "named", "package": "foreign", "name": "Array" },
    "name": "filter",
  })
  inspect(foreign.matches(check_array_filter_count), content="false")
  inspect(
    collection_fixture("Array", "filter", "Array", "length", 2, 9, 0).matches(
      check_array_filter_count,
    ),
    content="false",
  )
  inspect(
    collection_fixture(
      "Iter",
      "filter",
      "Iter",
      "count",
      3,
      3,
      0,
      callback_type=12,
    ).matches(check_iter_filter_count),
    content="false",
  )
  inspect(
    collection_fixture("Iter", "filter", "Iter", "next", 3, 3, 11).matches(
      check_iter_filter_next,
    ),
    content="false",
  )
  inspect(
    collection_fixture("Iter", "find_first", "OtherOption", "is_some", 3, 4, 1).matches(
      check_iter_find_first_exists,
    ),
    content="false",
  )
  inspect(
    collection_fixture(
      "Iter",
      "map",
      "Iter",
      "flatten",
      3,
      6,
      10,
      callback_type=7,
    ).matches(check_iter_map_flatten),
    content="false",
  )
  inspect(
    collection_fixture(
      "Array",
      "map",
      "Array",
      "flatten",
      2,
      6,
      2,
      callback_type=7,
    ).matches(check_iter_map_flatten),
    content="false",
  )
}

///|
test "collection theorems reject indirect dispatch and asynchronous callbacks" {
  let indirect = collection_fixture("Iter", "filter", "Iter", "count", 3, 3, 0)
  collection_put(indirect.facts[2], "details", { "dispatch": "indirect" })
  inspect(indirect.matches(check_iter_filter_count), content="false")
  let asynchronous = collection_fixture(
    "Array", "filter", "Array", "length", 2, 2, 0,
  )
  collection_put(asynchronous.types[5], "async", Json::string("async"))
  inspect(asynchronous.matches(check_array_filter_count), content="false")
}

///|
test "collection theorems retain generic owner identities" {
  let generic = collection_fixture("Iter", "filter", "Iter", "next", 3, 3, 4)
  generic.types[0] = {
    "id": 0,
    "kind": "parameter",
    "owner": "generic",
    "index": 0,
    "name": "T",
  }
  inspect(generic.matches(check_iter_filter_next), content="true")
  generic.types[8] = {
    "id": 8,
    "kind": "parameter",
    "owner": "unrelated",
    "index": 0,
    "name": "T",
  }
  collection_put(generic.facts[3], "type_id", Json::number(11))
  inspect(generic.matches(check_iter_filter_next), content="false")
}
