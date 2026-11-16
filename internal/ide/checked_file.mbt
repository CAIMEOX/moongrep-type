///|
pub struct CheckedFile {
  priv project : CheckedProject
  priv input : InputSource
  priv declarations : Array[@untyped_cst.CstNode]
  priv scopes : Map[(Int32, Int32), Scope]
}

///|
fn Definition::source_range(self : Definition) -> @semantic.Range {
  {
    file: self.file,
    start: { line: self.range.start.line, column: self.range.start.column, },
    end: { line: self.range.end.line, column: self.range.end.column, },
  }
}

///|
pub fn CheckedFile::path(self : CheckedFile) -> String {
  self.input.path
}

///|
pub fn CheckedFile::package_name(self : CheckedFile) -> String {
  "\{self.input.package_name}@\{self.project.client.backend}:ide"
}

///|
pub fn CheckedFile::raw_type(self : CheckedFile, id : Int32) -> Json? {
  self.project.catalog.types.values.get(id)
}

///|
pub fn CheckedFile::binding(
  self : CheckedFile,
  id : String,
) -> @semantic.Range? {
  self.project.catalog.bindings.get(id)
}

///|
fn CheckedFile::scope(
  self : CheckedFile,
  node : @untyped_cst.CstNode,
) -> Scope raise {
  for root in self.declarations {
    if root.source_span.0 <= node.source_span.0 &&
      node.source_span.1 <= root.source_span.1 {
      if self.scopes.get(root.source_span) is Some(scope) {
        return scope
      }
      let scope = declaration_scope(self.input, root)
      self.scopes[root.source_span] = scope
      return scope
    }
  }
  fail("IDE position has no enclosing declaration in \{self.input.path}")
}

///|
pub async fn CheckedFile::symbol_at(
  self : CheckedFile,
  node : @untyped_cst.CstNode,
) -> @semantic.SymbolInfo? {
  let catalog = self.project.catalog
  if node.kind is (Name_Binder | Pattern_Var) {
    return catalog.symbols.get(
      catalog.symbol({ file: self.input.path, range: span(node), }),
    )
  }
  let defs = self.project.client.locations(
    self.input.path,
    span(query_anchor(node)).start,
    catalog.documents,
  )
  let mut unique : String? = None
  for definition in defs {
    let id = catalog.symbol(definition)
    if unique is Some(previous) && previous != id {
      return None
    }
    unique = Some(id)
  }
  unique.bind(id => catalog.symbols.get(id))
}

///|
pub async fn CheckedFile::type_at(
  self : CheckedFile,
  node : @untyped_cst.CstNode,
) -> Int32? {
  let catalog = self.project.catalog
  // This language form has a fixed result after a successful check.
  if node.kind is Expr_Is {
    return Some(catalog.types.intern({ "kind": "builtin", "name": "Bool" }))
  }
  let scope = self.scope(node)
  let range = span(node)
  let anchor = span(query_anchor(node))
  if node.kind is (Expr_Infix | Expr_Unary) {
    guard self.project.client.hover(self.path(), anchor.start)
      is Some((text, found)) &&
      found == anchor &&
      catalog.types.parse(text, self.input, scope.owner, scope.parameters)
      is Some(id) &&
      catalog.types.values[id]
      is { "kind": "function", "return_type": Number(result, ..), .. } &&
      !(catalog.types.values[id] is { "polymorphic": true, .. }) else {
      return None
    }
    return Some(result.to_int())
  }
  let member_anchor = node.kind is (Expr_Constr | Expr_Field | Name_Binder)
  let points = if member_anchor || node.kind is Expr_Function {
    [range.end, anchor.start]
  } else {
    [range.end]
  }
  for point in points {
    if self.project.client.hover(self.path(), point) is Some((text, found)) &&
      (found == range || (member_anchor && found == anchor)) {
      // A declaration signature can bind type variables in a different scope.
      let symbol = if text.has_prefix("fn") ||
        text.has_prefix("async fn") ||
        text.has_prefix("pub fn") {
        self.symbol_at(node)
      } else {
        None
      }
      return catalog.types.parse(
        text,
        self.input,
        scope.owner,
        scope.parameters,
        signature_owner=symbol.map(s => s.id),
        global_signature=symbol is Some(s) && s.kind == "global",
      )
    }
  }
  None
}

///|
/// Ask the compiler for all occurrences only for rules proving exclusive use.
pub async fn CheckedFile::references(
  self : CheckedFile,
  binder : @untyped_cst.CstNode,
) -> Array[@semantic.Range] {
  self.project.client
  .locations(
    self.path(),
    span(binder).start,
    self.project.catalog.documents,
    command="find-references",
  )
  .map(Definition::source_range)
}
