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
priv struct Catalog {
  types : TypeTable
  symbols : Map[String, @semantic.SymbolInfo]
  symbol_ids : Map[String, String]
  bindings : Map[String, @semantic.Range]
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
fn Catalog::source_for(self : Catalog, file : String) -> InputSource? {
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
    type_names: @lazy.Lazy::Lazy(() => {
      type_declarations(text, package_name, aliases)
    }),
  })
}

///|
fn definition_key(definition : Definition) -> String {
  "\{definition.file}:\{definition.range.start.line}:\{definition.range.start.column}:\{definition.range.end.line}:\{definition.range.end.column}"
}

///|
fn Catalog::symbol(self : Catalog, definition : Definition) -> String {
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
  if !self.symbols.contains(id) {
    let raw : Json = {
      "id": id,
      "kind": kind,
      "name": name,
      "identity": identity,
      "definition": {
        "file": definition.file,
        "range": ToJson::to_json(definition.range),
      },
    }
    self.symbols[id] = { id, kind, name, identity, raw, }
    if kind == "local" {
      self.bindings[id] = definition.source_range()
    }
  }
  self.symbol_ids[key] = id
  id
}
