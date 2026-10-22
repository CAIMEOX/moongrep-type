///|
let primitive_names : Array[String] = [
  "Unit", "Bool", "Byte", "Char", "Int", "Int16", "Int64", "UInt", "UInt16", "UInt64",
  "Float", "Double", "String", "V128", "Bytes",
]

///|
let builtin_paths : Array[String] = [
  "Unit", "Bool", "Byte", "Char", "Int", "Int16", "Int64", "UInt", "UInt16", "UInt64",
  "Float", "Double", "String", "V128", "Option", "Result", "ErrorValueResult", "FixedArray",
  "ReadOnlyArray", "Bytes", "MutLocal", "Error", "Cancelled", "MaybeError", "BytesView",
  "StringView",
]

///|
fn Exporter::path(self : Exporter, id : Int) -> Json raise {
  let w = self.wire
  match w.value(id) {
    Integer(_) =>
      obj([
        ("kind", str("builtin")),
        ("name", str(select_name(builtin_paths, w.integer(id), "builtin path"))),
      ])
    Block(tag~, ..) =>
      match tag {
        0 => {
          let f = w.fields(id, 0, 2)
          obj([
            ("kind", str("named")),
            ("package", str(w.text(f[0]))),
            ("name", str(w.text(f[1]))),
          ])
        }
        1 => {
          let f = w.fields(id, 1, 4)
          obj([
            ("kind", str("generated")),
            ("package", str(w.text(f[0]))),
            ("owner", self.qualified(f[1])),
            ("name", str(w.text(f[2]))),
            ("stamp", num(w.integer(f[3]))),
          ])
        }
        2 =>
          obj([
            ("kind", str("tuple")),
            ("arity", num(w.integer(w.fields(id, 2, 1)[0]))),
          ])
        3 => {
          let f = w.fields(id, 3, 2)
          obj([
            ("kind", str("constructor_type")),
            ("type", self.path(f[0])),
            ("tag", self.constructor_tag(f[1])),
          ])
        }
        _ => raise Invalid("unknown type path tag \{tag}")
      }
    _ => raise Invalid("invalid type path")
  }
}

///|
fn Exporter::qualified(self : Exporter, id : Int) -> Json raise {
  let w = self.wire
  let tag = w.tag(id)
  let f = w.fields(id, tag, if tag <= 1 { 2 } else { 3 })
  match tag {
    0 =>
      obj([
        ("kind", str("value")),
        ("package", str(w.text(f[0]))),
        ("name", str(w.text(f[1]))),
      ])
    1 =>
      obj([
        ("kind", str("method")),
        ("self_type", self.path(f[0])),
        ("name", str(w.text(f[1]))),
      ])
    2 =>
      obj([
        ("kind", str("local_method")),
        ("package", str(w.text(f[0]))),
        ("self_type", self.path(f[1])),
        ("name", str(w.text(f[2]))),
      ])
    3 =>
      obj([
        ("kind", str("trait_implementation")),
        ("trait", self.path(f[0])),
        ("self_type", self.path(f[1])),
        ("name", str(w.text(f[2]))),
      ])
    _ => raise Invalid("unknown qualified identifier tag \{tag}")
  }
}

///|
fn json_name(value : Json) -> String {
  match value {
    { "name": String(name), .. } => name
    _ => value.stringify()
  }
}

///|
fn Exporter::ident(self : Exporter, ctx : Context, id : Int) -> String raise {
  let w = self.wire
  match w.tag(id) {
    0 => {
      let f = w.fields(id, 0, 2)
      let name = w.text(f[1])
      self.symbol(
        "local",
        name,
        obj([
          ("kind", str("local")),
          ("owner", str(ctx.owner)),
          ("stamp", num(w.integer(f[0]))),
          ("name", str(name)),
        ]),
      )
    }
    1 => {
      let f = w.record(w.fields(id, 1, 1)[0], 4)
      self.symbol(
        "parameter_method",
        w.text(f[3]),
        obj([
          ("kind", str("parameter_method")),
          ("owner", str(ctx.owner)),
          ("parameter_index", num(w.integer(f[0]))),
          ("parameter_name", str(w.text(f[1]))),
          ("trait", self.path(f[2])),
          ("method", str(w.text(f[3]))),
        ]),
      )
    }
    2 => {
      let q = self.qualified(w.fields(id, 2, 1)[0])
      self.symbol("global", json_name(q), q)
    }
    tag => raise Invalid("unknown identifier tag \{tag}")
  }
}

///|
fn Exporter::type_symbol(self : Exporter, path : Json) -> String {
  self.symbol(
    "type",
    json_name(path),
    obj([("kind", str("type")), ("path", path)]),
  )
}

///|
fn Exporter::member_symbol(
  self : Exporter,
  kind : String,
  owner : Json,
  name : String,
) -> String {
  self.symbol(
    kind,
    name,
    obj([("kind", str(kind)), ("owner_type", owner), ("name", str(name))]),
  )
}

///|
fn Exporter::field_symbol(
  self : Exporter,
  owner : Json,
  name : String,
  position : Int,
) -> String {
  self.symbol(
    "field",
    name,
    obj([
      ("kind", str("field")),
      ("owner_type", owner),
      ("position", num(position)),
    ]),
  )
}

///|
fn Exporter::constructor_symbol(
  self : Exporter,
  owner : Json,
  spelling : String,
  tag : Int,
) -> String raise {
  let tag_value = self.constructor_tag(tag)
  let name = json_name(tag_value)
  let owner = match owner {
    { "kind": "constructor_type", "type": underlying, .. } => underlying
    _ => owner
  }
  let identity = match tag_value {
    { "kind": "regular", "index": index, .. } =>
      obj([
        ("kind", str("constructor")),
        ("owner_type", owner),
        ("index", index),
      ])
    { "kind": "suberror", "package": pkg, "type_name": ty, "name": name, .. } =>
      obj([
        ("kind", str("constructor")),
        ("package", pkg),
        ("type_name", ty),
        ("name", name),
      ])
    {
      "kind": "extensible",
      "enum_package": pkg,
      "enum_name": ty,
      "constructor_package": constructor_pkg,
      "name": name,
      ..
    } =>
      obj([
        ("kind", str("constructor")),
        ("enum_package", pkg),
        ("enum_name", ty),
        ("constructor_package", constructor_pkg),
        ("name", name),
      ])
    _ => raise Invalid("invalid constructor identity")
  }
  self.symbol(
    "constructor",
    if name.is_empty() {
      spelling
    } else {
      name
    },
    identity,
  )
}

///|
fn Exporter::constructor_tag(self : Exporter, id : Int) -> Json raise {
  let w = self.wire
  match w.tag(id) {
    0 => {
      let f = w.fields(id, 0, 4)
      obj([
        ("kind", str("regular")),
        ("index", num(w.integer(f[1]))),
        ("name", str(w.text(f[3]))),
      ])
    }
    1 => {
      let f = w.fields(id, 1, 6)
      obj([
        ("kind", str("suberror")),
        ("package", str(w.text(f[0]))),
        ("type_name", str(w.text(f[1]))),
        ("name", str(w.text(f[2]))),
        ("index", num(w.integer(f[5]))),
      ])
    }
    2 => {
      let f = w.fields(id, 2, 7)
      obj([
        ("kind", str("extensible")),
        ("enum_package", str(w.text(f[0]))),
        ("enum_name", str(w.text(f[1]))),
        ("constructor_package", str(w.text(f[2]))),
        ("name", str(w.text(f[3]))),
        ("index", num(w.integer(f[6]))),
      ])
    }
    tag => raise Invalid("unknown constructor tag \{tag}")
  }
}

///|
fn Exporter::typ(self : Exporter, ctx : Context, id : Int) -> Int raise {
  let w = self.wire
  if w.value(id) is Integer(0L) {
    let key = ("error_recovery", -1)
    if self.type_ids.get(key) is Some(found) {
      return found
    }
    let n = self.types.length()
    self.types.push(obj([("id", num(n)), ("kind", str("error_recovery"))]))
    self.type_ids[key] = n
    return n
  }
  if w.tag(id) == 5 {
    return self.builtin(
      select_name(
        primitive_names,
        w.integer(w.fields(id, 5, 1)[0]),
        "primitive",
      ),
    )
  }
  let key = (ctx.owner, id)
  if self.type_ids.get(key) is Some(found) {
    return found
  }
  let out = self.types.length()
  self.type_ids[key] = out
  self.types.push(Json::null())
  let fields = match w.tag(id) {
    0 => {
      let f = w.fields(id, 0, 4)
      [
        ("kind", str("function")),
        ("parameters", json_array_int(w.list(f[0]).map(t => self.typ(ctx, t)))),
        ("return_type", num(self.typ(ctx, f[1]))),
        ("error", self.error(ctx, f[2], [])),
        (
          "async",
          str(
            select_name(
              ["sync", "async", "async_nocancel"],
              w.integer(f[3]),
              "async",
            ),
          ),
        ),
      ]
    }
    1 => {
      let f = w.fields(id, 1, 3)
      [
        ("kind", str("named")),
        ("path", self.path(f[0])),
        ("arguments", json_array_int(w.list(f[1]).map(t => self.typ(ctx, t)))),
        (
          "named_kind",
          str(
            select_name(
              ["Normal", "Suberror", "Newtype", "Valtype", "Extenum"],
              w.integer(f[2]),
              "named type kind",
            ),
          ),
        ),
      ]
    }
    2 => {
      let reference = w.fields(id, 2, 1)[0]
      let link = w.record(reference, 1)[0]
      match w.tag(link) {
        0 =>
          [
            ("kind", str("unresolved")),
            ("owner", str(ctx.owner)),
            ("variable", num(reference)),
            ("recovery", bool(w.integer(w.fields(link, 0, 1)[0]) == 1)),
          ]
        1 =>
          [
            ("kind", str("resolved_variable")),
            ("target_type", num(self.typ(ctx, w.fields(link, 1, 1)[0]))),
          ]
        tag => raise Invalid("unknown type link tag \{tag}")
      }
    }
    3 => {
      let f = w.fields(id, 3, 2)
      [
        ("kind", str("parameter")),
        ("owner", str(ctx.owner)),
        ("index", num(w.integer(f[0]))),
        ("name", str(w.text(f[1]))),
      ]
    }
    4 =>
      [
        ("kind", str("trait_object")),
        ("path", self.path(w.fields(id, 4, 1)[0])),
      ]
    tag => raise Invalid("unknown semantic type tag \{tag}")
  }
  self.types[out] = obj([("id", num(out)), ..fields])
  out
}

///|
fn Exporter::error(
  self : Exporter,
  ctx : Context,
  id : Int,
  visited : Array[Int],
) -> Json raise {
  if visited.contains(id) {
    raise Invalid("cyclic error link")
  }
  let w = self.wire
  match w.value(id) {
    Integer(0L) => obj([("kind", str("none"))])
    Integer(1L) => obj([("kind", str("parameter")), ("owner", str(ctx.owner))])
    Block(tag=0, ..) =>
      obj([
        ("kind", str("typed")),
        ("type_id", num(self.typ(ctx, w.fields(id, 0, 1)[0]))),
      ])
    Block(tag=1, ..) => {
      let reference = w.fields(id, 1, 1)[0]
      let link = w.record(reference, 1)[0]
      if w.value(link) is Integer(0L) {
        obj([
          ("kind", str("unresolved")),
          ("owner", str(ctx.owner)),
          ("variable", num(reference)),
        ])
      } else {
        self.error(ctx, w.record(link, 1)[0], [..visited, id])
      }
    }
    _ => raise Invalid("unknown error type")
  }
}

///|
fn Exporter::result_path(
  self : Exporter,
  type_id : Int,
  visited~ : Array[Int] = [],
) -> Json? raise {
  if visited.contains(type_id) {
    return None
  }
  match self.types[type_id] {
    { "kind": String("named" | "trait_object"), "path": path, .. } => Some(path)
    { "kind": "builtin", "name": String(name), .. } =>
      Some(obj([("kind", str("builtin")), ("name", str(name))]))
    { "kind": "resolved_variable", "target_type": Number(n, ..), .. } =>
      self.result_path(n.to_int(), visited=[..visited, type_id])
    { "kind": "function", "return_type": Number(n, ..), .. } =>
      self.result_path(n.to_int(), visited=[..visited, type_id])
    _ => None
  }
}
