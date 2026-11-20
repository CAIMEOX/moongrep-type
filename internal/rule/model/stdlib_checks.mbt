///|
/// Standard-library suggestions dispatched after structural matching.
pub(all) enum StdlibCheck {
  IntegerMax
  IntegerMin
  FloatFiniteness
  CollectionIsEmpty
  StringFindContains
  StringStripPrefixTest
  StringStripSuffixTest
  MapGetContains
  ArraySearchContains
  ArraySearchByAny
  IterDropNext
  MapGetDefault
  MatchOptionMap
  MatchOptionBind
  MatchOptionUnwrapOr
  MatchOptionUnwrapOrElse
  MatchResultMap
  MatchResultBind
  MatchResultUnwrapOr
  MatchResultUnwrapOrElse
  MatchResultMapErr
  MatchResultToOption
  LoopAny
  LoopAll
  LoopFindFirst
  CharAsciiDigit
  CharAsciiLowercase
  CharAsciiUppercase
}

///|
fn stdlib_check(name : String) -> StdlibCheck? {
  match name {
    "integer-max" => Some(IntegerMax)
    "integer-min" => Some(IntegerMin)
    "float-finiteness" => Some(FloatFiniteness)
    "collection-is-empty" => Some(CollectionIsEmpty)
    "string-find-contains" => Some(StringFindContains)
    "string-prefix-presence" => Some(StringStripPrefixTest)
    "string-suffix-presence" => Some(StringStripSuffixTest)
    "map-get-contains" => Some(MapGetContains)
    "array-search-contains" => Some(ArraySearchContains)
    "array-search-by-any" => Some(ArraySearchByAny)
    "iter-drop-next" => Some(IterDropNext)
    "map-get-default" => Some(MapGetDefault)
    "match-option-map" => Some(MatchOptionMap)
    "match-option-bind" => Some(MatchOptionBind)
    "match-option-unwrap-or" => Some(MatchOptionUnwrapOr)
    "match-option-unwrap-or-else" => Some(MatchOptionUnwrapOrElse)
    "match-result-map" => Some(MatchResultMap)
    "match-result-bind" => Some(MatchResultBind)
    "match-result-unwrap-or" => Some(MatchResultUnwrapOr)
    "match-result-unwrap-or-else" => Some(MatchResultUnwrapOrElse)
    "match-result-map-err" => Some(MatchResultMapErr)
    "match-result-to-option" => Some(MatchResultToOption)
    "loop-any" => Some(LoopAny)
    "loop-all" => Some(LoopAll)
    "loop-find-first" => Some(LoopFindFirst)
    "char-ascii-digit" => Some(CharAsciiDigit)
    "char-ascii-lowercase" => Some(CharAsciiLowercase)
    "char-ascii-uppercase" => Some(CharAsciiUppercase)
    _ => None
  }
}

///|
/// A lint hint inside the implementation it recommends could introduce recursion.
pub fn StdlibCheck::suggested_method(self : StdlibCheck) -> String {
  match self {
    IntegerMax => "max"
    IntegerMin => "min"
    FloatFiniteness => "is_finite"
    CollectionIsEmpty => "is_empty"
    StringFindContains | MapGetContains | ArraySearchContains => "contains"
    StringStripPrefixTest => "has_prefix"
    StringStripSuffixTest => "has_suffix"
    ArraySearchByAny => "any"
    IterDropNext => "nth"
    MapGetDefault => "get_or_default"
    MatchOptionMap | MatchResultMap => "map"
    MatchOptionBind | MatchResultBind => "bind"
    MatchOptionUnwrapOr | MatchResultUnwrapOr => "unwrap_or"
    MatchOptionUnwrapOrElse | MatchResultUnwrapOrElse => "unwrap_or_else"
    MatchResultMapErr => "map_err"
    MatchResultToOption => "to_option"
    LoopAny => "any"
    LoopAll => "all"
    LoopFindFirst => "find_first"
    CharAsciiDigit => "is_ascii_digit"
    CharAsciiLowercase => "is_ascii_lowercase"
    CharAsciiUppercase => "is_ascii_uppercase"
  }
}
