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
