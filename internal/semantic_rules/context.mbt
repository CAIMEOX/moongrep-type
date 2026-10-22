///|
priv suberror MissingEvidence {
  Unavailable(String)
}

///|
priv struct CheckContext {
  source : @semantic_source.Source
  facts_by_symbol : Map[String, Array[@semantic.Fact]]
  mutable_bindings : Map[@semantic.Range, Bool]
  previous : Map[(Int, Int), (@untyped_cst.CstNode, @untyped_cst.CstNode)]
}

///|
fn CheckContext::new(source : @semantic_source.Source) -> CheckContext raise {
  let facts_by_symbol : Map[String, Array[@semantic.Fact]] = Map([])
  for fact in source.facts(include_generated=false) {
    if fact.symbol_id is Some(id) {
      if facts_by_symbol.get(id) is Some(facts) {
        facts.push(fact)
      } else {
        facts_by_symbol[id] = [fact]
      }
    }
  }
  let context : CheckContext = {
    source,
    facts_by_symbol,
    mutable_bindings: Map([]),
    previous: Map([]),
  }
  let pending = [source.root()]
  while pending.pop() is Some(node) {
    if node.kind is Expr_LetMut && @cst.child(node, "pattern") is Some(pattern) {
      context.mutable_bindings[source.range_for_node(pattern)] = true
    }
    if node.kind is List_BlockStatementList {
      let statements = @cst.sequence_items(node)
      for i in 1..<statements.length() {
        if statement_call_syntax(statements[i]) is Some(call) {
          context.previous[call.source_span] = (
            statements[i - 1],
            statements[i],
          )
        }
      }
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  context
}

///|
fn CheckContext::facts(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Array[@semantic.Fact] raise {
  match authored_facts_for_node(self.source, node) {
    Associated(facts) => facts
    Unmatched =>
      raise Unavailable("No exact compiler facts in the selected package view.")
    Ambiguous(_) =>
      raise Unavailable("Ambiguous compiler facts; select one package view.")
  }
}

///|
fn CheckContext::expression(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> @semantic.Fact raise {
  let facts = source_expression_facts(self.facts(node))
  guard facts is [fact] else {
    raise Unavailable("No unique typed expression at this exact source range.")
  }
  fact
}

///|
fn CheckContext::shape(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Json raise {
  let fact = self.expression(node)
  guard fact.type_id.bind(id => type_shape(self.source.index(), id))
    is Some(shape) else {
    raise Unavailable("The expression type is unresolved or unsupported.")
  }
  shape
}

///|
fn CheckContext::symbol_id(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> String raise {
  let ids : Map[String, Bool] = Map([])
  for fact in self.facts(node) {
    if fact.symbol_id is Some(id) &&
      (
        fact.kind == "binding" ||
        fact.kind == "symbol_reference" ||
        (fact.kind == "expression" && fact.node_kind == "Texpr_ident")
      ) {
      ids[id] = true
    }
  }
  guard ids.length() == 1 else {
    raise Unavailable("No unique binding identity at this exact source range.")
  }
  for id, _ in ids {
    return id
  }
  abort("one symbol identity")
}

///|
fn CheckContext::method_is(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  owner : String,
  names : Array[String],
) -> Bool raise {
  let fact = self.expression(node)
  guard fact.node_kind == "Texpr_apply" &&
    fact.details
    is { "dispatch": "resolved_symbol", "callee_symbol_id": String(id), .. } &&
    fact.symbol_id == Some(id) &&
    self.source.index().symbol(id) is Some(symbol) else {
    return false
  }
  match symbol.identity {
    { "kind": "method", "name": String(name), "self_type": owner_type, .. } =>
      symbol.kind == "global" &&
      builtin_owner_is(owner_type, owner) &&
      names.contains(name)
    _ => false
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
fn CheckContext::builtin_value_call(
  self : CheckContext,
  node : @untyped_cst.CstNode,
  name : String,
) -> Bool raise {
  let fact = self.expression(node)
  guard fact.node_kind == "Texpr_apply" &&
    fact.symbol_id is Some(id) &&
    self.source.index().symbol(id) is Some(symbol) else {
    return false
  }
  match symbol.identity {
    {
      "kind": "value",
      "package": "moonbitlang/core/builtin",
      "name": String(found),
      ..
    } => symbol.kind == "global" && found == name
    _ => false
  }
}

///|
fn CheckContext::stable_identifier(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> Bool raise {
  guard node.kind is Expr_Ident else { return false }
  let id = self.symbol_id(node)
  guard self.source.index().symbol(id) is Some(symbol) else { return false }
  if symbol.kind == "global" {
    return true
  }
  guard symbol.kind == "local" && self.facts_by_symbol.get(id) is Some(facts) else {
    return false
  }
  let mut has_binding = false
  for fact in facts {
    if fact.kind == "binding" {
      has_binding = true
      if fact.location is Some(location) &&
        self.mutable_bindings.contains(location) {
        return false
      }
    }
  }
  has_binding
}

///|
fn CheckContext::uses_only_at(
  self : CheckContext,
  id : String,
  allowed : Array[@untyped_cst.CstNode],
) -> Bool raise {
  let ranges = allowed.map(node => self.source.range_for_node(node))
  guard self.facts_by_symbol.get(id) is Some(facts) else { return false }
  for fact in facts {
    if fact.location is Some(location) && !ranges.contains(location) {
      return false
    }
  }
  true
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
fn CheckContext::simple_callback(
  self : CheckContext,
  node : @untyped_cst.CstNode,
) -> (Json, Json)? raise {
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
