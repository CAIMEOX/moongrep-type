///|
pub fn yaml_word(c : Char) -> Bool {
  c is ('0'..<='9') ||
  c is ('a'..<='z') ||
  c is ('A'..<='Z') ||
  c is '_' ||
  c is '-'
}

///|
pub fn line_break(b : Byte) -> Bool {
  b == b'\x0a' || b is b'\r'
}

///|
pub fn small_code(code : Int32) -> Bool {
  code == -1 || code is (0 | 2) || code == 3
}

///|
pub fn protocol(s : String) -> Bool {
  s == "http" || s == "https"
}

///|
pub fn edge_numbers(n : UInt64) -> Bool {
  n == 0UL || n == 18446744073709551615UL
}
