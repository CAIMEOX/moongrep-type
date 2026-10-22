///|
fn Exporter::record_children(
  self : Exporter,
  ctx : Context,
  id : Int,
  fields : Array[String],
) -> Unit raise {
  self.children(ctx, self.wire.record(id, fields.length()), fields)
}

///|
fn Exporter::step(
  self : Exporter,
  kind : String,
  id : Int,
  ctx : Context,
) -> Unit raise {
  let w = self.wire
  if kind == "x" ||
    kind == "l" ||
    kind == "accessor" ||
    kind == "cn" ||
    kind == "label" {
    return
  }
  if kind == "s" {
    ignore(w.text(id))
    return
  }
  if kind.has_prefix("!") {
    self.active.remove(
      (
        kind[1:].to_owned() + ctx.owner + ctx.file + ctx.base_line.to_string(),
        id,
      ),
    )
    return
  }
  let active = (kind + ctx.owner + ctx.file + ctx.base_line.to_string(), id)
  if self.active.contains(active) {
    raise Invalid("cyclic semantic node \{kind} at \{id}")
  }
  self.active[active] = true
  self.enqueue("!" + kind, id, ctx)
  if kind.has_prefix("*") || kind.has_prefix("#") {
    let nodes = if kind.has_prefix("*") { w.list(id) } else { w.record(id, -1) }
    for i = nodes.length() - 1; i >= 0; i = i - 1 {
      self.enqueue(
        kind[1:].to_owned(),
        nodes[i],
        if kind == "*fielddecl" {
          { ..ctx, field_position: i, }
        } else {
          ctx
        },
      )
    }
    return
  }
  if kind.has_prefix("?") {
    if w.option(id) is Some(child) {
      self.enqueue(kind[1:].to_owned(), child, ctx)
    }
    return
  }
  match kind {
    "e" | "p" | "ty" => self.semantic(ctx, kind, id)
    "impl" => self.implementation(ctx, id)
    "decl" => self.declaration(ctx, id)
    "method" => self.method_declaration(ctx, id)
    "t" => ignore(self.typ(ctx, id))
    "b" => self.binding(ctx, id, None, "binder")
    "v" => self.variable(ctx, id)
    "tl" => {
      let f = w.record(id, 3)
      self.fact(
        ctx,
        "type_use",
        "type_constr_loc",
        f[2],
        None,
        Some(self.type_symbol(self.path(f[0]))),
      )
    }
    "tn" => {
      let (symbol, loc) = self.type_name(ctx, id)
      let details = if w.tag(id) == 2 {
        let f = w.fields(id, 2, 4)
        [
          ("alias_symbol_id", str(self.type_symbol(self.path(f[2])))),
          ("target_symbol_id", str(symbol)),
        ]
      } else {
        []
      }
      self.fact(ctx, "type_use", "type_name", loc, None, Some(symbol), details~)
    }
    "pb" => {
      let f = w.record(id, 2)
      self.binding(ctx, f[0], Some(self.typ(ctx, f[1])), "pat_binder")
    }
    "sub" => ignore(self.substitution(ctx, id))
    "tp" => {
      let f = w.record(id, 2)
      for index, param in w.record(f[0], -1) {
        let p = w.record(param, 5)
        let symbol = self.symbol(
          "type_parameter",
          w.text(p[0]),
          obj([
            ("kind", str("type_parameter")),
            ("owner", str(ctx.owner)),
            ("index", num(index)),
          ]),
        )
        self.fact(
          ctx,
          "type_parameter",
          "tparam",
          p[4],
          Some(self.typ(ctx, p[1])),
          Some(symbol),
          details=[
            ("hidden", bool(w.bool(p[3]))),
            ("constraints", self.constraints(ctx, p[2])),
          ],
        )
        self.enqueue("*constraint", p[2], ctx)
      }
      if w.bool(f[1]) {
        self.fact(ctx, "effect", "error_parameter", -1, None, None)
      }
    }
    "constraint" => {
      let f = w.record(id, 3)
      self.fact(
        ctx,
        "constraint",
        "trait_constraint",
        f[1],
        None,
        Some(self.type_symbol(self.path(f[0]))),
        details=[("source", self.raw(f[2], 8))],
      )
    }
    "fn" => {
      let f = w.record(id, 8)
      self.fact(
        ctx,
        "expression",
        "function_body",
        f[7],
        Some(self.typ(ctx, f[5])),
        None,
      )
      self.children(ctx, f, ["*param", "l", "e", "?ty", "errty", "t", "x", "l"])
    }
    "param" => {
      let tag = w.tag(id)
      if tag == 0 {
        let f = w.fields(id, 0, 4)
        self.binding(ctx, f[0], Some(self.typ(ctx, f[2])), "Param", details=[
          ("parameter_kind", str(self.param_kind(f[3]))),
        ])
        self.children(ctx, f, ["b", "?ty", "t", "paramkind"])
      } else {
        let f = w.fields(id, 1, 3)
        self.fact(
          ctx,
          "binding",
          "Discard_positional_param",
          f[2],
          Some(self.typ(ctx, f[0])),
          None,
        )
        self.children(ctx, f, ["t", "?ty", "l"])
      }
    }
    "paramkind" =>
      match w.value(id) {
        Integer(n) if n >= 0L && n <= 2L => ()
        Block(tag=0, ..) => ignore(w.fields(id, 0, 1))
        Block(tag=1, ..) => self.children(ctx, w.fields(id, 1, 2), ["e", "x"])
        _ => raise Invalid("invalid parameter kind")
      }
    "arg" => {
      let tag = w.tag(id)
      let n = match tag {
        0 => 1
        1 => 2
        2 | 3 => 3
        4 | 5 => 4
        _ => raise Invalid("invalid argument")
      }
      let f = w.fields(id, tag, n)
      if tag >= 2 {
        let label = w.record(f[1], 2)
        self.fact(
          ctx,
          "argument",
          "labelled_argument",
          label[1],
          Some(self.node_type(ctx, "e", f[0])),
          None,
          details=[
            ("label", str(w.text(label[0]))),
            ("original_label", str(w.text(f[2]))),
            ("kind", num(tag)),
          ],
        )
      }
      self.enqueue("e", f[0], ctx)
    }
    "case" => self.record_children(ctx, id, ["p", "e", "?e", "*pb"])
    "bind" | "recbind" => {
      let f = w.record(id, if kind == "bind" { 2 } else { 3 })
      let expr = f[f.length() - 1]
      self.binding(ctx, f[0], Some(self.node_type(ctx, "e", expr)), kind)
      self.enqueue("e", expr, ctx)
      if kind == "recbind" {
        self.enqueue("?ty", f[1], ctx)
      }
    }
    "step" => self.record_children(ctx, id, ["v", "e"])
    "bindvar" => self.record_children(ctx, id, ["b", "v"])
    "loopproof" => self.record_children(ctx, id, ["*e", "?e"])
    "contract" => self.record_children(ctx, id, ["*e", "*e", "?e", "x"])
    "pipe" => {
      let tag = w.tag(id)
      self.children(
        ctx,
        w.fields(id, tag, if tag == 0 { 4 } else { 3 }),
        if tag == 0 {
          ["e", "*arg", "x", "l"]
        } else {
          ["e", "t", "l"]
        },
      )
    }
    "interp" => {
      let tag = w.tag(id)
      match tag {
        0 => ignore(w.fields(id, 0, 1))
        1 => self.children(ctx, w.fields(id, 1, 3), ["e", "e", "l"])
        2 => self.children(ctx, w.fields(id, 2, 2), ["e", "l"])
        _ => raise Invalid("invalid interpolation")
      }
    }
    "foreachbind" => {
      let tag = w.tag(id)
      if tag > 1 {
        raise Invalid("invalid foreach binder")
      }
      for item in w.fields(id, tag, tag + 1) {
        self.enqueue("foreachitem", item, ctx)
      }
    }
    "foreachitem" => self.record_children(ctx, id, ["p", "*pb"])
    "foreachkind" => {
      let tag = w.tag(id)
      if tag < 4 {
        self.enqueue("e", w.fields(id, tag, 1)[0], ctx)
      } else {
        self.children(ctx, w.fields(id, 4, 5), ["e", "e", "x", "x", "x"])
      }
    }
    "comprehension" => {
      let tag = w.tag(id)
      self.children(
        ctx,
        w.fields(id, tag, if tag == 0 { 4 } else { 3 }),
        if tag == 0 {
          ["foreachbind", "foreachkind", "*bind", "*step"]
        } else {
          ["*bind", "?e", "*step"]
        },
      )
    }
    "arraypat" =>
      match w.tag(id) {
        0 => self.enqueue("*p", w.fields(id, 0, 1)[0], ctx)
        1 => self.children(ctx, w.fields(id, 1, 3), ["*p", "*p", "?pb"])
        _ => raise Invalid("invalid array pattern")
      }
    "bitpat" => {
      let f = w.record(id, 9)
      self.fact(
        ctx,
        "metadata",
        "bitstring_extract",
        -1,
        Some(self.typ(ctx, f[7])),
        Some(self.ident(ctx, f[6])),
        details=[("pattern_type", num(self.typ(ctx, f[8])))],
      )
      self.enqueue("p", f[0], ctx)
    }
    "bitrest" =>
      if !(w.value(id) is Integer(0L)) {
        self.enqueue("?pb", w.fields(id, 0, 1)[0], ctx)
      }
    "constrarg" => self.children(ctx, w.record(id, 3), ["p", "x", "x"])
    "mappat" => self.record_children(ctx, id, ["x", "p"])
    "mapop" => {
      let f = w.record(id, 3)
      self.fact(
        ctx,
        "metadata",
        "map_get",
        -1,
        Some(self.typ(ctx, f[1])),
        Some(self.ident(ctx, f[0])),
        details=[("type_arguments", self.substitution(ctx, f[2]))],
      )
    }
    "fielddef" | "fieldpat" => {
      let f = w.record(id, if kind == "fielddef" { 5 } else { 4 })
      let label = w.record(f[0], 2)
      let family = if kind == "fielddef" { "e" } else { "p" }
      let sid = match ctx.parent_type {
        Some(path) =>
          Some(
            self.field_symbol(
              path,
              w.text(label[0]),
              w.integer(f[f.length() - 1]),
            ),
          )
        None => None
      }
      self.fact(
        ctx,
        "field_reference",
        kind,
        label[1],
        Some(self.node_type(ctx, family, f[1])),
        sid,
      )
      self.enqueue(family, f[1], ctx)
    }
    "fieldinfo" => {
      let f = w.record(id, 12)
      let path = self.wire_path(f[3])
      let ctx = match path {
        Some(path) => self.nominal_context(ctx, path)
        None => { ..ctx, origin_known: false, }
      }
      let record_ty = self.typ(ctx, f[3])
      let sid = match path {
        Some(path) =>
          Some(self.field_symbol(path, w.text(f[0]), w.integer(f[1])))
        None => None
      }
      self.fact(
        ctx,
        "metadata",
        "field_info",
        -1,
        Some(self.typ(ctx, f[2])),
        sid,
        details=[
          ("record_type", num(record_ty)),
          ("position", num(w.integer(f[1]))),
        ],
      )
      self.enqueue("tp", f[7], ctx)
    }
    "errty" =>
      match w.value(id) {
        Integer(0L) => ()
        Block(tag=0, ..) => self.enqueue("ty", w.fields(id, 0, 1)[0], ctx)
        Block(tag~, ..) if tag <= 3 => ignore(w.fields(id, tag, 1))
        _ => raise Invalid("invalid error annotation")
      }
    "fkind" =>
      match w.value(id) {
        Integer(0L) => ()
        Block(tag=0, ..) => self.enqueue("?tn", w.fields(id, 0, 1)[0], ctx)
        Block(tag=1, ..) => self.enqueue("tn", w.fields(id, 1, 1)[0], ctx)
        Block(tag=2, ..) => self.children(ctx, w.fields(id, 2, 2), ["ty", "tn"])
        Block(tag=3, ..) => ignore(w.fields(id, 3, 1))
        _ => raise Invalid("invalid function kind")
      }
    "typedesc" =>
      match w.value(id) {
        Integer(0L) => ()
        Block(tag~, ..) => {
          let child = w.fields(id, tag, 1)[0]
          self.enqueue(
            match tag {
              0 | 3 => "*constructordecl"
              1 => "exception"
              2 | 5 => "ty"
              4 => "*fielddecl"
              6 => "*ty"
              _ => raise Invalid("invalid type declaration")
            },
            child,
            ctx,
          )
        }
        _ => raise Invalid("invalid type description")
      }
    "exception" =>
      if !(w.value(id) is Integer(0L)) {
        self.enqueue("*constructordecl", w.fields(id, 0, 1)[0], ctx)
      }
    "constructordecl" => {
      let f = w.record(id, 6)
      let label = w.record(f[0], 2)
      let symbol = match ctx.parent_type {
        Some(p) => Some(self.constructor_symbol(p, w.text(label[0]), f[1]))
        None => None
      }
      let params = w
        .list(f[2])
        .map(arg => self.node_type(ctx, "ty", w.record(arg, 3)[0]))
      let constructor_ty = if params.is_empty() {
        ctx.parent_semtype
      } else {
        guard ctx.parent_semtype is Some(result) else {
          raise Invalid("constructor has no result type")
        }
        let index = self.types.length()
        self.types.push(
          obj([
            ("id", num(index)),
            ("kind", str("function")),
            ("parameters", json_array_int(params)),
            ("return_type", num(result)),
            ("error", obj([("kind", str("none"))])),
            ("async", str("sync")),
          ]),
        )
        Some(index)
      }
      self.fact(
        ctx,
        "declaration",
        "constructor",
        label[1],
        constructor_ty,
        symbol,
        details=[("tag", self.constructor_tag(f[1]))],
      )
      self.enqueue("*constrdeclarg", f[2], ctx)
    }
    "constrdeclarg" => self.record_children(ctx, id, ["ty", "x", "?label"])
    "fielddecl" => {
      let f = w.record(id, 6)
      let label = w.record(f[0], 2)
      let symbol = match ctx.parent_type {
        Some(p) =>
          Some(self.field_symbol(p, w.text(label[0]), ctx.field_position))
        None => None
      }
      self.fact(
        ctx,
        "declaration",
        "field",
        label[1],
        Some(self.node_type(ctx, "ty", f[1])),
        symbol,
        details=[("mutable", bool(w.bool(f[2])))],
      )
      self.enqueue("ty", f[1], ctx)
    }
    "using" => {
      let tag = w.tag(id)
      self.children(
        ctx,
        w.fields(id, tag, 2),
        if tag == 0 {
          ["b", "v"]
        } else if tag <= 2 {
          ["tl", "tn"]
        } else {
          raise Invalid("invalid using item")
        },
      )
    }
    "lb" => {
      let f = w.record(id, 2)
      let label = w.record(f[0], 2)
      let sid = self.symbol(
        "label",
        w.text(label[0]),
        obj([
          ("kind", str("label")),
          ("owner", str(ctx.owner)),
          ("stamp", num(w.integer(label[1]))),
        ]),
      )
      self.fact(ctx, "symbol_reference", "loop_label", f[1], None, Some(sid))
    }
    _ => raise Invalid("unsupported wire field \{kind}")
  }
}
