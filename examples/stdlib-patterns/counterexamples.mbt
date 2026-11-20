///|
#locals(p)
pub fn[T] local_predicate(xs : Array[T], p : (T) -> Bool) -> Bool {
  for x in xs {
    if p(x) {
      break true
    }
  } nobreak {
    false
  }
}

///|
#locals(p)
pub fn[T] local_search(xs : Iter[T], p~ : (T) -> Bool) -> T? {
  for x in xs {
    if p(x) {
      break Some(x)
    }
  } nobreak {
    None
  }
}

///|
#locals(f)
pub fn[A, B] local_transform(value : A?, f : (A) -> B) -> B? {
  match value {
    Some(x) => Some(f(x))
    None => None
  }
}

///|
#locals(read)
pub fn[T, E] local_default(value : Result[T, E], read : () -> T) -> T {
  match value {
    Ok(x) => x
    Err(_) => read()
  }
}

///|
pub fn notify_if_rebuilt(
  value : Result[Int32, String],
  notify : (Result[Int32, String]) -> Unit,
) -> Unit {
  notify(value.map(x => x))
}

///|
pub fn same_optional_box(value : Int64?) -> Bool {
  physical_equal(value, value.bind(x => Some(x)))
}

///|
pub fn export_nested(value : Int32??) -> Int32?? {
  value.map(x => x)
}

///|
pub fn match_whole(value : Result[Int32, String]) -> Bool {
  match value.bind(x => Ok(x)) {
    Ok(_) as rebuilt => physical_equal(value, rebuilt)
    _ => false
  }
}
