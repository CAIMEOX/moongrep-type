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
