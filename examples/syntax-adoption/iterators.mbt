///|
pub fn empty_numbers() -> Iter[Int32] {
  Iter::empty()
}

///|
pub fn[T] one(item : T) -> Iter[T] {
  Iter::singleton(item)
}

///|
pub fn two_reads(read : () -> Int32 raise?) -> Iter[Int32] raise? {
  [read(), read()].iter()
}
