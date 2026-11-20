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

///|
pub(all) enum ParseStop {
  Miss
  Committed
  Need(Int32)
}

///|
pub fn optional_token(
  result : Result[(Char, Int32), ParseStop],
  start : Int32,
) -> Result[(Char?, Int32), ParseStop] {
  match result {
    Ok((token, next)) => Ok((Some(token), next))
    Err(Miss) => Ok((None, start))
    Err(error) => Err(error)
  }
}

///|
pub fn keep_capacity(xs : Array[Int32], keep : (Int32) -> Bool) -> Array[Int32] {
  let kept : Array[Int32] = Array(capacity=xs.length())
  for x in xs {
    if keep(x) {
      kept.push(x)
    }
  }
  kept
}

///|
pub fn flush_callbacks(queue : Array[() -> Unit]) -> Unit {
  while queue.length() > 0 {
    let run = queue.remove(0)
    run()
  }
}

///|
pub fn read_minimum(
  minimum : Int32,
  read : () -> (Int32, Bool),
) -> (Int32, Bool) {
  let mut total = 0
  let mut eof = false
  while total < minimum && !eof {
    let (n, stopped) = read()
    total += n
    eof = stopped
  }
  (total, total < minimum && eof)
}

///|
pub fn follow_path(
  keys : Array[Char],
  edges : Map[(Int32, Char), Int32],
  values : Map[Int32, String],
) -> String? {
  for key in keys; node = 0 {
    match edges.get((node, key)) {
      None => break None
      Some(next) => continue next
    }
  } nobreak {
    values.get(node)
  }
}

///|
pub fn read_without_caching(
  table : Map[Int32, Int32],
  fallback : () -> Int32,
) -> Int32 {
  table.get(1).unwrap_or_else(fallback)
}
