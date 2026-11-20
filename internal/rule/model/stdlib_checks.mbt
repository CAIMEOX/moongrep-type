///|
/// Standard-library suggestions dispatched after structural matching.
pub(all) enum StdlibCheck {
  CollectionIsEmpty
  StringFindContains
  StringStripPrefixTest
  StringStripSuffixTest
  MapGetContains
  ArraySearchContains
  ArraySearchByAny
  IterDropNext
  MapGetDefault
}

///|
fn stdlib_check(name : String) -> StdlibCheck? {
  match name {
    "collection-is-empty" => Some(CollectionIsEmpty)
    "string-find-contains" => Some(StringFindContains)
    "string-prefix-presence" => Some(StringStripPrefixTest)
    "string-suffix-presence" => Some(StringStripSuffixTest)
    "map-get-contains" => Some(MapGetContains)
    "array-search-contains" => Some(ArraySearchContains)
    "array-search-by-any" => Some(ArraySearchByAny)
    "iter-drop-next" => Some(IterDropNext)
    "map-get-default" => Some(MapGetDefault)
    _ => None
  }
}

///|
/// A lint hint inside the implementation it recommends could introduce recursion.
pub fn StdlibCheck::suggested_method(self : StdlibCheck) -> String {
  match self {
    CollectionIsEmpty => "is_empty"
    StringFindContains | MapGetContains | ArraySearchContains => "contains"
    StringStripPrefixTest => "has_prefix"
    StringStripSuffixTest => "has_suffix"
    ArraySearchByAny => "any"
    IterDropNext => "nth"
    MapGetDefault => "get_or_default"
  }
}
