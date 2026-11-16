///|
priv struct TypeVariable {
  owner : String
  index : Int32
}

///|
priv struct TypeScope {
  owner : String
  variables : Map[String, TypeVariable]
}

///|
fn TypeScope::new(owner : String, parameters : Map[String, Int32]) -> TypeScope {
  let variables : Map[String, TypeVariable] = Map([])
  for name, position in parameters {
    variables[name] = { owner, index: position, }
  }
  { owner, variables, }
}

///|
priv struct TypeTable {
  values : Array[Json]
  ids : Map[String, Int32]
}

///|
fn TypeTable::new() -> TypeTable {
  { values: [], ids: Map([]), }
}

///|
fn TypeTable::intern(self : TypeTable, value : Json) -> Int32 {
  let key = value.stringify()
  if self.ids.get(key) is Some(id) {
    return id
  }
  let id = self.values.length()
  guard value is Object(fields) else { abort("structured type") }
  let result = fields.copy()
  result["id"] = Json(id)
  self.values.push(Json::object(result))
  self.ids[key] = id
  id
}

///|
fn name_parts(name : @syntax.LongIdent) -> (String?, String) {
  match name {
    Ident(name~) => (None, name)
    Dot(pkg~, id~) => (Some(pkg), id)
  }
}

///|
fn source_package(source : InputSource, pkg_alias : String) -> String? {
  if source.aliases.get(pkg_alias) is Some(package_name) {
    return Some(package_name)
  }
  if pkg_alias == source.package_name ||
    pkg_alias == "moonbitlang/core/builtin" ||
    source.aliases.values().any(package_name => package_name == pkg_alias) {
    Some(pkg_alias)
  } else {
    None
  }
}

///|
fn package_type_path(package_name : String, name : String) -> Json {
  if package_name == "moonbitlang/core/builtin" &&
    ["Option", "Result", "FixedArray"].contains(name) {
    { "kind": "builtin", "name": name }
  } else {
    { "kind": "named", "package": package_name, "name": name }
  }
}

///|
fn nominal_path(name : @syntax.LongIdent, source : InputSource) -> Json? {
  let (pkg_alias, name) = name_parts(name)
  if pkg_alias is Some(pkg_alias) {
    guard source_package(source, pkg_alias) is Some(package_name) else {
      return None
    }
    return Some(package_type_path(package_name, name))
  }
  if source.type_names.force().get(name) is Some(path) {
    return Some(path)
  }
  if ["Option", "Result", "FixedArray"].contains(name) {
    Some({ "kind": "builtin", "name": name })
  } else if [
      "Array", "ArrayView", "ReadOnlyArray", "Iter", "Iter2", "StringView", "BytesView",
      "Ref", "Eq", "Compare", "Hash", "Show", "Default",
    ].contains(name) {
    Some({
      "kind": "named",
      "package": "moonbitlang/core/builtin",
      "name": name,
    })
  } else {
    None
  }
}

///|
fn TypeTable::convert(
  self : TypeTable,
  ty : @syntax.Type,
  source : InputSource,
  scope : TypeScope,
) -> Int32? {
  match ty {
    Any(..) => None
    Name(constr_id~, tys~, ..) => {
      let (pkg_alias, name) = name_parts(constr_id.id)
      if pkg_alias is None && scope.variables.get(name) is Some(variable) {
        return Some(
          self.intern({
            "kind": "parameter",
            "owner": variable.owner,
            "index": variable.index,
            "name": name,
          }),
        )
      }
      let builtin_scope = if pkg_alias is Some(pkg_alias) {
        source_package(source, pkg_alias) == Some("moonbitlang/core/builtin")
      } else {
        !source.type_names.force().contains(name)
      }
      let normalized = match name {
        "Int32" => "Int"
        "UInt32" => "UInt"
        _ => name
      }
      if builtin_scope &&
        [
          "Unit", "Bool", "Byte", "Char", "Int", "UInt", "Int16", "UInt16", "Int64",
          "UInt64", "Float", "Double", "String", "Bytes", "V128", "Error",
        ].contains(normalized) {
        return Some(self.intern({ "kind": "builtin", "name": normalized }))
      }
      guard nominal_path(constr_id.id, source) is Some(path) else {
        return None
      }
      let arguments : Array[Json] = []
      for ty in tys {
        guard self.convert(ty, source, scope) is Some(id) else { return None }
        arguments.push(Json(id))
      }
      Some(
        self.intern({
          "kind": "named",
          "path": path,
          "arguments": arguments,
          "named_kind": "Normal",
        }),
      )
    }
    Option(ty~, ..) => {
      guard self.convert(ty, source, scope) is Some(id) else { return None }
      Some(
        self.intern({
          "kind": "named",
          "path": { "kind": "builtin", "name": "Option" },
          "arguments": [id],
          "named_kind": "Normal",
        }),
      )
    }
    Tuple(tys~, ..) => {
      let arguments : Array[Json] = []
      for ty in tys {
        guard self.convert(ty, source, scope) is Some(id) else { return None }
        arguments.push(Json(id))
      }
      Some(
        self.intern({
          "kind": "named",
          "path": { "kind": "tuple", "arity": arguments.length() },
          "arguments": arguments,
          "named_kind": "Normal",
        }),
      )
    }
    Object(name) => {
      guard nominal_path(name.id, source) is Some(path) else { return None }
      Some(self.intern({ "kind": "trait_object", "path": path }))
    }
    Arrow(args~, res~, err~, is_async~, nocancel_~, ..) => {
      let inputs : Array[Json] = []
      for arg in args {
        guard self.convert(arg, source, scope) is Some(id) else { return None }
        inputs.push(Json(id))
      }
      guard self.convert(res, source, scope) is Some(output) &&
        self.error_type(err, source, scope) is Some(error_type) else {
        return None
      }
      Some(
        self.intern({
          "kind": "function",
          "parameters": inputs,
          "return_type": output,
          "error": error_type,
          "async": if is_async is None {
            "sync"
          } else if nocancel_ is Some(_) {
            "async_nocancel"
          } else {
            "async"
          },
        }),
      )
    }
  }
}

///|
/// Local declarations and explicit type imports take precedence over prelude
/// names. The map is shared by all files in the checked file context.
fn type_declarations(
  text : String,
  package_name : String,
  aliases : Map[String, String],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  let (items, reports) = @untyped_cst.parse_structure(text).to_impls()
  if !reports.is_empty() {
    return result
  }
  for item in items {
    match item {
      TopTypeDef(decl) =>
        result[decl.tycon] = package_type_path(package_name, decl.tycon)
      TopUsing(pkg~, names~, ..) =>
        if aliases.get(pkg.name) is Some(imported) {
          for (alias_target, kind) in names {
            if kind is (Type | Trait) {
              result[alias_target.binder.name] = package_type_path(
                imported,
                alias_target.target
                .map(target => target.name)
                .unwrap_or(alias_target.binder.name),
              )
            }
          }
        }
      _ => ()
    }
  }
  result
}

///|
fn TypeTable::error_type(
  self : TypeTable,
  error : @syntax.ErrorType,
  source : InputSource,
  scope : TypeScope,
) -> Json? {
  match error {
    NoErrorType | Noraise(..) => Some({ "kind": "none" })
    DefaultErrorType(..) =>
      Some({
        "kind": "typed",
        "type_id": self.intern({ "kind": "builtin", "name": "Error" }),
      })
    ErrorType(ty~) =>
      self
      .convert(ty, source, scope)
      .map(id => { "kind": "typed", "type_id": id })
    MaybeError(..) => Some({ "kind": "parameter", "owner": scope.owner })
  }
}

///|
/// Parse the language syntax printed by the official hover provider. Unsupported
/// types remain unavailable; display strings are never compared as types.
fn TypeTable::parse(
  self : TypeTable,
  text : String,
  source : InputSource,
  owner : String,
  parameters : Map[String, Int32],
  signature_owner~ : String? = None,
  global_signature~ : Bool = false,
) -> Int32? {
  let root_scope = TypeScope::new(owner, parameters)
  if text.has_prefix("fn") ||
    text.has_prefix("async fn") ||
    text.has_prefix("pub fn") {
    let declaration = if text.has_prefix("pub ") { text } else { "pub " + text }
    let parsed = @untyped_cst.parse_structure(
      declaration + " { abort(\"type signature\") }",
    )
    guard parsed.diagnostics_view().is_empty() else { return None }
    let (impls, reports) = parsed.to_impls()
    guard reports.is_empty() else { return None }
    for item in impls {
      if item is TopFuncDef(fun_decl~, ..) {
        guard fun_decl.decl_params is Some(params) &&
          fun_decl.return_type is Some(result) else {
          return None
        }
        let scope_owner = signature_owner.unwrap_or(owner)
        let variables = if global_signature {
          Map([])
        } else {
          root_scope.variables.copy()
        }
        let scope : TypeScope = { owner: scope_owner, variables, }
        for position, parameter in fun_decl.quantifiers.iter() {
          variables[parameter.name] = { owner: scope_owner, index: position, }
        }
        let args = []
        for param in params {
          match param {
            Positional(ty=Some(ty), ..) | DiscardPositional(ty=Some(ty), ..) =>
              args.push(ty)
            _ => return None
          }
        }
        guard self.convert(
            Arrow(
              args=@list.List([..args]),
              res=result,
              err=fun_decl.error_type,
              is_async=fun_decl.is_async,
              nocancel_=fun_decl.nocancel_,
              loc=fun_decl.loc,
            ),
            source,
            scope,
          )
          is Some(id) else {
          return None
        }
        if fun_decl.quantifiers.is_empty() {
          return Some(id)
        }
        guard self.values[id] is Object(fields) else { return None }
        let scheme = fields.copy()
        ignore(scheme.remove("id"))
        scheme["polymorphic"] = true
        return Some(self.intern(Json::object(scheme)))
      }
    }
    return None
  }
  let parsed = @untyped_cst.parse_expression("(_ : " + text + ")")
  guard parsed.diagnostics_view().is_empty() else { return None }
  let (expr, reports) = parsed.to_expr()
  guard reports.is_empty() && expr is Some(expr) else { return None }
  let expr = match expr {
    Group(expr~, ..) => expr
    _ => expr
  }
  guard expr is Constraint(ty~, ..) else { return None }
  self.convert(ty, source, root_scope)
}
