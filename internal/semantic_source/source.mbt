///|
pub(all) suberror SourceError {
  InvalidSource(String)
  ForeignNode
} derive(Debug)

///|
pub impl Show for SourceError with fn output(self, logger) {
  match self {
    InvalidSource(reason) =>
      logger.write_string("cannot associate semantic source: \{reason}")
    ForeignNode =>
      logger.write_string("CST node does not belong to this semantic source")
  }
}

///|
/// Associated facts share the exact source range and have a compatible syntax
/// role. This does not select a unique type: implicit conversions may add facts.
/// Ambiguous preserves exact candidates whose source role or package is unclear.
pub(all) enum Association {
  Unmatched
  Associated(Array[@semantic.Fact])
  Ambiguous(Array[@semantic.Fact])
} derive(Debug)

///|
/// One whole-file parse tied to a validated compiler source snapshot.
pub struct Source {
  priv index : @semantic.Index
  priv file : String
  priv cst_root : @untyped_cst.CstNode
  priv nodes : Map[(Int, Int), Array[@untyped_cst.CstNode]]
  priv view : String?
}

///|
pub fn Source::parse(
  index : @semantic.Index,
  file~ : String,
  text~ : String,
  view? : String,
) -> Source raise {
  if view is Some(name) && !["normal", "wbtest", "bbtest"].contains(name) {
    raise InvalidSource("unknown package view: \{name}")
  }
  index.require_source(file, text)
  let parsed = @untyped_cst.parse_structure(text, name=file)
  let reports = parsed.diagnostics_view()
  if !reports.is_empty() {
    raise InvalidSource(reports.map(report => report.msg).join("; "))
  }
  let root = parsed.root()
  if @cst.first_recovery_node(root) is Some(_) {
    raise InvalidSource("incomplete recovered CST node")
  }
  let nodes : Map[(Int, Int), Array[@untyped_cst.CstNode]] = Map([])
  let pending = [root]
  while pending.pop() is Some(node) {
    if nodes.get(node.source_span) is Some(bucket) {
      bucket.push(node)
    } else {
      nodes[node.source_span] = [node]
    }
    for (_, child) in node.children {
      pending.push(child)
    }
  }
  { index, file, cst_root: root, nodes, view, }
}

///|
fn Source::includes_fact(
  self : Source,
  fact : @semantic.Fact,
  include_generated~ : Bool,
) -> Bool {
  if !include_generated && fact.details is { "generated_top_level": true, .. } {
    return false
  }
  match self.view {
    None => true
    Some(view) => fact.package_name.has_suffix(":\{view}")
  }
}

///|
/// Located facts for this source in its explicitly selected package view.
/// Generated top-level bodies remain queryable by default.
pub fn Source::facts(
  self : Source,
  include_generated~ : Bool = true,
) -> Array[@semantic.Fact] {
  self.index
  .facts_for_file(self.file)
  .filter(fact => self.includes_fact(fact, include_generated~))
}

///|
pub fn Source::root(self : Source) -> @untyped_cst.CstNode {
  self.cst_root
}

///|
pub fn Source::index(self : Source) -> @semantic.Index {
  self.index
}

///|
pub fn Source::file(self : Source) -> String {
  self.file
}

///|
fn Source::owns(self : Source, node : @untyped_cst.CstNode) -> Bool {
  if self.nodes.get(node.source_span) is Some(bucket) {
    for candidate in bucket {
      if physical_equal(node, candidate) {
        return true
      }
    }
  }
  false
}

///|
/// Only original nodes from `root()` may be used, preventing stale or block-local
/// locations from accidentally matching another parse's compiler facts.
pub fn Source::range_for_node(
  self : Source,
  node : @untyped_cst.CstNode,
) -> @semantic.Range raise SourceError {
  if !self.owns(node) {
    raise ForeignNode
  }
  {
    file: self.file,
    start: { line: node.loc.start.lnum, column: node.loc.start.column(), },
    end: { line: node.loc.end.lnum, column: node.loc.end.column(), },
  }
}

///|
fn compatible_role(node : @untyped_cst.CstNode, fact : @semantic.Fact) -> Bool {
  let kind = "\{Repr(node.kind)}"
  if kind.has_prefix("Expr_") {
    fact.kind == "expression"
  } else if kind.has_prefix("Pattern_") {
    fact.kind == "pattern"
  } else if kind.has_prefix("Type_") {
    fact.kind == "type_use"
  } else if kind.has_prefix("Impl_") {
    fact.kind == "declaration"
  } else if kind == "Name_Binder" {
    fact.kind == "binding"
  } else if kind.has_prefix("Name_") {
    fact.kind == "symbol_reference" ||
    fact.kind == "field_reference" ||
    fact.kind == "constructor_reference" ||
    fact.kind == "type_use" ||
    fact.kind == "type_parameter" ||
    fact.kind == "binding"
  } else {
    false
  }
}

///|
pub fn Source::facts_for_node(
  self : Source,
  node : @untyped_cst.CstNode,
  include_generated~ : Bool = true,
) -> Association raise SourceError {
  let range = self.range_for_node(node)
  let facts = self.index
    .facts_for_range(range)
    .filter(fact => self.includes_fact(fact, include_generated~))
  if facts.is_empty() {
    return Unmatched
  }
  let package_name = facts[0].package_name
  let mut compatible = false
  for fact in facts {
    if fact.package_name != package_name {
      return Ambiguous(facts)
    }
    if compatible_role(node, fact) {
      compatible = true
    }
  }
  if compatible {
    Associated(facts)
  } else {
    Ambiguous(facts)
  }
}

///|
/// Each captured node retains its own association, including empty ellipses.
pub fn Source::facts_for_capture(
  self : Source,
  value : @model.BoundValue,
) -> Array[Association] raise SourceError {
  match value {
    Single(node) => [self.facts_for_node(node)]
    Multiple(nodes) => nodes.map(node => self.facts_for_node(node))
  }
}

///|
pub extend Association with Debug::{to_repr}

///|
pub extend SourceError with Debug::{to_repr}

///|
pub extend SourceError with Show::{to_string, output}
