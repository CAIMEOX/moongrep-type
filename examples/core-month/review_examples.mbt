///|
pub fn copy_prefix(xs : FixedArray[Int32], n : Int32) -> FixedArray[Int32] {
  let result = FixedArray::make(n, 0)
  for i in 0..<n {
    result[i] = xs[i]
  }
  result
}

///|
pub fn cookie_item(s : StringView) -> (StringView, StringView)? {
  if s.find("=") is Some(i) {
    let left = s[:i]
    let right = s[i + 1:]
    Some((left, right))
  } else {
    None
  }
}

///|
pub fn has_only(xs : Array[Int32], p : (Int32) -> Bool) -> Bool {
  xs.iter().all(p)
}
