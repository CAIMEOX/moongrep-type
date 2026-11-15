///|
priv struct InputSource {
  path : String
  text : String
  package_name : String
  aliases : Map[String, String]
  type_names : Map[String, Json]
}

///|
#derive(ToJson, Eq)
priv struct Point {
  line : Int32
  column : Int32
}

///|
#derive(ToJson, Eq)
priv struct Span {
  start : Point
  end : Point
}

///|
priv struct Query {
  file : String
  range : Span
  anchor : Span
  role : String
  node_kind : String
  owner : String
  parameters : Map[String, Int32]
  definition : Bool
}

///|
priv struct Plan {
  queries : Array[Query]
}

///|
fn span(node : @untyped_cst.CstNode) -> Span {
  {
    start: { line: node.loc.start.lnum, column: node.loc.start.column(), },
    end: { line: node.loc.end.lnum, column: node.loc.end.column(), },
  }
}

///|
fn contains_call(root : @untyped_cst.CstNode) -> Bool {
  let pending = [root]
  while pending.pop() is Some(node) {
    if node.kind is (Expr_DotApply | Expr_Apply | Expr_ForEach) {
      return true
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  false
}

///|
fn node_role(node : @untyped_cst.CstNode) -> (String, String)? {
  match node.kind {
    Expr_DotApply | Expr_Apply => Some(("expression", "call"))
    Expr_Ident => Some(("expression", "identifier"))
    Expr_Constr => Some(("expression", "constructor"))
    Expr_Function => Some(("expression", "function"))
    Expr_Is => Some(("expression", "is"))
    Expr_Infix | Expr_Unary => Some(("expression", "operator"))
    Expr_Field => Some(("expression", "field"))
    Pattern_Constr => Some(("pattern", "constructor_pattern"))
    Pattern_Var => Some(("pattern", "variable_pattern"))
    Name_Binder => Some(("binding", "binder"))
    Expr_Block | Expr_Sequence | Expr_Group => None
    _ =>
      if "\{Repr(node.kind)}".has_prefix("Expr_") {
        Some(("expression", "value"))
      } else {
        None
      }
  }
}

///|
fn query_anchor(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  match node.kind {
    Expr_DotApply => @cst.child(node, "field").unwrap_or(node)
    Expr_Function | Expr_Infix | Expr_Unary =>
      @cst.raw_child(node, "op").unwrap_or(node)
    Expr_Field => @cst.raw_child(node, "field").unwrap_or(node)
    Expr_Apply => query_anchor(@cst.child(node, "func").unwrap_or(node))
    Expr_Constr | Pattern_Constr => {
      let names = @cst.raw_children(node, "name")
      @cst.raw_child(node, "field").unwrap_or(
        names.get(names.length() - 1).unwrap_or(node),
      )
    }
    _ => node
  }
}

///|
/// Enumerate authored syntax using MoonGrep's parser. No compiler artifact or
/// generated derive body is traversed. Positions remain Unicode scalar columns.
fn plan(sources : Array[InputSource]) -> Plan raise {
  let queries = []
  for source in sources {
    let parsed = @untyped_cst.parse_structure(source.text, name=source.path)
    if !parsed.diagnostics_view().is_empty() ||
      @cst.first_recovery_node(parsed.root()) is Some(_) {
      fail("cannot parse IDE source: \{source.path}")
    }
    for root in @cst.toplevel_nodes(parsed.root()) {
      if !contains_call(root) {
        continue
      }
      let owner = "\{source.path}:\{root.loc.start.lnum}:\{root.loc.start.column()}"
      let parameters : Map[String, Int32] = Map([])
      // Bind generic names to this authored declaration's scope.
      let (impls, reports) = @untyped_cst.parse_structure(
        @cst.source_text(root, source.text),
      ).to_impls()
      if reports.is_empty() {
        for item in impls {
          match item {
            TopFuncDef(fun_decl~, ..) =>
              for parameter in fun_decl.quantifiers {
                parameters[parameter.name] = parameters.length()
              }
            TopImpl(quantifiers~, method_quantifiers~, ..) => {
              for parameter in quantifiers {
                parameters[parameter.name] = parameters.length()
              }
              for parameter in method_quantifiers {
                parameters[parameter.name] = parameters.length()
              }
            }
            _ => ()
          }
        }
      }
      let pending = [root]
      while pending.pop() is Some(node) {
        if node_role(node) is Some((role, node_kind)) {
          let anchor = query_anchor(node)
          queries.push({
            file: source.path,
            range: span(node),
            anchor: span(anchor),
            role,
            node_kind,
            owner,
            parameters,
            definition: node_kind == "call" ||
            node_kind == "identifier" ||
            node_kind == "constructor" ||
            node_kind == "constructor_pattern",
          })
        }
        // Reverse push preserves lexical source traversal.
        for i = node.children.length() - 1; i >= 0; i = i - 1 {
          pending.push(node.children[i].1)
        }
      }
    }
  }
  { queries, }
}
