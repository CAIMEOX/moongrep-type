///|
/// One-based line and Unicode scalar column. Range ends are exclusive.
#derive(Eq, Hash, Debug, @json.FromJson)
pub(all) struct Position {
  line : Int32
  column : Int32
}

///|
/// The file is the original absolute path of the checked source snapshot.
#derive(Eq, Hash, Debug, @json.FromJson)
pub(all) struct Range {
  file : String
  start : Position
  end : Position
}

///|
#derive(Debug)
pub(all) struct SymbolInfo {
  id : String
  kind : String
  name : String
  identity : Json
  raw : Json
}

///|
pub extend Position with Debug::{to_repr}

///|
pub extend Range with Debug::{to_repr}

///|
pub extend SymbolInfo with Debug::{to_repr}

///|
pub extend Position with Eq::{equal, not_equal}

///|
pub extend Position with Hash::{hash, hash_combine}

///|
pub extend Range with Eq::{equal, not_equal}

///|
pub extend Range with Hash::{hash, hash_combine}

///|
pub extend Position with @json.FromJson::{from_json}

///|
pub extend Range with @json.FromJson::{from_json}
