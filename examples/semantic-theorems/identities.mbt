///|
pub fn identity_option_map(value : Int?) -> Int? {
  value.map(x => x)
}

///|
pub fn identity_result_map(value : Result[Int, String]) -> Result[Int, String] {
  value.map(x => x)
}

///|
pub fn identity_option_bind(value : Int?) -> Int? {
  value.bind(x => Some(x))
}

///|
pub fn identity_result_bind(value : Result[Int, String]) -> Result[Int, String] {
  value.bind(x => Ok(x))
}

///|
pub fn identity_some_unwrap(value : Int) -> Int {
  Option::Some(value).unwrap()
}

///|
pub fn identity_ok_unwrap(value : Int) -> Int {
  (Ok(value) : Result[Int, String]).unwrap()
}

///|
pub fn identity_err_unwrap(value : String) -> String {
  (Err(value) : Result[Int, String]).unwrap_err()
}

///|
pub fn[T, E] identity_result_generic(value : Result[T, E]) -> Result[T, E] {
  value.map(item => item)
}

///|
pub fn identity_unicode(value : Int?) -> (String, Int?) {
  ("🚀", value.bind(item => Some(item)))
}

///|
// The callback returns a different binding, even though its type is identical.
pub fn identity_negative_other_binding(value : Int?, other : Int) -> Int? {
  value.map(_item => other)
}

///|
pub fn identity_negative_shadowing(value : Int?) -> Int? {
  value.map(item => {
    let item = item + 1
    item
  })
}

///|
pub fn identity_negative_effect(value : Int?, calls : Array[Int]) -> Int? {
  value.map(item => {
    calls.push(item)
    item
  })
}

///|
pub fn identity_negative_array(value : Array[Int]) -> Array[Int] {
  value.map(item => item)
}

///|
pub enum IdentityLookalike {
  Some(Int)
  Ok(Int)
  Err(String)
}

///|
pub fn IdentityLookalike::unwrap(
  self : IdentityLookalike,
  msg~ : String = "",
) -> Int {
  ignore(msg)
  match self {
    Some(value) | Ok(value) => value
    Err(_) => 0
  }
}

///|
pub fn identity_negative_foreign_constructor(value : Int) -> Int {
  IdentityLookalike::Some(value).unwrap()
}

///|
pub fn identity_negative_unwrap_argument(
  value : Int,
  calls : Array[Int],
) -> Int {
  IdentityLookalike::Ok(value).unwrap(
    msg={
      calls.push(value)
      "explicit argument is evaluated"
    },
  )
}

///|
pub fn IdentityLookalike::unwrap_err(self : IdentityLookalike) -> String {
  match self {
    Err(error) => error
    _ => ""
  }
}

///|
pub fn identity_negative_foreign_error(error : String) -> String {
  IdentityLookalike::Err(error).unwrap_err()
}
