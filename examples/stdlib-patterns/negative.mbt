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
