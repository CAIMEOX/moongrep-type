///|
pub fn views(values : Array[Int], text : String, bytes : Bytes) -> Int {
  fn array_size(view : ArrayView[Int]) -> Int { view.length() }
  fn string_size(view : StringView) -> Int { view.length() }
  fn bytes_size(view : BytesView) -> Int { view.length() }
  array_size(values) + string_size(text) + bytes_size(bytes)
}

///|
pub fn control(value : Int, values : Array[Int]) -> Int {
  let mut total = 0
  for item in values {
    total += item
  }
  for i = 0; i < value; i = i + 1 {
    if i == 2 { continue }
    total += i
  }
  while total < 10 { total += 1 }
  let chosen = match values {
    [first, .. rest] => first + rest.length()
    [] => 0
  }
  let optional : Int? = Some(chosen)
  guard optional is Some(found) else { return 0 }
  if !(found == 0) && (total > 0 || value == 1) { found } else { total }
}

///|
pub fn recursive(value : Int) -> Int {
  fn down(n : Int) -> Int {
    if n <= 0 { 0 } else { down(n - 1) }
  }
  down(value)
}

///|
pub fn comprehensions() -> Array[Int] {
  [for i in 0..<4 => i + 1]
}

///|
pub fn matches(value : Int, values : Map[String, Int]) -> Int {
  let scalar = match value { 1 | 2 => 1; 3..=5 => 2; other as copy => other + copy }
  match values {
    { "key"?: Some(item), .. } => scalar + item
    _ => scalar
  }
}

///|
pub fn effects() -> Int {
  defer { ignore(1) }
  risky(1) catch { ProbeError::Bad => 0 }
}

///|
pub fn strings(value : Int) -> String {
  let text = "value=\{value}"
  text
}

///|
pub fn pipe(value : Int) -> Int { value |> identity }

///|
pub async fn async_one() -> Int { 1 }

///|
pub async fn async_two() -> Int { async_one() }

///|
pub type ChoiceAlias = Choice

///|
pub fn alias_type(value : ChoiceAlias) -> ChoiceAlias { value }

///|
pub fn numeric_values() -> (Int64, UInt64, Double, Float, Char, Bytes) {
  (-9223372036854775808L, 18446744073709551615UL, 3.5, 2.0F, '🚀', b"\xff\x00")
}

///|
pub fn erased_error(error : Error) -> Int {
  match error { ProbeError::Bad => 1; _ => 0 }
}

///|
pub(all) struct Pair(Int, String)

///|
pub fn pairing() -> Int {
  let value = Pair(7, "tuple")
  value.0
}

///|
pub fn effect_identity(action : () -> Int raise?) -> Int raise? {
  action()
}

///|
pub fn pure_effect() -> Int { effect_identity(fn() { 1 }) }

///|
pub fn checked_effect() -> Int raise ProbeError {
  effect_identity(fn() raise ProbeError { risky(1) })
}

///|
pub fn[E : Error] typed_effect(action : () -> Int raise E) -> Int raise E { action() }
