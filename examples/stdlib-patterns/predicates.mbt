///|
pub fn[A] any_item(xs : Array[A], p : (A) -> Bool raise?) -> Bool raise? {
  for x in xs {
    if p(x) {
      break true
    }
  } nobreak {
    false
  }
}

///|
pub fn[A] all_items(xs : Iter[A], p : (A) -> Bool raise?) -> Bool raise? {
  for x in xs {
    if !p(x) {
      break false
    }
  } nobreak {
    true
  }
}

///|
pub fn[A] guarded_all(xs : ArrayView[A], p : (A) -> Bool) -> Bool {
  for x in xs {
    guard p(x) else { break false }
  } nobreak {
    true
  }
}

///|
pub fn first_negative(xs : Iter[Int32]) -> Int32? {
  for x in xs {
    if x < 0 {
      break Some(x)
    }
  } nobreak {
    None
  }
}

///|
pub fn digit(c : Char) -> Bool {
  '0' <= c && c <= '9'
}

///|
pub fn lowercase(c : Char) -> Bool {
  c is ('a'..<='z')
}

///|
pub fn uppercase(c : Char) -> Bool {
  'Z' >= c && c >= 'A'
}

///|
#locals(p)
pub fn shadowed_predicate(xs : Array[Int32], p : (Int32) -> Bool) -> Bool {
  if p(0) {
    return true
  }
  let p = (x : Int32) => x > 10
  for x in xs {
    if p(x) {
      break true
    }
  } nobreak {
    false
  }
}
