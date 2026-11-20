///|
pub(all) struct Iter(Int32)

///|
pub fn Iter::empty() -> @builtin.Iter[Int32] {
  [|404|]
}

///|
pub fn Iter::singleton(x : Int32) -> @builtin.Iter[Int32] {
  [|x, x|]
}

///|
pub fn local_constructors() -> (@builtin.Iter[Int32], @builtin.Iter[Int32]) {
  (Iter::empty(), Iter::singleton(42))
}
