///|
priv struct InputSource {
  path : String
  text : String
  package_name : String
  aliases : Map[String, String]
  type_names : @lazy.Lazy[Map[String, Json]]
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
fn span(node : @untyped_cst.CstNode) -> Span {
  {
    start: { line: node.loc.start.lnum, column: node.loc.start.column(), },
    end: { line: node.loc.end.lnum, column: node.loc.end.column(), },
  }
}

///|
fn query_anchor(node : @untyped_cst.CstNode) -> @untyped_cst.CstNode {
  match node.kind {
    Expr_DotApply => @cst.child(node, "field").unwrap_or(node)
    Expr_Function | Expr_Infix | Expr_Unary =>
      @cst.raw_child(node, "op").unwrap_or(node)
    Expr_Field | Expr_Method => @cst.raw_child(node, "field").unwrap_or(node)
    Expr_Apply => @cst.child(node, "func").map(query_anchor).unwrap_or(node)
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
priv struct Scope {
  owner : String
  parameters : Map[String, Int32]
}

///|
/// Bind hover type variables to the declaration containing the requested node.
fn declaration_scope(
  source : InputSource,
  root : @untyped_cst.CstNode,
) -> Scope {
  let owner = "\{source.path}:\{root.loc.start.lnum}:\{root.loc.start.column()}"
  let parameters : Map[String, Int32] = Map([])
  let (items, reports) = @untyped_cst.parse_structure(
    @cst.source_text(root, source.text),
  ).to_impls()
  if reports.is_empty() {
    for item in items {
      match item {
        TopFuncDef(fun_decl~, ..) =>
          for param in fun_decl.quantifiers {
            parameters[param.name] = parameters.length()
          }
        TopImpl(quantifiers~, method_quantifiers~, ..) => {
          for param in quantifiers {
            parameters[param.name] = parameters.length()
          }
          for param in method_quantifiers {
            parameters[param.name] = parameters.length()
          }
        }
        _ => ()
      }
    }
  }
  { owner, parameters, }
}
