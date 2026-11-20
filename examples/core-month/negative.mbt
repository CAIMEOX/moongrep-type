///|
pub(all) struct Sample(Int32)

///|
pub fn Sample::is_nan(self : Sample) -> Bool {
  self.0 < 0
}

///|
pub fn Sample::is_inf(self : Sample) -> Bool {
  self.0 > 99
}

///|
pub fn foreign_number(x : Sample) -> Bool {
  x.is_nan() || x.is_inf()
}

///|
pub fn double_read(read : () -> Double) -> Bool {
  read().is_nan() || read().is_inf()
}

///|
pub fn two_numbers(x : Double, y : Double) -> Bool {
  x.is_nan() || y.is_inf()
}

///|
pub fn fresh_input(next_iter : () -> Iter[Int32]) -> Unit {
  while next_iter().next() is Some(x) {
    ignore(x)
  }
}

///|
pub fn different_input(first : Iter[Int32], other : Iter[Int32]) -> Unit {
  let mut it = first
  while it.next() is Some(x) {
    if x == 0 {
      it = other
    }
  }
}

///|
pub fn stop_on_pattern(it : Iter[Int32?]) -> Unit {
  while it.next() is Some(Some(x)) {
    ignore(x)
  }
}

///|
pub fn extra_condition(it : Iter[Int32], ready : () -> Bool) -> Unit {
  while ready() && it.next() is Some(x) {
    ignore(x)
  }
}

///|
pub fn array_iteration(arr : Array[Int32], body : (Int32) -> Unit) -> Unit {
  for x in arr.iter() {
    body(x)
  }
}

///|
pub(all) struct Source {
  mut text : StringView
}

///|
pub fn changes_field(s : Source) -> StringView {
  s.text[{
    s.text = "z"
    0
  }:s.text.length()]
}

///|
pub fn mismatched_end(a : String, b : String, i : Int32) -> StringView {
  a[i:b.length()]
}

///|
pub fn view_factory(get : () -> String, i : Int32) -> StringView {
  get()[i:get().length()]
}

///|
pub fn reads_builder(buf : StringBuilder) -> Unit {
  buf.write_string("prefix\{buf.to_string()}")
}

///|
pub fn unknown_logger(log : &Logger, s : String) -> Unit {
  log.write_string("v=\{s}")
}

///|
pub fn literal_write(buf : StringBuilder) -> Unit {
  buf.write_string("literal")
}

///|
pub fn effectful_bound(read : () -> Int32, y : Int32) -> Int32 {
  if read() < y {
    read()
  } else {
    y
  }
}

///|
pub fn floating_bound(x : Double, y : Double) -> Double {
  if x < y {
    x
  } else {
    y
  }
}

///|
pub fn choose_other(x : Int32, y : Int32, z : Int32) -> Int32 {
  if x < y {
    x
  } else {
    z
  }
}

///|
pub fn increment_instead(value : Int32, init : Int32) -> Int32 {
  let mut acc = init
  if value < acc {
    acc += value
  }
  acc
}

///|
pub fn independent_predicate(x : Double) -> Bool {
  x.is_finite() == !(x.is_nan() || x.is_inf())
}

///|
pub fn compare_with_oracle(x : Double) -> Unit raise {
  assert_eq(x.is_finite(), !(x.is_nan() || x.is_inf()))
}

///|
pub fn Sample::write_string(_self : Sample, _s : String) -> Unit {
  ()
}

///|
pub fn foreign_write(dst : Sample, s : String) -> Unit {
  dst.write_string("v=\{s}")
}

///|
pub fn repeated_bound(x : Int32) -> Int32 {
  if x < x {
    x
  } else {
    x
  }
}

///|
pub fn[T : Compare] generic_min(x : T, y : T) -> T {
  if x < y {
    x
  } else {
    y
  }
}

///|
pub fn Sample::next(_self : Sample) -> Int32? {
  None
}

///|
pub fn foreign_next(s : Sample) -> Unit {
  while s.next() is Some(value) {
    ignore(value)
  }
}
