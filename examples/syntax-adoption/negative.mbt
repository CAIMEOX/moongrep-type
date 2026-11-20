///|
pub fn keep_pair(
  rows : Array[(Int32, Int32)],
  visit : ((Int32, Int32), Int32) -> Unit,
) -> Unit {
  for pair in rows {
    let (x, y) = pair
    visit(pair, x + y)
  }
}

///|
pub fn key_shadows_header(rows : Map[Int32, (Int32, Int32)]) -> Int32 {
  let mut total = 0
  for _key, pair in rows {
    let (_key, n) = pair
    total += _key + n
  }
  total
}

///|
pub fn keep_prior_work(
  rows : Array[(Int32, Int32)],
  tick : () -> Unit,
) -> Int32 {
  let mut total = 0
  for pair in rows {
    tick()
    let (x, y) = pair
    total += x + y
  }
  total
}
