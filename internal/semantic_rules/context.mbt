///|
priv suberror MissingEvidence {
  Unavailable(String)
}

///|
priv struct CheckContext {
  file : String
  text : String
  package_name : async () -> String
  shape_at : async (@untyped_cst.CstNode) -> Json?
  is_tuple_at : async (@untyped_cst.CstNode, Int32) -> Bool?
  call_header_at : async (@untyped_cst.CstNode) -> (String, Int32)?
  symbol_at : async (@untyped_cst.CstNode) -> @semantic.SymbolInfo?
  exports_method : async (@semantic.SymbolInfo, String, String, String, Int32) -> Bool
  binding : async (String) -> @semantic.Range?
  references : async (@untyped_cst.CstNode) -> Array[@semantic.Range]
  binders : Map[@semantic.Range, Bool]
  local_callbacks : Set[@semantic.Position]
  finite_oracles : Map[(Int32, Int32), String]
  sum_uses : Map[(Int32, Int32), @untyped_cst.CstNode]
  previous : Map[(Int32, Int32), (@untyped_cst.CstNode, @untyped_cst.CstNode)]
}

///|
fn CheckContext::inspect_syntax(
  self : CheckContext,
  root : @untyped_cst.CstNode,
  finite_checks~ : Bool = false,
) -> Unit {
  for declaration in @cst.toplevel_nodes(root) {
    self.record_local_callbacks(declaration)
  }
  let pending = [root]
  while pending.pop() is Some(node) {
    if finite_checks {
      self.record_finite_comparison(node)
    }
    self.record_sum_use(node)
    if node.kind is Name_Binder {
      let location = self.range(node)
      if !self.binders.contains(location) {
        self.binders[location] = false
      }
    }
    if node.kind is Expr_LetMut && @cst.child(node, "pattern") is Some(pattern) {
      self.binders[self.range(pattern)] = true
    }
    if node.kind is List_BlockStatementList {
      let statements = @cst.sequence_items(node)
      for i in 1..<statements.length() {
        if statement_call_syntax(statements[i]) is Some(call) {
          self.previous[call.source_span] = (statements[i - 1], statements[i])
        }
      }
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
}

///|
fn CheckContext::range(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> @semantic.Range {
  node_range(self.file, node)
}

///|
fn node_range(file : String, node : @untyped_cst.CstNode) -> @semantic.Range {
  {
    file,
    start: { line: node.loc.start.lnum, column: node.loc.start.column(), },
    end: { line: node.loc.end.lnum, column: node.loc.end.column(), },
  }
}

///|
async fn CheckContext::shape(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Json {
  guard (self.shape_at)(node) is Some(shape) else {
    raise Unavailable("The expression type is unresolved or unsupported.")
  }
  shape
}

///|
async fn CheckContext::symbol_id(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> String {
  guard (self.symbol_at)(node) is Some(symbol) else {
    raise Unavailable("No unique binding identity at this exact source range.")
  }
  symbol.id
}

///|
async fn CheckContext::method_is(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
  names : Array[String],
) -> Bool {
  guard (self.symbol_at)(node) is Some(symbol) else {
    raise Unavailable("The IDE did not resolve a unique callable definition.")
  }
  guard symbol.kind == "global" &&
    symbol.identity
    is { "kind": "method", "name": String(name), "self_type": path, .. } else {
    return false
  }
  builtin_owner_is(path, owner) && names.contains(name)
}

///|
async fn CheckContext::core_trait_method(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  trait_name : String,
  method_name : String,
) -> @semantic.SymbolInfo? {
  guard (self.symbol_at)(node) is Some(symbol) else {
    raise Unavailable("The IDE could not resolve the operator definition.")
  }
  if symbol.kind == "global" &&
    symbol.identity
    is {
      "kind": "trait_impl",
      "package": "moonbitlang/core/builtin",
      "trait": tr,
      "name": String(found),
      ..
    } &&
    found == method_name &&
    builtin_owner_is(tr, trait_name) {
    Some(symbol)
  } else {
    None
  }
}

///|
fn builtin_owner_is(path : Json, owner : String) -> Bool {
  match path {
    {
      "kind": "named",
      "package": "moonbitlang/core/builtin",
      "name": String(name),
      ..
    }
    | { "kind": "builtin", "name": String(name), .. } => name == owner
    _ => false
  }
}

///|
async fn CheckContext::builtin_value_call(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  name : String,
) -> Bool {
  guard (self.symbol_at)(node) is Some(symbol) else {
    raise Unavailable("The IDE did not resolve a unique callable definition.")
  }
  symbol.kind == "global" &&
  symbol.identity
  is {
    "kind": "value",
    "package": "moonbitlang/core/builtin",
    "name": String(found),
    ..
  } &&
  name == found
}

///|
async fn CheckContext::stable_identifier(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool {
  guard node.kind is Expr_Ident && (self.symbol_at)(node) is Some(symbol) else {
    return false
  }
  if symbol.kind == "global" {
    return true
  }
  symbol.kind == "local" &&
  (self.binding)(symbol.id) is Some(location) &&
  self.binders.get(location) == Some(false)
}

///|
async fn CheckContext::uses_only_at(
  self : CheckContext,
  binder : @untyped_cst.CstNode,
  allowed : Array[@untyped_cst.CstNode],
) -> Bool {
  let ranges = allowed.map(node => self.range(node))
  let uses = (self.references)(binder)
  uses.all(loc => ranges.contains(loc)) &&
  ranges.all(loc => loc == self.range(binder) || uses.contains(loc))
}

///|
fn container_element(shape : Json, name : String) -> Json? {
  match shape {
    {
      "kind": "named",
      "named_kind": "Normal",
      "arguments": [element],
      "path": {
        "kind": "named",
        "package": "moonbitlang/core/builtin",
        "name": String(found),
        ..
      },
      ..
    } if found == name => Some(element)
    _ => None
  }
}

///|
fn no_abrupt_control(node : @untyped_cst.CstNode) -> Bool {
  let pending = [node]
  while pending.pop() is Some(current) {
    match current.kind {
      Expr_Return
      | Expr_Break
      | Expr_Continue
      | Expr_Raise
      | Expr_Defer
      | Expr_LetMut
      | Expr_ForEach
      | Expr_For
      | Expr_While => return false
      _ => ()
    }
    for (_, child) in current.children {
      pending.push(child)
    }
  }
  true
}

///|
async fn CheckContext::simple_callback(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> (Json, Json)? {
  guard callback_arrow(self.shape(node)) is Some(arrow) else { return None }
  if node.kind is Expr_Function {
    if no_abrupt_control(node) {
      Some(arrow)
    } else {
      None
    }
  } else if self.stable_identifier(node) {
    Some(arrow)
  } else {
    None
  }
}
