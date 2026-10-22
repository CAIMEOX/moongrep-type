///|
pub fn reads_accumulator(xs : Array[Int]) -> Array[Int] {
  let out = []
  for _x in xs {
    out.push(out.length())
  }
  out
}

///|
pub fn captures_accumulator(xs : Array[Int]) -> Array[() -> Int] {
  let out : Array[() -> Int] = []
  for _x in xs {
    out.push(fn() { out.length() })
  }
  out
}

///|
pub fn escaping_accumulator(
  xs : Array[Int],
  observe : (Array[Int]) -> Int,
) -> Array[Int] {
  let out = []
  for _x in xs {
    out.push(observe(out))
  }
  out
}

///|
pub fn early_exit(xs : Array[Int]) -> Array[Int] {
  let out = []
  for x in xs {
    if x < 0 {
      break
    }
    out.push(x)
  }
  out
}

///|
pub fn eager_filter_map(xs : Array[Int]) -> Array[Int] {
  xs.filter(x => x > 0).map(x => x * 2)
}

///|
pub fn iterator_factory(xs : Array[Int]) -> Iter[Int] {
  xs.iter().filter(x => x > 0).map(x => x * 2)
}

///|
pub fn callback_factory(
  it : Iter[Int],
  factory : () -> (Int) -> Int,
) -> Iter[Int] {
  it.filter(x => x > 0).map(factory())
}

///|
pub fn custom_map(value : @foreign.Array[Int]) -> Unit {
  ignore(value.map(x => x + 1))
}

///|
pub fn custom_count(value : @foreign.Array[Int]) -> Int {
  value.collect().length()
}

///|
pub fn non_adjacent(it : Iter[Int]) -> Array[Int] {
  let count = it.count()
  ignore(count)
  it.collect()
}

///|
pub fn iterator_rebound(xs : Array[Int]) -> Array[Int] {
  let mut it = xs.iter()
  let _count = it.count()
  it = xs.iter()
  it.collect()
}

///|
pub fn shadowed_iterator(it : Iter[Int], xs : Array[Int]) -> Array[Int] {
  let _count = it.count()
  let it = xs.iter()
  it.collect()
}

///|
pub fn non_option_filter(xs : Array[Int]) -> Array[Int] {
  xs.filter_map(x => Some(x + 1))
}

///|
pub fn mutable_iterator(xs : Array[Int]) -> Iter[Int] {
  let mut it = xs.iter()
  let pipeline = it.filter(x => x > 0).map(x => x + 1)
  it = xs.iter()
  ignore(it)
  pipeline
}

///|
pub fn custom_ignore(xs : Array[Int], ignore : (Array[Int]) -> Unit) -> Unit {
  ignore(xs.map(x => x + 1))
}

///|
pub fn accumulator_in_guard(xs : Array[Int]) -> Array[Int] {
  let out = []
  for x in xs {
    if out.is_empty() {
      out.push(x)
    }
  }
  out
}

///|
pub fn shadowed_output(xs : Array[Array[Int]]) -> Array[Int] {
  let out : Array[Int] = []
  for out in xs {
    out.push(1)
  }
  out
}
