///|
/// Invalid or incompatible semantic input is never treated as an empty index.
pub(all) suberror SemanticError {
  Invalid(String)
  StaleSource(String)
  MissingSource(String)
  CompilerMismatch(expected~ : String, found~ : String)
} derive(Debug)

///|
pub impl Show for SemanticError with fn output(self, logger) {
  match self {
    Invalid(reason) => logger.write_string("invalid semantic index: \{reason}")
    StaleSource(file) =>
      logger.write_string(
        "semantic source differs from current source: \{file}",
      )
    MissingSource(file) =>
      logger.write_string("semantic source is missing: \{file}")
    CompilerMismatch(expected~, found~) =>
      logger.write_string(
        "semantic compiler mismatch: expected \{expected}, found \{found}",
      )
  }
}

///|
/// One-based line and Unicode scalar column. Range ends are exclusive.
pub(all) struct Position {
  line : Int
  column : Int
} derive(Eq, Hash, Debug)

///|
/// The file is the original absolute path supplied by the semantic reader.
pub(all) struct Range {
  file : String
  start : Position
  end : Position
} derive(Eq, Hash, Debug)

///|
pub(all) struct SourceFile {
  path : String
  text : String
} derive(Debug)

///|
/// `raw` retains the reader's structured type fields, including extensions.
pub(all) struct TypeInfo {
  id : Int
  kind : String
  raw : Json
} derive(Debug)

///|
pub(all) struct SymbolInfo {
  id : String
  kind : String
  name : String
  identity : Json
  raw : Json
} derive(Debug)

///|
/// Multiple compiler facts may describe the same source range.
pub(all) struct Fact {
  id : Int
  package_name : String
  kind : String
  node_kind : String
  location : Range?
  type_id : Int?
  symbol_id : String?
  details : Json
  raw : Json
} derive(Debug)

///|
/// A validated snapshot of the compiler's facts and their source contents.
pub struct Index {
  priv version : String
  priv original : Json
  priv source_entries : Array[SourceFile]
  priv type_entries : Array[TypeInfo]
  priv symbol_entries : Array[SymbolInfo]
  priv fact_entries : Array[Fact]
  priv source_ids : Map[String, Int]
  priv type_ids : Map[Int, Int]
  priv symbol_ids : Map[String, Int]
  priv ranges : Map[Range, Array[Int]]
  priv file_facts : Map[String, Array[Int]]
}

///|
pub fn Index::compiler_version(self : Index) -> String {
  self.version
}

///|
pub fn Index::raw_json(self : Index) -> Json {
  self.original
}

///|
pub fn Index::sources(self : Index) -> ArrayView[SourceFile] {
  self.source_entries[:]
}

///|
pub fn Index::types(self : Index) -> ArrayView[TypeInfo] {
  self.type_entries[:]
}

///|
pub fn Index::symbols(self : Index) -> ArrayView[SymbolInfo] {
  self.symbol_entries[:]
}

///|
pub fn Index::facts(self : Index) -> ArrayView[Fact] {
  self.fact_entries[:]
}

///|
pub fn Index::source(self : Index, path : String) -> SourceFile? {
  self.source_ids.get(path).map(id => self.source_entries[id])
}

///|
pub fn Index::type_info(self : Index, id : Int) -> TypeInfo? {
  self.type_ids.get(id).map(index => self.type_entries[index])
}

///|
pub fn Index::symbol(self : Index, id : String) -> SymbolInfo? {
  self.symbol_ids.get(id).map(index => self.symbol_entries[index])
}

///|
/// Require byte-for-byte-equivalent decoded source text before associating facts.
pub fn Index::require_source(
  self : Index,
  path : String,
  text : String,
) -> Unit raise SemanticError {
  match self.source(path) {
    None => raise MissingSource(path)
    Some(source) if source.text != text => raise StaleSource(path)
    Some(_) => ()
  }
}

///|
/// Exact lookup only: no containing-expression fallback or inferred facts.
pub fn Index::facts_for_range(self : Index, range : Range) -> Array[Fact] {
  match self.ranges.get(range) {
    Some(indices) => indices.map(id => self.fact_entries[id])
    None => []
  }
}

///|
/// Explicitly query containing ranges. Results retain compiler traversal order.
pub fn Index::enclosing_facts(self : Index, range : Range) -> Array[Fact] {
  let result : Array[Fact] = []
  if self.file_facts.get(range.file) is Some(indices) {
    for id in indices {
      let fact = self.fact_entries[id]
      if fact.location is Some(location) &&
        position_le(location.start, range.start) &&
        position_le(range.end, location.end) {
        result.push(fact)
      }
    }
  }
  result
}

///|
fn position_le(left : Position, right : Position) -> Bool {
  left.line < right.line ||
  (left.line == right.line && left.column <= right.column)
}

///|
pub extend SemanticError with Debug::{to_repr}

///|
pub extend Position with Debug::{to_repr}

///|
pub extend Range with Debug::{to_repr}

///|
pub extend SourceFile with Debug::{to_repr}

///|
pub extend TypeInfo with Debug::{to_repr}

///|
pub extend SymbolInfo with Debug::{to_repr}

///|
pub extend Fact with Debug::{to_repr}

///|
pub extend Position with Eq::{equal, not_equal}

///|
pub extend Position with Hash::{hash, hash_combine}

///|
pub extend Range with Eq::{equal, not_equal}

///|
pub extend Range with Hash::{hash, hash_combine}

///|
pub extend SemanticError with Show::{to_string, output}
