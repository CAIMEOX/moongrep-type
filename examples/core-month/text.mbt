///|
pub(all) struct MatchInput {
  text : StringView
}

///|
pub fn MatchInput::tail(self : MatchInput, from : Int32) -> StringView {
  self.text[from:self.text.length()]
}

///|
pub fn bytes_suffix(bytes : Bytes, offset : Int32) -> BytesView {
  bytes[offset:bytes.length()]
}

///|
pub fn whole(s : String) -> StringView {
  s[:s.length()]
}

///|
pub fn write_key(buf : StringBuilder, i : Int32, name : String) -> Unit {
  buf.write_string("key=\{i} name=\{name}")
}
