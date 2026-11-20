///|
pub fn[T] empty_list(xs : Array[T]) -> Bool {
  xs.length() == 0
}

///|
pub fn has_bytes(data : Bytes) -> Bool {
  0 < data.length()
}

///|
pub fn substring(s : String, needle : StringView) -> Bool {
  s.find(needle) is Some(_)
}

///|
pub fn prefix(s : StringView, part : StringView) -> Bool {
  s.strip_prefix(part) is None
}

///|
pub fn suffix(s : String, part : StringView) -> Bool {
  s.strip_suffix(part) is Some(_)
}

///|
pub fn present_key(m : Map[String, Int32?], key : String) -> Bool {
  m.get(key) is Some(_)
}

///|
pub fn contains_number(xs : Array[Int32], value : Int32) -> Bool {
  xs.search(value) is None
}

///|
pub fn[T] searched(xs : Array[T], p : (T) -> Bool raise) -> Bool raise {
  xs.search_by(p) is Some(_)
}

///|
pub fn[T] fourth(it : Iter[T]) -> T? {
  it.drop(3).next()
}

///|
pub fn frequency(m : Map[String, Int32], key : String) -> Int32 {
  m.get(key).unwrap_or(0)
}

///|
pub(all) struct WordList {
  words : Array[String]
}

///|
pub fn WordList::is_empty(self : WordList) -> Bool {
  self.words.length() == 0
}
