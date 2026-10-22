///|
pub(all) struct Source {
  path : String
  text : String
}

///|
pub(all) struct Package {
  key : String
  name : String
  source_root : String
  artifact : Bytes
  source_aliases : Array[(String, String)]
}

///|
priv struct Context {
  view_key : String
  pkg_name : String
  root : String
  owner : String
  file : String
  base_line : Int
  generated : Bool
  origin_known : Bool
  parent_type : Json?
  parent_semtype : Int?
  field_position : Int
}

///|
priv struct Exporter {
  wire : Wire
  sources : Map[String, String]
  source_aliases : Map[String, String]
  types : Array[Json]
  type_ids : Map[(String, Int), Int]
  builtin_ids : Map[String, Int]
  symbols : Array[Json]
  symbol_ids : Map[String, String]
  facts : Array[Json]
  type_env : Map[String, Int]
  global_values : Map[String, Int]
  constructors : Array[Int]
  constructor_definitions : Map[String, Bool]
  active : Map[(String, Int), Bool]
  pending : Array[(String, Int, Context)]
}

///|
fn obj(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
fn num(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
fn str(s : String) -> Json {
  Json::string(s)
}

///|
fn bool(b : Bool) -> Json {
  Json::boolean(b)
}

///|
fn nullable_id(id : Int?) -> Json {
  match id {
    Some(id) => num(id)
    None => Json::null()
  }
}

///|
fn nullable_symbol(id : String?) -> Json {
  match id {
    Some(id) => str(id)
    None => Json::null()
  }
}

///|
fn Exporter::location(self : Exporter, ctx : Context, id : Int) -> Json raise {
  if id < 0 || !ctx.origin_known || ctx.base_line < 0 {
    return Json::null()
  }
  let f = self.wire.record(id, 2)
  let start = self.wire.integer(f[0])
  let end = self.wire.integer(f[1])
  if start == -1 && end == -1 {
    return Json::null()
  }
  if start < 0 || end < start {
    raise Invalid("invalid packed source range")
  }
  let file = if ctx.file.has_prefix("/") ||
    (ctx.file.length() > 1 && ctx.file[1] == ':') {
    ctx.file
  } else {
    ctx.root + "/" + ctx.file
  }
  let logical = @path.Path::normalize(file).to_string()
  let file = self.source_aliases.get(logical).unwrap_or(logical)
  if !self.sources.contains(file) {
    raise Invalid("source text missing for \{file}")
  }
  fn position(p : Int) -> Json {
    obj([
      ("line", num(ctx.base_line + (p >> 16))),
      ("column", num((p & 65535) + 1)),
    ])
  }
  obj([("file", str(file)), ("start", position(start)), ("end", position(end))])
}

///|
fn Exporter::context(
  self : Exporter,
  ctx : Context,
  base : Int,
  owner : String,
  generated : Bool,
) -> Context raise {
  let fields = self.wire.record(base, 3)
  let file = self.wire.text(fields[1])
  let line = self.wire.integer(fields[2])
  {
    ..ctx,
    owner: ctx.view_key + ":" + file + ":" + owner,
    file,
    base_line: line,
    generated,
    parent_type: None,
    parent_semtype: None,
  }
}

///|
fn Exporter::fact(
  self : Exporter,
  ctx : Context,
  kind : String,
  node : String,
  loc : Int,
  ty : Int?,
  symbol : String?,
  details~ : Array[(String, Json)] = [],
) -> Unit raise {
  self.fact_at(ctx, kind, node, self.location(ctx, loc), ty, symbol, details~)
}

///|
fn Exporter::fact_at(
  self : Exporter,
  ctx : Context,
  kind : String,
  node : String,
  location : Json,
  ty : Int?,
  symbol : String?,
  details~ : Array[(String, Json)] = [],
) -> Unit {
  if kind == "declaration" && node == "constructor" && symbol is Some(symbol) {
    self.constructor_definitions[symbol] = true
  }
  self.facts.push(
    obj([
      ("id", num(self.facts.length())),
      ("package", str(ctx.view_key)),
      ("kind", str(kind)),
      ("node_kind", str(node)),
      ("location", location),
      ("type_id", nullable_id(ty)),
      ("symbol_id", nullable_symbol(symbol)),
      (
        "details",
        obj(
          [
            ("owner", str(ctx.owner)),
            ("generated_top_level", bool(ctx.generated)),
            ..details,
          ],
        ),
      ),
    ]),
  )
}

///|
fn Exporter::symbol(
  self : Exporter,
  kind : String,
  name : String,
  identity : Json,
) -> String {
  let key = identity.stringify()
  if self.symbol_ids.get(key) is Some(id) {
    return id
  }
  let id = "symbol:\{self.symbols.length()}"
  self.symbol_ids[key] = id
  self.symbols.push(
    obj([
      ("id", str(id)),
      ("kind", str(kind)),
      ("name", str(name)),
      ("identity", identity),
    ]),
  )
  id
}

///|
fn Exporter::builtin(self : Exporter, name : String) -> Int {
  if self.builtin_ids.get(name) is Some(id) {
    return id
  }
  let id = self.types.length()
  self.builtin_ids[name] = id
  let kind = if name == "StringView" || name == "BytesView" {
    "named"
  } else {
    "builtin"
  }
  let fields = [("id", num(id)), ("kind", str(kind)), ("name", str(name))]
  if kind == "named" {
    fields.push(("path", obj([("kind", str("builtin")), ("name", str(name))])))
    fields.push(("arguments", Json::array([])))
    fields.push(("named_kind", str("Normal")))
  }
  self.types.push(obj(fields))
  id
}

///|
fn select_name(
  names : Array[String],
  index : Int,
  context : String,
) -> String raise {
  guard names.get(index) is Some(name) else {
    raise Invalid("unknown \{context} code \{index}")
  }
  name
}
