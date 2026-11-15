///|
pub fn sample(xs : Array[Int]) -> Array[Int] {
  xs.map(x => x + 1).map(x => x * 2)
}
