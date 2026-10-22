///|
/// Some constructors (notably tuple structs and newtypes) are represented in
/// the serialized declaration environment rather than the source-facing list.
fn Exporter::implicit_constructors(
  self : Exporter,
  ctx : Context,
) -> Unit raise {
  let w = self.wire
  for entry in self.constructors {
    let c = w.record(entry, 12)
    let definition = w.record(c[8], 3)
    if w.text(definition[0]) != ctx.pkg_name {
      continue
    }
    let start = w.record(definition[1], 3)
    let end = w.record(definition[2], 3)
    let file = w.text(start[0])
    let start_line = w.integer(start[1])
    let start_column = w.integer(start[2])
    if start_line < 1 || start_column < 0 {
      continue
    }
    guard self.wire_path(c[2]) is Some(path) else {
      raise Invalid("constructor result has no nominal type")
    }
    let symbol = self.constructor_symbol(path, w.text(c[0]), c[3])
    if self.constructor_definitions.contains(symbol) {
      continue
    }
    let logical = if @path.Path::is_absolute(file) {
      @path.Path::normalize(file).to_string()
    } else {
      @path.Path::join(ctx.root, file).normalize().to_string()
    }
    let file = self.source_aliases.get(logical).unwrap_or(logical)
    if !self.sources.contains(file) {
      continue
    }
    let context = self.nominal_context(ctx, path)
    let arguments = w.list(c[1]).map(ty => self.typ(context, ty))
    let result = self.typ(context, c[2])
    let ty = if arguments.is_empty() {
      result
    } else {
      let id = self.types.length()
      self.types.push(
        obj([
          ("id", num(id)),
          ("kind", str("function")),
          ("parameters", json_array_int(arguments)),
          ("return_type", num(result)),
          ("error", obj([("kind", str("none"))])),
          ("async", str("sync")),
        ]),
      )
      id
    }
    let location = obj([
      ("file", str(file)),
      (
        "start",
        obj([("line", num(start_line)), ("column", num(start_column + 1))]),
      ),
      (
        "end",
        obj([
          ("line", num(w.integer(end[1]))),
          ("column", num(w.integer(end[2]) + 1)),
        ]),
      ),
    ])
    self.fact_at(
      context,
      "declaration",
      "constructor",
      location,
      Some(ty),
      Some(symbol),
      details=[("arity", self.arity(c[6])), ("tag", self.constructor_tag(c[3]))],
    )
  }
}
