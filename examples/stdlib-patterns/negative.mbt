///|
pub(all) struct Other(Int32)

///|
pub fn Other::length(self : Other) -> Int32 {
  self.0
}

///|
pub fn Other::find(self : Other, _s : String) -> Int32? {
  Some(self.0)
}

///|
pub fn Other::get(self : Other, _key : String) -> Int32? {
  Some(self.0)
}

///|
pub fn namesake_empty(x : Other) -> Bool {
  x.length() == 0
}

///|
pub fn namesake_find(x : Other) -> Bool {
  x.find("x") is Some(_)
}

///|
pub fn namesake_key(x : Other) -> Bool {
  x.get("x") is None
}

///|
pub fn tests_index(s : String) -> Bool {
  s.find("x") is Some(0)
}

///|
pub fn not_empty_test(xs : Array[Int32]) -> Bool {
  xs.length() > 1
}

///|
pub fn bind_position(xs : Array[Int32], x : Int32) -> Int32 {
  if xs.search(x) is Some(i) {
    i
  } else {
    -1
  }
}

///|
pub fn negative_drop(it : Iter[Int32]) -> Int32? {
  it.drop(-1).next()
}

///|
pub fn unknown_drop(it : Iter[Int32], n : Int32) -> Int32? {
  it.drop(n).next()
}

///|
pub fn changes_map(m : Map[String, Int32]) -> Int32 {
  m
  .get("x")
  .unwrap_or(
    {
      m.set("x", 3)
      42
    },
  )
}

///|
pub fn none_as_value(m : Map[String, Int32?]) -> Bool {
  m.get("x") is Some(None)
}

///|
pub(all) enum MaybeCount {
  Some(Int32)
  None
}

///|
pub fn other_sum(n : MaybeCount) -> MaybeCount {
  match n {
    Some(x) => Some(x + 1)
    None => None
  }
}

///|
pub fn increment_other(n : Int32?, y : Int32) -> Int32? {
  match n {
    Some(_) => Some(y + 1)
    None => None
  }
}

///|
pub fn error_from_elsewhere(
  r : Result[Int32, String],
  msg : String,
) -> Result[Int32, String] {
  match r {
    Ok(x) => Ok(x + 1)
    Err(_) => Err(msg)
  }
}

///|
pub fn error_is_used(r : Result[Int32, Int32]) -> Int32 {
  match r {
    Ok(x) => x
    Err(e) => e + 3
  }
}

///|
pub fn only_positive(n : Int32?) -> Int32? {
  match n {
    Some(x) if x > 0 => Some(x + 1)
    _ => None
  }
}

///|
pub fn fallback_reads_mutable(n : Int32?) -> Int32 {
  let mut fallback = 0
  match
    ({
      fallback += 1
      n
    }) {
    Some(x) => x
    None => fallback
  }
}

///|
pub fn double_wrapped(r : Result[Int32?, String]) -> Int32? {
  match r {
    Err(_) => None
    Ok(x) => x
  }
}

///|
pub fn incomplete_digit(c : Char) -> Bool {
  '0' <= c && c < '9'
}

///|
pub fn different_chars(x : Char, y : Char) -> Bool {
  'a' <= x && y <= 'z'
}

///|
pub fn successive_chars(read : () -> Char) -> Bool {
  read() >= 'A' && read() <= 'Z'
}

///|
pub fn excluded_uppercase(c : Char) -> Bool {
  c is ('A'..<'Z')
}

///|
pub fn first_indexed_value(xs : Array[Int32], p : (Int32) -> Bool) -> Int32? {
  for x in xs {
    if p(x) {
      break Some(x)
    }
  } nobreak {
    None
  }
}

///|
pub fn first_transformed(xs : Iter[Int32], p : (Int32) -> Bool) -> Int32? {
  for x in xs {
    if p(x) {
      break Some(x + 1)
    }
  } nobreak {
    None
  }
}

///|
pub fn calls_on_exhaustion(
  xs : Iter[Int32],
  p : (Int32) -> Bool,
  exhausted : () -> Bool,
) -> Bool {
  for x in xs {
    if p(x) {
      break true
    }
  } nobreak {
    exhausted()
  }
}

///|
pub fn records_before_testing(
  xs : Array[Int32],
  record : (Int32) -> Unit,
  p : (Int32) -> Bool,
) -> Bool {
  for x in xs {
    record(x)
    if !p(x) {
      break false
    }
  } nobreak {
    true
  }
}

///|
pub async fn async_optional_transform(
  n : Int32?,
  f : async (Int32) -> Int32,
) -> Int32? {
  match n {
    Some(x) => Some(f(x))
    None => None
  }
}
