///|
/// OCaml Marshal values are a graph. Block fields and shared references use
/// arena indices, so cycles never require recursively allocating MoonBit values.
pub(all) enum Value {
  Integer(Int64)
  Block(tag~ : Int, fields~ : Array[Int])
  ByteString(Bytes)
  FloatBits(Int64)
  FloatArray(Array[Int64])
  Custom(name~ : String, value~ : Int64)
} derive(Debug)

///|
pub struct Graph {
  priv values : Array[Value]
  priv root_id : Int
  priv shared_count : Int
}

///|
pub(all) suberror DecodeError {
  Invalid(offset~ : Int, reason~ : String)
} derive(Debug)

///|
pub impl Show for DecodeError with fn output(self, logger) {
  let Invalid(offset~, reason~) = self
  logger.write_string("invalid OCaml Marshal at byte \{offset}: \{reason}")
}

///|
pub fn Graph::root(self : Graph) -> Int {
  self.root_id
}

///|
pub fn Graph::length(self : Graph) -> Int {
  self.values.length()
}

///|
pub fn Graph::shared_objects(self : Graph) -> Int {
  self.shared_count
}

///|
pub fn Graph::get(self : Graph, id : Int) -> Value raise DecodeError {
  guard self.values.get(id) is Some(value) else {
    raise Invalid(offset=0, reason="invalid graph reference: \{id}")
  }
  value
}

///|
pub fn Graph::text(self : Graph, id : Int) -> String raise DecodeError {
  guard self.get(id) is ByteString(bytes) else {
    raise Invalid(offset=0, reason="expected a byte string at node \{id}")
  }
  @utf8.decode(bytes) catch {
    _ => raise Invalid(offset=0, reason="invalid UTF-8 at node \{id}")
  }
}

///|
pub extend Value with Debug::{to_repr}

///|
pub extend DecodeError with Debug::{to_repr}

///|
pub extend DecodeError with Show::{to_string, output}
