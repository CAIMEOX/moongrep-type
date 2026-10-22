///|
pub fn lambdas(xs : Array[Int]) -> Array[String] {
  xs.map(x => x + 1).map(x => x.to_string())
}

///|
pub fn[A, B, C] generic(xs : Array[A], g : (A) -> B, f : (B) -> C) -> Array[C] {
  xs.map(g).map(f)
}

///|
pub fn to_text(x : Int) -> String { x.to_string() }

///|
pub fn text_length(x : String) -> Int { x.length() }

///|
pub fn named(xs : Array[Int]) -> Array[Int] {
  xs.map(to_text).map(text_length)
}

///|
pub fn multiline(xs : Array[Int]) -> Array[Int] {
  ignore("🚀"); xs.map(to_text)
    .map(text_length)
}

///|
pub fn triple(xs : Array[Int], f : (Int) -> Int) -> Array[Int] {
  xs.map(f).map(f).map(f)
}

///|
pub fn effects(xs : Array[Int], events : Array[String]) -> Array[Int] {
  xs.map(x => { events.push("g"); x }).map(x => { events.push("f"); x })
}

///|
pub fn factory() -> (Int) -> Int { x => x + 1 }

///|
pub fn factories(xs : Array[Int]) -> Array[Int] {
  xs.map(factory()).map(factory())
}

///|
pub suberror Failed { Failed }

///|
pub fn failure() -> Failed { Failed::Failed }

///|
pub fn throwing(xs : Array[Int], g : (Int) -> Int raise Failed, f : (Int) -> Int) -> Array[Int] raise Failed {
  xs.map(g).map(f)
}

///|
pub fn optional(xs : Int?, g : (Int) -> Int, f : (Int) -> Int) -> Int? {
  xs.map(g).map(f)
}

///|
pub fn lazy_maps(xs : Iter[Int], g : (Int) -> Int, f : (Int) -> Int) -> Iter[Int] {
  xs.map(g).map(f)
}

///|
pub fn lookalike(xs : @foreign.Array[Int], g : (Int) -> Int, f : (Int) -> Int) -> @foreign.Array[Int] {
  xs.map(g).map(f)
}

///|
pub fn one(xs : Array[Int], f : (Int) -> Int) -> Array[Int] {
  xs.map(f)
}

///|
pub fn qualified(xs : Array[Int], g : (Int) -> Int, f : (Int) -> Int) -> Array[Int] {
  Array::map(Array::map(xs, g), f)
}
