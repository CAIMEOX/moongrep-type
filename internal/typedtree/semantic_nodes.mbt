///|
fn Exporter::shape_for(self : Exporter, kind : String, id : Int) -> Shape raise {
  let shapes = match kind {
    "e" => expressions
    "p" => patterns
    "ty" => type_nodes
    _ => raise Invalid("unknown node family")
  }
  let tag = self.wire.tag(id)
  guard shapes.get(tag) is Some(shape) else {
    raise Invalid("unknown \{kind} tag \{tag}")
  }
  ignore(self.wire.fields(id, tag, shape.fields.length()))
  shape
}

///|
fn Exporter::node_type(
  self : Exporter,
  ctx : Context,
  kind : String,
  id : Int,
) -> Int raise {
  let shape = self.shape_for(kind, id)
  let f = self.wire.fields(id, self.wire.tag(id), shape.fields.length())
  if shape.type_slot >= 0 {
    return self.typ(ctx, f[shape.type_slot])
  }
  match shape.type_slot {
    -2 => self.builtin("Unit")
    -3 => self.builtin("Bool")
    -4 => self.builtin("String")
    -5 => self.builtin("StringView")
    -6 => self.builtin("BytesView")
    -7 => self.node_type(ctx, "p", f[0])
    _ => raise Invalid("missing node type for \{shape.name}")
  }
}

///|
fn Exporter::var_parts(
  self : Exporter,
  id : Int,
  actual~ : Bool = false,
) -> (Int, Int, Array[(String, Int)]) raise {
  let w = self.wire
  match w.tag(id) {
    0 => {
      let f = w.fields(id, 0, 2)
      (f[0], f[1], [])
    }
    1 => {
      let f = w.fields(id, 1, 3)
      (f[1], f[2], [("alias_symbol_id", f[0]), ("target_symbol_id", f[1])])
    }
    2 => {
      let f = w.fields(id, 2, 4)
      (
        if actual {
          f[1]
        } else {
          f[0]
        },
        f[3],
        [("constructor_symbol_id", f[0]), ("method_symbol_id", f[1])],
      )
    }
    tag => raise Invalid("unknown variable tag \{tag}")
  }
}

///|
fn Exporter::variable(self : Exporter, ctx : Context, id : Int) -> Unit raise {
  let (ident, loc, aliases) = self.var_parts(id)
  let details = aliases.map(pair => (pair.0, str(self.ident(ctx, pair.1))))
  self.fact(
    ctx,
    "symbol_reference",
    "var",
    loc,
    None,
    Some(self.ident(ctx, ident)),
    details~,
  )
}

///|
fn Exporter::binding(
  self : Exporter,
  ctx : Context,
  id : Int,
  ty : Int?,
  name : String,
  details~ : Array[(String, Json)] = [],
) -> Unit raise {
  let f = self.wire.record(id, 2)
  let ty = if ty is None && self.wire.tag(f[0]) == 2 {
    let identity = self.qualified(self.wire.fields(f[0], 2, 1)[0])
    match self.global_values.get(identity.stringify()) {
      Some(value) => {
        let info = self.wire.record(value, 11)
        let context = {
          ..ctx,
          owner: ctx.view_key + ":value:" + self.qualified(info[0]).stringify(),
        }
        Some(self.typ(context, info[1]))
      }
      None => None
    }
  } else {
    ty
  }
  self.fact(
    ctx,
    "binding",
    name,
    f[1],
    ty,
    Some(self.ident(ctx, f[0])),
    details~,
  )
}

///|
fn Exporter::callee(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> (String?, String) raise {
  let tag = self.wire.tag(id)
  if tag == 1 || tag == 3 {
    let f = self.wire.fields(id, tag, if tag == 1 { 7 } else { 6 })
    let (ident, _, _) = self.var_parts(f[0], actual=true)
    (
      Some(self.ident(ctx, ident)),
      match self.wire.tag(ident) {
        0 => "binding"
        1 => "parameter_method"
        _ => "resolved_symbol"
      },
    )
  } else {
    (None, if tag == 2 { "unresolved_trait" } else { "indirect" })
  }
}

///|
fn Exporter::type_name(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> (String, Int) raise {
  let w = self.wire
  match w.tag(id) {
    0 => {
      let f = w.fields(id, 0, 3)
      (
        self.symbol(
          "type_parameter",
          w.text(f[1]),
          obj([
            ("kind", str("type_parameter")),
            ("owner", str(ctx.owner)),
            ("index", num(w.integer(f[0]))),
          ]),
        ),
        f[2],
      )
    }
    1 => {
      let f = w.record(w.fields(id, 1, 1)[0], 3)
      (self.type_symbol(self.path(f[0])), f[2])
    }
    2 => {
      let f = w.fields(id, 2, 4)
      (self.type_symbol(self.path(f[0])), f[3])
    }
    _ => raise Invalid("unknown type name")
  }
}

///|
fn Exporter::constraints(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> Json raise {
  let w = self.wire
  Json::array(
    w
    .list(id)
    .map(item => {
      let f = w.record(item, 3)
      obj([
        ("trait", self.path(f[0])),
        ("location", self.location(ctx, f[1])),
        ("source", self.raw(f[2], 8)),
      ])
    }),
  )
}

///|
fn Exporter::substitution(
  self : Exporter,
  ctx : Context,
  id : Int,
) -> Json raise {
  let w = self.wire
  let f = w.record(id, 2)
  let origin = { ..ctx, origin_known: false, }
  let entries = w
    .record(f[0], -1)
    .map(item => {
      let pair = w.record(item, 2)
      obj([
        ("type_id", num(self.typ(ctx, pair[0]))),
        ("constraints", self.constraints(origin, pair[1])),
      ])
    })
  obj([
    ("types", Json::array(entries)),
    (
      "error",
      match w.option(f[1]) {
        Some(e) => self.error(ctx, e, [])
        None => Json::null()
      },
    ),
  ])
}

///|
/// Opaque auxiliary data stays structural; it never runs a custom decoder or
/// masquerades as a typed node. References beyond the display depth are explicit.
fn Exporter::raw(self : Exporter, id : Int, depth : Int) -> Json raise {
  if depth <= 0 {
    return obj([("wire_reference", num(id))])
  }
  match self.wire.value(id) {
    Integer(n) => obj([("integer", str(n.to_string()))])
    Block(tag~, fields~) =>
      obj([
        ("tag", num(tag)),
        ("fields", Json::array(fields.map(n => self.raw(n, depth - 1)))),
      ])
    ByteString(_) =>
      try self.wire.text(id) catch {
        _ => obj([("wire_reference", num(id)), ("kind", str("binary_string"))])
      } noraise {
        s => str(s)
      }
    FloatBits(n) => obj([("float_bits", str(n.to_string()))])
    FloatArray(ns) =>
      obj([("float_bits", Json::array(ns.map(n => str(n.to_string()))))])
    Custom(name~, value~) =>
      obj([("custom", str(name)), ("value", str(value.to_string()))])
  }
}

///|
fn Exporter::enqueue(
  self : Exporter,
  kind : String,
  id : Int,
  ctx : Context,
) -> Unit {
  self.pending.push((kind, id, ctx))
}

///|
fn Exporter::children(
  self : Exporter,
  ctx : Context,
  f : Array[Int],
  kinds : Array[String],
) -> Unit raise {
  if f.length() != kinds.length() {
    raise Invalid("record field count mismatch")
  }
  for i = f.length() - 1; i >= 0; i = i - 1 {
    self.enqueue(kinds[i], f[i], ctx)
  }
}

///|
fn Exporter::semantic(
  self : Exporter,
  ctx : Context,
  family : String,
  id : Int,
) -> Unit raise {
  let w = self.wire
  let shape = self.shape_for(family, id)
  let tag = w.tag(id)
  let f = w.fields(id, tag, shape.fields.length())
  let ty = self.node_type(ctx, family, id)
  let loc = if shape.location_slot >= 0 {
    f[shape.location_slot]
  } else {
    w.record(f[0], 8)[7]
  }
  let details : Array[(String, Json)] = []
  let mut symbol : String? = None
  if family == "e" {
    match tag {
      0 => {
        let (callee, dispatch) = self.callee(ctx, f[0])
        symbol = callee
        details.append([
          ("callee_symbol_id", nullable_symbol(callee)),
          ("dispatch", str(dispatch)),
          ("rethrow", bool(w.integer(f[2]) == 1)),
        ])
      }
      1 | 3 => {
        let (ident, _, aliases) = self.var_parts(f[0])
        symbol = Some(self.ident(ctx, ident))
        details.push(("type_arguments", self.substitution(ctx, f[1])))
        if w.option(f[2]) is Some(arity) {
          details.push(("arity", self.arity(arity)))
        }
        details.append(
          aliases.map(pair => (pair.0, str(self.ident(ctx, pair.1)))),
        )
      }
      2 => {
        let (trait_id, _) = self.type_name(ctx, f[0])
        details.append([
          ("unresolved_dispatch", bool(true)),
          ("trait_symbol_id", str(trait_id)),
          ("method", str(w.text(f[1]))),
          ("self_type", num(self.typ(ctx, f[2]))),
          ("type_arguments", self.substitution(ctx, f[3])),
        ])
      }
      4 => details.push(("implicit", bool(w.bool(f[3]))))
      7 => {
        let cn = w.record(f[1], 3)
        if self.result_path(ty) is Some(owner) {
          symbol = Some(
            self.constructor_symbol(
              owner,
              w.text(cn[0]),
              f[if family == "e" { 2 } else { 3 }],
            ),
          )
        }
        self.fact(
          ctx,
          "constructor_reference",
          shape.name,
          cn[2],
          Some(ty),
          symbol,
          details=[("tag", self.constructor_tag(f[2]))],
        )
      }
      12 =>
        self.binding(
          ctx,
          f[0],
          Some(self.typ(ctx, w.record(f[1], 8)[5])),
          shape.name,
        )
      23 =>
        self.binding(
          ctx,
          f[0],
          Some(self.node_type(ctx, "e", f[2])),
          shape.name,
        )
      19 => {
        let owner_type = self.node_type(ctx, "e", f[0])
        let access_tag = w.tag(f[1])
        let a = w.fields(f[1], access_tag, if access_tag == 1 { 2 } else { 1 })
        let (name, field_loc) = match access_tag {
          0 => {
            let label = w.record(a[0], 2)
            (w.text(label[0]), label[1])
          }
          1 => (w.integer(a[0]).to_string(), a[1])
          2 => ("0", a[0])
          _ => raise Invalid("invalid field accessor")
        }
        if self.result_path(owner_type) is Some(owner) {
          symbol = Some(self.field_symbol(owner, name, w.integer(f[2])))
        }
        self.fact(
          ctx,
          "field_reference",
          shape.name,
          field_loc,
          Some(ty),
          symbol,
          details=[
            ("receiver_type", num(owner_type)),
            ("position", num(w.integer(f[2]))),
          ],
        )
      }
      20 => {
        let label = w.record(f[1], 2)
        let receiver = self.node_type(ctx, "e", f[0])
        let sid = match self.result_path(receiver) {
          Some(p) =>
            Some(self.field_symbol(p, w.text(label[0]), w.integer(f[3])))
          None => None
        }
        self.fact(
          ctx,
          "field_reference",
          shape.name,
          label[1],
          Some(self.node_type(ctx, "e", f[2])),
          sid,
        )
      }
      35 => details.push(("caught_error_type", num(self.typ(ctx, f[5]))))
      36 =>
        details.append([
          ("try_operator", num(w.integer(f[1]))),
          ("async", num(w.integer(f[2]))),
        ])
      41 => details.push(("deferred_function_type", num(self.typ(ctx, f[3]))))
      46 | 47 | 48 => details.push(("implicit", bool(true)))
      _ => ()
    }
  } else if family == "p" {
    match tag {
      0 => self.binding(ctx, f[1], Some(ty), shape.name)
      8 => self.binding(ctx, f[0], Some(ty), shape.name)
      5 => {
        let cn = w.record(f[1], 3)
        if self.result_path(ty) is Some(owner) {
          symbol = Some(
            self.constructor_symbol(
              owner,
              w.text(cn[0]),
              f[if family == "e" { 2 } else { 3 }],
            ),
          )
        }
        self.fact(
          ctx,
          "constructor_reference",
          shape.name,
          cn[2],
          Some(ty),
          symbol,
          details=[
            ("tag", self.constructor_tag(f[3])),
            (
              "parameter_types",
              json_array_int(w.list(f[7]).map(t => self.typ(ctx, t))),
            ),
          ],
        )
      }
      _ => ()
    }
  } else {
    if shape.type_slot >= 0 && self.wire_path(f[shape.type_slot]) is Some(p) {
      symbol = Some(self.type_symbol(p))
    }
    if tag == 3 || tag == 4 {
      let slot = if tag == 3 { 3 } else { 2 }
      if w.option(f[slot]) is Some(alias_path) {
        details.append([
          ("alias", self.path(alias_path)),
          ("alias_symbol_id", str(self.type_symbol(self.path(alias_path)))),
        ])
      }
    }
  }
  self.fact(
    ctx,
    match family {
      "e" => "expression"
      "p" => "pattern"
      _ => "type_use"
    },
    shape.name,
    loc,
    Some(ty),
    symbol,
    details~,
  )
  let ctx = if (family == "e" && (tag == 17 || tag == 18)) ||
    (family == "p" && tag == 9) {
    { ..ctx, parent_type: self.result_path(ty), parent_semtype: Some(ty), }
  } else {
    ctx
  }
  self.children(ctx, f, shape.fields)
}
