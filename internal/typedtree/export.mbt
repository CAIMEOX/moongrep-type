///|
pub fn extract(
  compiler_version : String,
  sources : Array[Source],
  packages : Array[Package],
) -> Json raise {
  if compiler_version != "v0.10.14+7080b3792-nightly (2026-10-10)" {
    raise Invalid("unverified compiler version: \{compiler_version}")
  }
  let source_map : Map[String, String] = Map([])
  for source in sources {
    if source_map.contains(source.path) {
      raise Invalid("duplicate source file")
    }
    source_map[source.path] = source.text
  }
  let types : Array[Json] = []
  let type_ids : Map[(String, Int), Int] = Map([])
  let builtin_ids : Map[String, Int] = Map([])
  let symbols : Array[Json] = []
  let symbol_ids : Map[String, String] = Map([])
  let facts : Array[Json] = []
  for input_package in packages {
    let graph = @marshal.decode(input_package.artifact)
    let wire : Wire = { graph, }
    let self : Exporter = {
      wire,
      sources: source_map,
      source_aliases: Map::from_array(input_package.source_aliases),
      types,
      type_ids,
      builtin_ids,
      symbols,
      symbol_ids,
      facts,
      type_env: Map([]),
      global_values: Map([]),
      constructors: [],
      constructor_definitions: Map([]),
      active: Map([]),
      pending: [],
    }
    for (_, target) in input_package.source_aliases {
      if !source_map.contains(target) {
        raise Invalid("source alias refers to missing source")
      }
    }
    let root = wire.record(graph.root(), 7)
    self.load_type_environment(root[1])
    self.load_value_environment(root[2])
    let output = wire.record(root[0], 2)
    let ctx : Context = {
      view_key: input_package.key,
      pkg_name: input_package.name,
      root: input_package.source_root,
      owner: input_package.key,
      file: "",
      base_line: -1,
      generated: false,
      origin_known: true,
      parent_type: None,
      parent_semtype: None,
      field_position: -1,
    }
    self.enqueue("*decl", output[1], ctx)
    self.enqueue("*impl", output[0], ctx)
    while self.pending.pop() is Some((kind, id, context)) {
      self.step(kind, id, context)
    }
    self.implicit_constructors(ctx)
  }
  obj([
    ("schema_version", num(1)),
    ("compiler_version", str(compiler_version)),
    ("position_encoding", str("unicode-scalar")),
    (
      "sources",
      Json::array(
        sources.map(source => {
          obj([("path", str(source.path)), ("text", str(source.text))])
        }),
      ),
    ),
    ("types", Json::array(types)),
    ("symbols", Json::array(symbols)),
    ("facts", Json::array(facts)),
  ])
}
