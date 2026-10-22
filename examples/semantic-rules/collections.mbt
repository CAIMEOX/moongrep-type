///|
pub fn builder_plain(xs : Array[Int]) -> Array[Int] {
  let out = []
  for x in xs {
    out.push(x + 1)
  }
  out
}

///|
pub fn builder_filter(xs : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for x in xs {
    if x > 0 {
      out.push(x * 2)
    }
  }
  out
}

///|
pub fn builder_indexed(xs : Array[Int]) -> Array[(Int, Int)] {
  let out = []
  for i, x in xs {
    out.push((i, x))
  }
  out
}

///|
pub fn builder_range(n : Int) -> Array[Int] {
  let out = []
  for i in 0..<n {
    out.push(i * i)
  }
  out
}

///|
pub fn filter_map_if(xs : Array[Int]) -> Array[Int] {
  xs.filter_map(x => if x > 0 { Some(x * 2) } else { None })
}

///|
pub fn filter_map_option(xs : Array[Int?]) -> Array[Int] {
  xs.filter_map(x => {
    match x {
      Some(value) => Some(value + 1)
      None => None
    }
  })
}

///|
pub fn iter_pipeline(it : Iter[Int]) -> Iter[Int] {
  it.filter(x => x > 0).map(x => x * 2)
}

///|
pub fn collected_pipeline(it : Iter[Int]) -> Array[Int] {
  it.filter(x => x > 0).map(x => x * 2).collect()
}

///|
pub fn count_without_array(it : Iter[Int]) -> Int {
  it.collect().length()
}

///|
pub fn count_without_array_alias(it : Iter[Int]) -> Int {
  it.to_array().length()
}

///|
pub fn discard_map(xs : Array[Int], f : (Int) -> Int) -> Unit {
  ignore(xs.map(f))
}

///|
pub fn reuse_iterator(it : Iter[Int]) -> Array[Int] {
  let _count = it.count()
  it.collect()
}

///|
pub fn reuse_after_ignored_count(it : Iter[Int]) -> Array[Int] {
  ignore(it.count())
  it.collect()
}

///|
pub fn map_fusion(xs : Array[Int]) -> Array[Int] {
  xs.map(x => x + 1).map(x => x * 2)
}

///|
pub fn unicode_builder(xs : Array[Int]) -> Array[Int] {
  ignore("🚀")
  let out = []
  for x in xs {
    out.push(x + 1)
  }
  out
}

///|
#moongrep.skip
pub fn skipped_builder(xs : Array[Int]) -> Array[Int] {
  let out = []
  for x in xs {
    out.push(x)
  }
  out
}

///|
pub fn lookalike(value : @foreign.Array[Int]) -> Int? {
  value.filter_map(x => if x > 0 { Some(x) } else { None })
}

///|
pub fn[A, B] generic_builder(xs : Array[A], transform : (A) -> B) -> Array[B] {
  let out = []
  for x in xs {
    out.push(transform(x))
  }
  out
}

///|
pub fn[A, B] generic_iter(
  it : Iter[A],
  predicate : (A) -> Bool,
  transform : (A) -> B,
) -> Iter[B] {
  it.filter(predicate).map(transform)
}

///|
pub fn unicode_count(items : Iter[Int]) -> (String, Int) {
  ("🚀", items.collect().length())
}
