///|
pub fn collection_array_count(xs : Array[Int], p : (Int) -> Bool) -> Int {
  xs.filter(p).length()
}

///|
pub fn[T] collection_generic_count(xs : Array[T], p : (T) -> Bool) -> Int {
  xs.filter(p).length()
}

///|
pub suberror CollectionFailure {
  Stop
}

///|
pub fn collection_raising_count(
  xs : Array[Int],
  p : (Int) -> Bool raise CollectionFailure,
) -> Int raise CollectionFailure {
  xs.filter(p).length()
}

///|
pub fn collection_count_factory(
  source : () -> Array[Int],
  predicate : () -> (Int) -> Bool,
) -> Int {
  source().filter(predicate()).length()
}

///|
pub fn collection_iter_count(it : Iter[Int], p : (Int) -> Bool) -> Int {
  it.filter(p).count()
}

///|
pub fn collection_first(it : Iter[Int], p : (Int) -> Bool) -> Int? {
  it.filter(p).next()
}

///|
pub fn collection_exists(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p).is_some()
}

///|
pub fn collection_absent(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p).is_none()
}

///|
pub fn collection_raising_exists(
  it : Iter[Int],
  p : (Int) -> Bool raise CollectionFailure,
) -> Bool raise CollectionFailure {
  it.find_first(p).is_some()
}

///|
pub fn collection_is_none(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p) is None
}

///|
pub fn collection_is_some(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p) is Some(_)
}

///|
pub fn collection_is_qualified(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p) is Option::Some(_)
}

///|
pub fn collection_is_raising(
  it : Iter[Int],
  p : (Int) -> Bool raise CollectionFailure,
) -> Bool raise CollectionFailure {
  it.find_first(p) is None
}

///|
pub fn[T] collection_is_generic(it : Iter[T], p : (T) -> Bool) -> Bool {
  it.find_first(p) is Some(_)
}

///|
pub fn collection_is_factory(
  source : () -> Iter[Int],
  predicate : () -> (Int) -> Bool,
) -> Bool {
  source().find_first(predicate()) is None
}

///|
pub fn collection_is_unicode(
  it : Iter[Int],
  p : (Int) -> Bool,
) -> (String, Bool) {
  ("🚀", it.find_first(p) is Some(_))
}

///|
pub fn collection_is_binding(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  if it.find_first(p) is Some(value) {
    value > 0
  } else {
    false
  }
}

///|
pub fn collection_is_literal(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p) is Some(7)
}

///|
pub fn collection_is_nested(it : Iter[Int?], p : (Int?) -> Bool) -> Bool {
  it.find_first(p) is Some(None)
}

///|
pub fn collection_is_alias(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  if it.find_first(p) is Some(_ as value) {
    value > 0
  } else {
    false
  }
}

///|
pub fn collection_is_alternative(it : Iter[Int], p : (Int) -> Bool) -> Bool {
  it.find_first(p) is (Some(_) | None)
}

///|
pub fn[A, B] collection_flatten(it : Iter[A], f : (A) -> Iter[B]) -> Iter[B] {
  it.map(f).flatten()
}

///|
pub fn collection_flatten_factory(
  source : () -> Iter[Int],
  transform : () -> (Int) -> Iter[Int],
) -> Iter[Int] {
  source().map(transform()).flatten()
}

///|
// Array maps eagerly, so the corresponding Iter theorem does not apply.
pub fn collection_eager_flatten(
  xs : Array[Int],
  f : (Int) -> Array[Int],
) -> Array[Int] {
  xs.map(f).flatten()
}

///|
// Counting the filtered array visits every input; any() would skip effects.
pub fn collection_keep_full_traversal(
  xs : Array[Int],
  p : (Int) -> Bool,
) -> Bool {
  xs.filter(p).is_empty()
}

///|
// An effectful map cannot be removed just because only the count is observed.
pub fn collection_keep_mapping(it : Iter[Int], f : (Int) -> Int) -> Int {
  it.map(f).count()
}
