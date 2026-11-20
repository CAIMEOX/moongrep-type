///|
pub fn identity_option_map(value : Int32?) -> Bool {
  value.map(x => x) is Some(_)
}

///|
pub fn identity_result_map(value : Result[Int32, String]) -> Int32 {
  value.map(x => x).unwrap_or(0)
}

///|
pub fn identity_option_bind(value : Int32?) -> Int32 {
  value.bind(x => Some(x)).unwrap_or(0)
}

///|
pub fn identity_result_bind(value : Result[Int32, String]) -> Bool {
  value.bind(x => Ok(x)) is Err(_)
}

///|
pub fn identity_some_unwrap(value : Int32) -> Int32 {
  Option::Some(value).unwrap()
}

///|
pub fn identity_ok_unwrap(value : Int32) -> Int32 {
  (Ok(value) : Result[Int32, String]).unwrap()
}

///|
pub fn identity_err_unwrap(value : String) -> String {
  (Err(value) : Result[Int32, String]).unwrap_err()
}

///|
pub fn[T, E] identity_result_generic(value : Result[T, E]) -> Bool {
  match value.map(item => item) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
pub fn identity_unicode(value : Int32?) -> (String, Bool) {
  ("🚀", value.bind(item => Some(item)) is None)
}

///|
// The callback returns a different binding, even though its type is identical.
pub fn identity_negative_other_binding(value : Int32?, other : Int32) -> Int32? {
  value.map(_item => other)
}

///|
pub fn identity_negative_shadowing(value : Int32?) -> Int32? {
  value.map(item => {
    let item = item + 1
    item
  })
}

///|
pub fn identity_negative_effect(value : Int32?, calls : Array[Int32]) -> Int32? {
  value.map(item => {
    calls.push(item)
    item
  })
}

///|
pub fn identity_negative_array(value : Array[Int32]) -> Array[Int32] {
  value.map(item => item)
}

///|
pub enum IdentityLookalike {
  Some(Int32)
  Ok(Int32)
  Err(String)
}

///|
pub fn IdentityLookalike::unwrap(
  self : IdentityLookalike,
  msg~ : String = "",
) -> Int32 {
  ignore(msg)
  match self {
    Some(value) | Ok(value) => value
    Err(_) => 0
  }
}

///|
pub fn identity_negative_foreign_constructor(value : Int32) -> Int32 {
  IdentityLookalike::Some(value).unwrap()
}

///|
pub fn identity_negative_unwrap_argument(
  value : Int32,
  calls : Array[Int32],
) -> Int32 {
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
