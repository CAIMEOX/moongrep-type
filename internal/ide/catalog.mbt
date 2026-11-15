///|
priv struct Declaration {
  range : Span
  kind : String
  name : String
  identity : Json
  alias_name : String?
}

///|
fn syntax_span(loc : @basic.Location) -> Span {
  {
    start: { line: loc.start.lnum, column: loc.start.column(), },
    end: { line: loc.end.lnum, column: loc.end.column(), },
  }
}

///|
fn declaration_owner(name : @syntax.LongIdent, source : InputSource) -> Json? {
  let (pkg_alias, name) = name_parts(name)
  let package_name = if pkg_alias is Some(pkg_alias) {
    guard source_package(source, pkg_alias) is Some(package_name) else {
      return None
    }
    package_name
  } else {
    source.package_name
  }
  Some(package_type_path(package_name, name))
}

///|
fn declarations(source : InputSource) -> Array[Declaration] {
  let (items, reports) = @untyped_cst.parse_structure(
    source.text,
    name=source.path,
  ).to_impls()
  if !reports.is_empty() {
    return []
  }
  let result : Array[Declaration] = []
  for item in items {
    match item {
      TopFuncDef(fun_decl~, ..) => {
        let identity = if fun_decl.type_name is Some(owner) {
          guard declaration_owner(owner.name, source) is Some(path) else {
            continue
          }
          (
            { "kind": "method", "name": fun_decl.name.name, "self_type": path } :
            Json)
        } else {
          (
            {
              "kind": "value",
              "package": source.package_name,
              "name": fun_decl.name.name,
            } : Json)
        }
        result.push({
          range: syntax_span(fun_decl.name.loc),
          kind: "global",
          name: fun_decl.name.name,
          identity,
          alias_name: None,
        })
        for attribute in fun_decl.attrs {
          if attribute.parsed is Some(Apply(id, properties)) &&
            id.qual is None &&
            id.name == "alias" {
            for property in properties {
              if property is Expr(Ident(alias_id)) && alias_id.qual is None {
                result.push({
                  range: syntax_span(attribute.loc),
                  kind: "global",
                  name: fun_decl.name.name,
                  identity,
                  alias_name: Some(alias_id.name),
                })
              }
            }
          }
        }
      }
      TopLetDef(binder~, ..) =>
        result.push({
          range: syntax_span(binder.loc),
          kind: "global",
          name: binder.name,
          identity: {
            "kind": "value",
            "package": source.package_name,
            "name": binder.name,
          },
          alias_name: None,
        })
      TopTypeDef(ty) => {
        let constructors = match ty.components {
          Variant(constructors) | ExtensibleEnum(Some(constructors)) =>
            constructors
          _ => @list.List([])
        }
        guard declaration_owner(Ident(name=ty.tycon), source) is Some(owner) else {
          continue
        }
        for constructor_decl in constructors {
          result.push({
            range: syntax_span(constructor_decl.name.loc),
            kind: "constructor",
            name: constructor_decl.name.name,
            identity: {
              "kind": "constructor",
              "owner_type": owner,
              "name": constructor_decl.name.name,
            },
            alias_name: None,
          })
        }
      }
      TopUsing(pkg~, names~, ..) => {
        guard source.aliases.get(pkg.name) is Some(target_package) else {
          continue
        }
        for (target, kind) in names {
          guard kind is Value && target.target is None else { continue }
          result.push({
            range: syntax_span(target.binder.loc),
            kind: "global",
            name: target.binder.name,
            identity: {
              "kind": "value",
              "package": target_package,
              "name": target.binder.name,
            },
            alias_name: None,
          })
        }
      }
      _ => ()
    }
  }
  result
}

///|
priv struct Builder {
  types : TypeTable
  symbols : Array[Json]
  symbol_ids : Map[String, String]
  facts : Array[Json]
  documents : Map[String, String]
  catalogs : Map[String, Array[Declaration]]
  packages : Map[String, String]
  sources : Map[String, InputSource]
}

///|
fn inside(directory : String, file : String) -> Bool {
  file == directory ||
  file.has_prefix(directory + "/") ||
  file.has_prefix(directory + "\\")
}

///|
fn Builder::source_for(self : Builder, file : String) -> InputSource? {
  if self.sources.get(file) is Some(source) {
    return Some(source)
  }
  guard self.documents.get(file) is Some(text) else { return None }
  let mut matched = ""
  let mut package_name = ""
  for root, name in self.packages {
    if inside(root, file) && root.length() > matched.length() {
      matched = root
      package_name = name
    }
  }
  if matched.is_empty() {
    return None
  }
  let aliases : Map[String, String] = Map([])
  if package_name.has_prefix("moonbitlang/core/") {
    for _, imported in self.packages {
      if imported.has_prefix("moonbitlang/core/") {
        let segments = imported.split("/").to_array()
        aliases[segments[segments.length() - 1].to_owned()] = imported
      }
    }
  }
  Some({
    path: file,
    text,
    package_name,
    aliases,
    type_names: type_declarations(text, package_name, aliases),
  })
}

///|
fn definition_key(definition : Definition) -> String {
  "\{definition.file}:\{definition.range.start.line}:\{definition.range.start.column}:\{definition.range.end.line}:\{definition.range.end.column}"
}

///|
fn Builder::symbol(self : Builder, definition : Definition) -> String {
  let key = definition_key(definition)
  if self.symbol_ids.get(key) is Some(id) {
    return id
  }
  let declarations = if self.catalogs.get(definition.file) is Some(items) {
    items
  } else {
    let items = self.source_for(definition.file).map(declarations).unwrap_or([])
    self.catalogs[definition.file] = items
    items
  }
  let found = declarations
    .iter()
    .find_first(item => {
      if item.alias_name is None {
        return item.range == definition.range
      }
      guard item.alias_name is Some(name) &&
        definition.range.start.line == definition.range.end.line &&
        item.range.start.line == definition.range.start.line &&
        item.range.end.line == definition.range.end.line &&
        item.range.start.column <= definition.range.start.column &&
        item.range.end.column >= definition.range.end.column &&
        self.documents.get(definition.file) is Some(text) else {
        return false
      }
      let chars = source_lines(text)[definition.range.start.line - 1]
      chars[definition.range.start.column - 1:definition.range.end.column - 1]
      .map(char => char.to_string())
      .join("") ==
      name
    })
  let (kind, name, identity) = if found is Some(item) {
    (item.kind, item.name, item.identity)
  } else {
    let name = if self.documents.get(definition.file) is Some(text) &&
      definition.range.start.line == definition.range.end.line {
      source_lines(text)[definition.range.start.line - 1][definition.range.start.column -
      1:definition.range.end.column - 1]
      .map(char => char.to_string())
      .join("")
    } else {
      ""
    }
    (
      "local",
      name,
      (
        {
          "kind": "local",
          "definition": {
            "file": definition.file,
            "range": ToJson::to_json(definition.range),
          },
        } : Json),
    )
  }
  let id = if kind == "local" {
    "definition:" + key
  } else {
    "symbol:" + identity.stringify()
  }
  if self.symbols.any(symbol => {
      symbol is { "id": String(found), .. } && found == id
    }) {
    self.symbol_ids[key] = id
    return id
  }
  self.symbols.push({
    "id": id,
    "kind": kind,
    "name": name,
    "identity": identity,
    "definition": {
      "file": definition.file,
      "range": ToJson::to_json(definition.range),
    },
  })
  self.symbol_ids[key] = id
  id
}

///|
fn Builder::add_fact(
  self : Builder,
  query : Query,
  source : InputSource,
  backend : String,
  ty : Int32?,
  symbol : String?,
  details : Json,
) -> Unit {
  self.facts.push({
    "id": self.facts.length(),
    "package": "\{source.package_name}@\{backend}:ide",
    "kind": query.role,
    "node_kind": query.node_kind,
    "location": {
      "file": query.file,
      "start": ToJson::to_json(query.range.start),
      "end": ToJson::to_json(query.range.end),
    },
    "type_id": ty.map(id => Json(id)).unwrap_or(Json::null()),
    "symbol_id": symbol.map(Json::string).unwrap_or(Json::null()),
    "details": details,
  })
}

///|
async fn Builder::query(
  self : Builder,
  client : Client,
  query : Query,
  backend : String,
) -> Unit {
  let source = self.sources.get(query.file).unwrap()
  let definitions = if query.definition {
    client.definitions(query.file, query.anchor.start, self.documents)
  } else {
    []
  }
  let mut definition : Definition? = None
  let ids : Map[String, Bool] = Map([])
  for candidate in definitions {
    ids[self.symbol(candidate)] = true
    definition = Some(candidate)
  }
  if ids.length() > 1 {
    definition = None
  }
  // A binder is an authored declaration. Referencing occurrences are admitted
  // only through the official definition response, including shadowing.
  let definition = if definition is None &&
    (query.role == "binding" || query.node_kind == "variable_pattern") {
    Some({ file: query.file, range: query.range, })
  } else {
    definition
  }
  let symbol = definition.map(value => self.symbol(value))
  let mut ty : Int32? = if query.node_kind == "is" {
    // `is` is a non-overloadable Bool-valued language form. The project has
    // already passed moon check; no generic instantiation is inferred here.
    Some(self.types.intern({ "kind": "builtin", "name": "Bool" }))
  } else {
    None
  }
  let mut hover_text = ""
  for point in hover_points(query) {
    if ty is Some(_) {
      break
    }
    if client.hover(query.file, point) is Some((text, found)) &&
      (
        found == query.range ||
        (
          (
            query.node_kind == "constructor" ||
            query.node_kind == "field" ||
            query.role == "binding"
          ) &&
          found == query.anchor
        )
      ) {
      hover_text = text
      let signature_owner = definition.map(definition_key)
      let global_signature = symbol is Some(id) &&
        self.symbols.any(s => {
          s is { "id": String(found), "kind": "global", .. } && found == id
        })
      ty = self.types.parse(
        text,
        source,
        query.owner,
        query.parameters,
        signature_owner~,
        global_signature~,
      )
      break
    }
  }
  if ty is None &&
    query.node_kind == "operator" &&
    client.hover(query.file, query.anchor.start) is Some((text, found)) &&
    found == query.anchor &&
    self.types.parse(text, source, query.owner, query.parameters) is Some(arrow) &&
    self.types.values[arrow]
    is { "kind": "function", "return_type": Number(id, ..), .. } &&
    !(self.types.values[arrow] is { "polymorphic": true, .. }) {
    ty = Some(id.to_int())
    hover_text = text
  }
  // Definitions and types are independent evidence. An unavailable type must
  // never be fabricated from a method name or an enclosing hover.
  let details : Json = if query.node_kind == "call" {
    {
      "provider": "moon-ide",
      "generated_top_level": false,
      "owner": query.owner,
      "callee_symbol_id": symbol.map(Json::string).unwrap_or(Json::null()),
      "dispatch": if symbol is Some(id) &&
        self.symbols.any(s => {
          s is { "id": String(found), "kind": "global", .. } && found == id
        }) {
        "resolved_symbol"
      } else if symbol is Some(_) {
        "binding"
      } else {
        "unavailable"
      },
      "hover": hover_text,
    }
  } else {
    {
      "provider": "moon-ide",
      "generated_top_level": false,
      "owner": query.owner,
      "hover": hover_text,
    }
  }
  self.add_fact(query, source, backend, ty, symbol, details)
}
