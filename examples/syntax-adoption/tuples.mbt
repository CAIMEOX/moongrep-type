///|
pub fn add_pairs(rows : Array[(Int32, Int32)]) -> Int32 {
  let mut total = 0
  for pair in rows {
    let (x, y) = pair
    total += x + y
  }
  total
}

///|
pub fn collect_counts(rows : Map[String, (Bool, Int32)]) -> Int32 {
  let mut total = 0
  for _, pair in rows {
    let (enabled, n) = pair
    if enabled {
      total += n
    }
  }
  total
}

///|
pub fn sum_keys(rows : Map[(Int32, Int32), Int32]) -> Int32 {
  let mut total = 0
  for key, weight in rows {
    let (x, _) = key
    total += x * weight
  }
  total
}
