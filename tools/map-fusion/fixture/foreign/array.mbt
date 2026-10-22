///|
pub(all) struct Array[T](T)

///|
pub fn[T, U] Array::map(self : Array[T], f : (T) -> U) -> Array[U] {
  Array(f(self.0))
}
