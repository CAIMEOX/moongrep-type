///|
pub(all) struct Array[T](T)

///|
pub fn[T, U] Array::map(self : Array[T], f : (T) -> U) -> Array[U] {
  Array(f(self.0))
}

///|
pub fn[T] Array::filter(self : Array[T], _p : (T) -> Bool) -> Array[T] {
  self
}

///|
pub fn[T, U] Array::filter_map(self : Array[T], f : (T) -> U?) -> U? {
  f(self.0)
}

///|
pub fn[T] Array::collect(self : Array[T]) -> Array[T] {
  self
}

///|
pub fn[T] Array::length(_self : Array[T]) -> Int {
  1
}
