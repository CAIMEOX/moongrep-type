///|
pub fn bumped(n : Int32?) -> Int32? {
  match n {
    Some(x) => Some(x + 1)
    None => None
  }
}

///|
pub fn[A, B] optional_lookup(key : A?, lookup : (A) -> B? raise?) -> B? raise? {
  match key {
    None => None
    Some(x) => lookup(x)
  }
}

///|
pub fn optional_default(n : Int32?, fallback : Int32) -> Int32 {
  match n {
    Some(x) => x
    None => fallback
  }
}

///|
pub fn optional_read(n : Int32?, read : () -> Int32 raise?) -> Int32 raise? {
  match n {
    None => read()
    Some(x) => x
  }
}

///|
pub fn[A, B, E] convert(
  r : Result[A, E],
  convert : (A) -> B raise?,
) -> Result[B, E] raise? {
  match r {
    Err(e) => Err(e)
    Ok(x) => Ok(convert(x))
  }
}

///|
pub fn[A, E, F] convert_error(
  r : Result[A, E],
  translate : (E) -> F raise?,
) -> Result[A, F] raise? {
  match r {
    Ok(x) => Ok(x)
    Err(e) => Err(translate(e))
  }
}

///|
pub fn[A, B, E] continue_result(
  r : Result[A, E],
  step : (A) -> Result[B, E] raise?,
) -> Result[B, E] raise? {
  match r {
    Ok(x) => step(x)
    Err(e) => Err(e)
  }
}

///|
pub fn[A, E] keep_success(r : Result[A, E]) -> A? {
  match r {
    Err(_) => None
    Ok(x) => Some(x)
  }
}

///|
pub fn result_default(r : Result[Int32, String]) -> Int32 {
  match r {
    Err(_) => 42
    Ok(x) => x
  }
}

///|
pub fn result_read(
  r : Result[Int32, String],
  read : () -> Int32 raise?,
) -> Int32 raise? {
  match r {
    Ok(x) => x
    Err(_) => read()
  }
}
