///|
pub fn keep_pair(
  rows : Array[(Int32, Int32)],
  visit : ((Int32, Int32), Int32) -> Unit,
) -> Unit {
  for pair in rows {
    let (x, y) = pair
    visit(pair, x + y)
  }
}

///|
pub fn key_shadows_header(rows : Map[Int32, (Int32, Int32)]) -> Int32 {
  let mut total = 0
  for _key, pair in rows {
    let (_key, n) = pair
    total += _key + n
  }
  total
}

///|
pub fn keep_prior_work(
  rows : Array[(Int32, Int32)],
  tick : () -> Unit,
) -> Int32 {
  let mut total = 0
  for pair in rows {
    tick()
    let (x, y) = pair
    total += x + y
  }
  total
}

///|
pub fn consumes_two(read : () -> Int32) -> Bool {
  read() == 1 || read() == 2
}

///|
pub fn different_values(x : Int32, y : Int32) -> Bool {
  x == 1 || y == 2
}

///|
pub fn redundant_range(c : Char) -> Bool {
  c is ('a'..<='z') || c == 'b'
}

///|
pub fn duplicate_spelling(n : Int32) -> Bool {
  n == 15 || n == 0x0f
}

///|
pub fn rebindable(n : Int32) -> Bool {
  let mut pos = n
  if pos < 0 {
    pos = 0
  }
  pos == 1 || pos == 3
}

///|
pub fn inspect_payload(n : Int32?) -> Bool {
  n is Some(1) || n is Some(2)
}

///|
pub fn float_values(n : Double) -> Bool {
  n == 0.0 || n == 1.0
}

///|
pub fn from_storage(xs : Array[Int32]) -> Iter[Int32] {
  xs.iter()
}

///|
pub fn slice_items(xs : Array[Int32]) -> Iter[Int32] {
  xs[1:].iter()
}

///|
pub fn computed_items(xs : Array[Int32], f : (Int32) -> Int32) -> Iter[Int32] {
  [ for x in xs => f(x) ].iter()
}

///|
pub fn spread_items(xs : Array[Int32]) -> Iter[Int32] {
  [..xs].iter()
}

///|
pub fn observe_room(flag : Bool) -> Int32 {
  let items = []
  if flag {
    items.push(4)
  }
  items.push(9)
  for item in items {
    ignore(item)
  }
  items.capacity()
}

///|
pub fn expose_array(inspect_items : (Array[Int32]) -> Bool) -> Unit {
  let items = []
  if inspect_items(items) {
    items.push(4)
  }
  items.push(9)
  for item in items {
    ignore(item)
  }
}

///|
pub fn reserved_array(flag : Bool) -> Unit {
  let items : Array[Int32] = Array(capacity=32)
  if flag {
    items.push(4)
  }
  items.push(9)
  for item in items {
    ignore(item)
  }
}
