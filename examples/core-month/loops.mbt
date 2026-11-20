///|
pub fn[T] drain_until(it : Iter[T], stop : (T) -> Bool) -> T? {
  while it.next() is Some(x) {
    if stop(x) {
      break Some(x)
    }
  } nobreak {
    None
  }
}

///|
pub fn[T] visit_items(it : Iter[T], visit : (T) -> Unit) -> Unit {
  while it.next() is Option::Some(x) {
    visit(x)
  }
}

///|
pub fn visit_text(text : StringView, visit : (Char) -> Unit) -> Unit {
  for ch in text.iter() {
    visit(ch)
  }
}

///|
pub fn visit_bytes(bytes : Bytes, visit : (Byte) -> Unit) -> Unit {
  for b in bytes.iter() {
    visit(b)
  }
}
