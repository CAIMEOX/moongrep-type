///|
pub(all) suberror SchemaError {
  Invalid(String)
} derive(Debug)

///|
pub impl Show for SchemaError with fn output(self, logger) {
  let Invalid(message) = self
  logger.write_string("unsupported or invalid typedtree: \{message}")
}

///|
pub extend SchemaError with Debug::{to_repr}

///|
pub extend SchemaError with Show::{to_string, output}

///|
priv struct Wire {
  graph : @marshal.Graph
}

///|
fn Wire::value(self : Wire, id : Int) -> @marshal.Value raise {
  self.graph.get(id)
}

///|
fn Wire::fields(
  self : Wire,
  id : Int,
  tag : Int,
  size : Int,
) -> Array[Int] raise {
  guard self.value(id) is Block(tag=found, fields~) &&
    found == tag &&
    (size < 0 || fields.length() == size) else {
    raise Invalid("node \{id}: expected block tag \{tag} with \{size} fields")
  }
  fields
}

///|
fn Wire::record(self : Wire, id : Int, size : Int) -> Array[Int] raise {
  self.fields(id, 0, size)
}

///|
fn Wire::integer(self : Wire, id : Int) -> Int raise {
  guard self.value(id) is Integer(n) && n >= -2147483648L && n <= 2147483647L else {
    raise Invalid("node \{id}: expected bounded integer")
  }
  n.to_int()
}

///|
fn Wire::text(self : Wire, id : Int) -> String raise {
  self.graph.text(id)
}

///|
fn Wire::bool(self : Wire, id : Int) -> Bool raise {
  match self.integer(id) {
    0 => false
    1 => true
    _ => raise Invalid("node \{id}: invalid boolean")
  }
}

///|
fn Wire::list(self : Wire, id : Int) -> Array[Int] raise {
  let out = []
  let seen : Map[Int, Bool] = Map([])
  let mut node = id
  while true {
    if self.value(node) is Integer(0L) {
      break
    }
    if seen.contains(node) {
      raise Invalid("cyclic list at node \{node}")
    }
    seen[node] = true
    let fields = self.record(node, 2)
    out.push(fields[0])
    node = fields[1]
  }
  out
}

///|
fn Wire::option(self : Wire, id : Int) -> Int? raise {
  if self.value(id) is Integer(0L) {
    None
  } else {
    Some(self.record(id, 1)[0])
  }
}

///|
fn Wire::tag(self : Wire, id : Int) -> Int raise {
  guard self.value(id) is Block(tag~, ..) else {
    raise Invalid("node \{id}: expected variant block")
  }
  tag
}

///|
fn json_array_int(values : Array[Int]) -> Json {
  Json::array(values.map(n => Json::number(n.to_double())))
}
