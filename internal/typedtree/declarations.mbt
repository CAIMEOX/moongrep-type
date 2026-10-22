///|
fn Exporter::owner_name(self : Exporter, binder : Int) -> String raise {
  let w = self.wire
  let id = w.record(binder, 2)[0]
  if w.tag(id) == 2 {
    self.qualified(w.fields(id, 2, 1)[0]).stringify()
  } else {
    "local:\{id}"
  }
}

///|
fn Exporter::implementation(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> Unit raise {
  let w = self.wire
  let tag = w.tag(id)
  match tag {
    0 => {
      let f = w.fields(id, 0, 7)
      let ctx = self.context(
        ctx,
        f[5],
        self.qualified(f[2]).stringify(),
        w.bool(f[6]),
      )
      self.fact(
        ctx,
        "declaration",
        "Timpl_expr",
        f[4],
        Some(self.node_type(ctx, "e", f[0])),
        None,
      )
      self.enqueue("e", f[0], ctx)
    }
    1 => {
      let f = w.fields(id, 1, 6)
      let d = w.record(f[0], 9)
      let derived = match w.value(d[0]) {
        Block(tag=3, ..) => true
        _ => false
      }
      let ctx = self.context(
        ctx,
        f[3],
        self.owner_name(d[1]),
        w.bool(f[4]) || derived,
      )
      let ty = self.typ(ctx, w.record(d[2], 8)[5])
      self.fact(
        ctx,
        "declaration",
        "Timpl_fun_decl",
        f[2],
        Some(ty),
        Some(self.ident(ctx, w.record(d[1], 2)[0])),
        details=[("arity", self.arity(f[1]))],
      )
      self.binding(ctx, d[1], Some(ty), "function")
      self.children(ctx, d, [
        "fkind", "b", "fn", "x", "tp", "*tn", "x", "x", "contract",
      ])
    }
    2 => {
      let f = w.fields(id, 2, 5)
      let d = w.record(f[0], 9)
      let ctx = self.context(ctx, f[3], self.owner_name(d[1]), w.bool(f[4]))
      self.fact(
        ctx,
        "declaration",
        "Timpl_mbtp_decl",
        f[2],
        Some(self.typ(ctx, w.record(d[3], 8)[5])),
        Some(self.ident(ctx, w.record(d[1], 2)[0])),
      )
      self.children(ctx, d, [
        "x", "b", "tp", "fn", "x", "x", "x", "contract", "x",
      ])
    }
    3 => {
      let f = w.fields(id, 3, 10)
      let ctx = self.context(ctx, f[5], self.owner_name(f[0]), w.bool(f[8]))
      let ty = self.node_type(ctx, "e", f[2])
      self.fact(
        ctx,
        "declaration",
        "Timpl_letdef",
        f[4],
        Some(ty),
        Some(self.ident(ctx, w.record(f[0], 2)[0])),
      )
      self.binding(ctx, f[0], Some(ty), "Timpl_letdef")
      self.children(ctx, f, ["b", "?ty", "e", "x", "l", "x", "x", "x", "x", "x"])
    }
    4 => {
      let d = w.record(w.fields(id, 4, 1)[0], 14)
      let ctx = self.context(ctx, d[13], self.owner_name(d[0]), false)
      let ty = self.typ(ctx, d[1])
      self.fact(
        ctx,
        "declaration",
        "Timpl_stub_decl",
        d[11],
        Some(ty),
        Some(self.ident(ctx, w.record(d[0], 2)[0])),
      )
      self.binding(ctx, d[0], Some(ty), "stub")
      self.children(ctx, d, [
        "b", "t", "tp", "*param", "?ty", "errty", "x", "x", "x", "x", "fkind", "l",
        "x", "x",
      ])
    }
    _ => raise Invalid("unknown implementation tag \{tag}")
  }
}

///|
fn Wire::hash_values(self : Wire, id : Int) -> Array[(String, Int)] raise {
  let h = self.record(id, 3)
  let out = []
  let seen : Map[Int, Bool] = Map([])
  for head in self.record(h[1], -1) {
    let mut node = head
    while !(self.value(node) is Integer(0L)) {
      if seen.contains(node) {
        raise Invalid("cyclic or duplicate hash bucket")
      }
      seen[node] = true
      let f = self.record(node, 3)
      out.push((self.text(f[0]), f[1]))
      node = f[2]
    }
  }
  if out.length() != self.integer(h[0]) {
    raise Invalid("hash table count mismatch")
  }
  out
}

///|
fn Exporter::load_type_environment(self : Exporter, id : Int) -> Unit raise {
  let w = self.wire
  for (_, info) in w.hash_values(id) {
    let tag = w.tag(info)
    let value = w.fields(info, tag, 1)[0]
    match tag {
      0 => {
        let f = w.record(value, 12)
        self.type_env[self.path(f[0]).stringify()] = info
      }
      1 => {
        let f = w.record(value, 11)
        self.type_env[self.path(f[0]).stringify()] = info
      }
      2 => {
        let f = w.record(value, 10)
        self.type_env[self.path(f[0]).stringify()] = info
      }
      3 => {
        let f = w.record(value, 8)
        self.type_env[self.path(f[0]).stringify()] = info
      }
      4 => ()
      _ => raise Invalid("unknown type environment entry")
    }
  }
}

///|
fn Exporter::load_value_environment(self : Exporter, id : Int) -> Unit raise {
  let w = self.wire
  let environment = w.record(id, 4)
  for (_, value) in w.hash_values(environment[0]) {
    let f = w.record(value, 11)
    self.global_values[self.qualified(f[0]).stringify()] = value
    if w.value(f[10]) is Block(tag~, fields~) && tag <= 2 {
      if fields.length() != (if tag == 0 { 1 } else { 2 }) {
        raise Invalid("invalid global alias metadata")
      }
      self.global_values[self.qualified(fields[0]).stringify()] = value
    }
  }
  for (_, items) in w.hash_values(environment[1]) {
    for info in w.list(items) {
      match w.tag(info) {
        0 => self.constructors.push(w.fields(info, 0, 1)[0])
        1 => ignore(w.fields(info, 1, 1))
        _ => raise Invalid("unknown constructor environment entry")
      }
    }
  }
}

///|
fn Exporter::declared_type(
  self : Exporter,
  ctx : Context,
  path : Json,
  params : Int,
  extension~ : Bool = false,
) -> Int raise {
  let w = self.wire
  let kind = if extension {
    "Extenum"
  } else {
    guard self.type_env.get(path.stringify()) is Some(info) else {
      raise Invalid("type declaration missing from environment")
    }
    let tag = w.tag(info)
    let record = w.fields(info, tag, 1)[0]
    if tag == 2 {
      return self.typ(ctx, w.record(record, 10)[3])
    }
    if tag != 0 {
      raise Invalid("type declaration has incorrect environment entry")
    }
    select_name(
      ["Normal", "Suberror", "Newtype", "Valtype", "Extenum"],
      w.integer(w.record(record, 12)[10]),
      "named type kind",
    )
  }
  let arguments = w
    .record(w.record(params, 2)[0], -1)
    .map(item => self.typ(ctx, w.record(item, 5)[1]))
  let id = self.types.length()
  self.types.push(
    obj([
      ("id", num(id)),
      ("kind", str("named")),
      ("path", path),
      ("arguments", json_array_int(arguments)),
      ("named_kind", str(kind)),
    ]),
  )
  id
}

///|
fn Exporter::declaration(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> Unit raise {
  let w = self.wire
  let tag = w.tag(id)
  if tag <= 2 {
    let d = w.record(w.fields(id, tag, 1)[0], if tag == 0 { 9 } else { 8 })
    let path = self.path(w.record(d[0], 3)[0])
    let base = d[if tag == 0 { 8 } else if tag == 1 { 7 } else { 5 }]
    let ctx = self.context(ctx, base, path.stringify(), false)
    if tag == 2 {
      let out = self.types.length()
      self.types.push(
        obj([("id", num(out)), ("kind", str("trait_object")), ("path", path)]),
      )
      let ctx = { ..ctx, parent_type: Some(path), parent_semtype: Some(out), }
      self.fact(
        ctx,
        "declaration",
        "Tdecl_trait_decl",
        d[4],
        Some(out),
        Some(self.type_symbol(path)),
      )
      self.children(ctx, d, ["tl", "*tn", "*method", "x", "l", "x", "x", "x"])
    } else {
      let ty = self.declared_type(ctx, path, d[1], extension=tag == 1)
      let ctx = { ..ctx, parent_type: Some(path), parent_semtype: Some(ty), }
      self.fact(
        ctx,
        "declaration",
        if tag == 0 {
          "Tdecl_type_decl"
        } else {
          "Tdecl_type_extension"
        },
        d[5],
        Some(ty),
        Some(self.type_symbol(path)),
      )
      self.children(
        ctx,
        d,
        if tag == 0 {
          ["tl", "tp", "typedesc", "x", "x", "l", "x", "*tn", "x"]
        } else {
          ["tl", "tp", "*constructordecl", "x", "x", "l", "x", "x"]
        },
      )
    }
  } else {
    let f = w.fields(id, tag, if tag == 4 { 6 } else { 7 })
    let base = f[f.length() - 1]
    let ctx = self.context(ctx, base, "declaration:\{tag}:\{id}", false)
    self.fact(
      ctx,
      "declaration",
      select_name(
        ["Tdecl_impl_relation", "Tdecl_using", "Tdecl_extend"],
        tag - 3,
        "declaration",
      ),
      f[f.length() - 2],
      None,
      None,
    )
    self.children(
      ctx,
      f,
      match tag {
        3 => ["tn", "ty", "x", "*tn", "x", "l", "x"]
        4 => ["label", "*using", "x", "x", "l", "x"]
        5 => ["tn", "tn", "*bindvar", "x", "x", "l", "x"]
        _ => raise Invalid("unknown top declaration tag")
      },
    )
  }
}

///|
fn Exporter::method_declaration(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> Unit raise {
  let w = self.wire
  let d = w.record(id, 8)
  let binder = w.record(d[0], 2)
  let name = w.text(binder[0])
  guard ctx.parent_type is Some(path) else {
    raise Invalid("trait method outside trait")
  }
  let ctx = { ..ctx, owner: ctx.owner + "::" + name, }
  let ty = self.typ(ctx, d[4])
  self.fact(
    ctx,
    "declaration",
    "method_decl",
    d[7],
    Some(ty),
    Some(self.member_symbol("trait_method", path, name)),
  )
  guard self.type_env.get(path.stringify()) is Some(info) else {
    raise Invalid("trait environment missing")
  }
  let definition = w.record(w.fields(info, 1, 1)[0], 11)
  let mut found = false
  for entry in w.list(definition[4]) {
    let method_info = w.record(entry, 8)
    if w.text(method_info[0]) == name {
      self.enqueue("tp", method_info[3], ctx)
      found = true
    }
  }
  if !found {
    raise Invalid("trait method environment missing")
  }
  self.children(ctx, d, [
    "label", "*param", "?ty", "errty", "t", "*tn", "x", "l",
  ])
}
