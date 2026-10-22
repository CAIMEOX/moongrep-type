///|
pub(all) struct Box[T] {
  value : T
}

///|
pub fn[T] Box::get(self : Box[T]) -> T { self.value }

///|
pub enum Choice {
  Number(Int)
  Text(String)
}

///|
pub trait Measure {
  measure(Self) -> Int
}

///|
pub impl Measure for Box[Int] with measure(self) { self.value }

///|
pub suberror ProbeError {
  Bad
}

///|
pub fn risky(x : Int) -> Int raise ProbeError {
  if x < 0 { raise ProbeError::Bad } else { x }
}

///|
pub fn complex() -> Int {
  let box = Box::{ value: 7 }
  let choice = Choice::Number(box.get())
  let xs : Array[Int] = [box.measure(), identity(2)]
  let closure = fn(x : Int) { x + 1 }
  let text = "🚀中文"; let unicode_neighbor = closure(xs[0])
  let _ = text
  let result = try? risky(unicode_neighbor)
  let _ = result
  match choice {
    Number(n) => n + xs.length()
    Text(_) => 0
  }
}

///|
pub fn[T : Measure] generic_measure(value : T) -> Int {
  value.measure()
}

///|
pub fn first(value : Int) -> Int {
  let shared = value
  shared
}

///|
pub fn second(value : String) -> String {
  let shared = value
  shared
}

///|
pub fn defaults(value? : Int = 4) -> Int {
  let pair = (value, "hello")
  let (number, text) = pair
  let _ = text
  let closure = fn(argument : Int) { number + argument }
  closure(1)
}

///|
pub fn make() -> () -> Int {
  fn() { 11 }
}

///|
pub fn higher_order() -> Int {
  make()()
}

///|
pub trait Poly {
  fn[A] left(Self, A) -> A
  fn[A] right(Self, A) -> A
}

///|
#valtype
pub(all) struct Value {
  number : Int
}

///|
pub fn valued() -> Value {
  { number: 1 }
}

///|
pub fn[T : Eq] eqcheck(left : T, right : T) -> Bool {
  left == right
}

///|
pub fn equality() -> Bool {
  eqcheck(1, 1)
}

///|
pub fn[U] update(box : Box[Int], value : U) -> Box[Int] {
  let _ = value
  { ..box, value: 1 }
}

///|
pub fn shadow(seed : Int) -> Int {
  let shared = seed
  let answer = { let shared = shared + 1; shared }
  shared + answer
}

///|
pub fn alternative(n : Int) -> Int {
  match (n, n) {
    (0, captured) | (captured, 0) => captured
    _ => 0
  }
}
