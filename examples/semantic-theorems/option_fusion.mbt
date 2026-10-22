///|
pub fn theorem_option_map(
  o : Int?,
  first : (Int) -> Int,
  second : (Int) -> Int,
) -> Int? {
  o.map(first).map(second)
}

///|
pub fn theorem_result_map(
  r : Result[Int, String],
  first : (Int) -> Int,
  second : (Int) -> Int,
) -> Result[Int, String] {
  r.map(first).map(second)
}

///|
pub fn theorem_result_map_err(
  r : Result[Int, String],
  first : (String) -> Int,
  second : (Int) -> Bool,
) -> Result[Int, Bool] {
  r.map_err(first).map_err(second)
}

///|
pub fn theorem_option_bind_map(o : Int?) -> Int? {
  o.bind(x => Some(x + 1))
}

///|
pub fn theorem_result_bind_map(r : Result[Int, String]) -> Result[Int, String] {
  r.bind(x => Ok(x + 1))
}

///|
pub fn theorem_result_map_flatten(
  r : Result[Int, String],
  f : (Int) -> Result[Int, String],
) -> Result[Int, String] {
  r.map(f).flatten()
}

///|
pub fn theorem_option_filter(
  o : Int?,
  first : (Int) -> Bool,
  second : (Int) -> Bool,
) -> Int? {
  o.filter(first).filter(second)
}

///|
pub fn theorem_option_default(
  o : Int?,
  transform : (Int) -> String,
  fallback : () -> String,
) -> String {
  o.map(transform).unwrap_or_else(fallback)
}

///|
pub fn theorem_option_map_raising(
  o : Int?,
  first : (Int) -> Int raise,
  second : (Int) -> Int raise,
) -> Int? raise {
  o.map(first).map(second)
}

///|
pub fn theorem_option_map_return(o : Int?) -> Int? {
  o.map(x => { return x + 1 }).map(x => x * 2)
}

///|
pub fn theorem_option_bind_raise(
  o : Int?,
  f : (Int) -> Int raise,
) -> Int? raise {
  o.bind(x => Some(f(x)))
}

///|
pub fn theorem_option_bind_mutation(o : Int?, events : Array[Int]) -> Int? {
  o.bind(x => {
    Some(
      {
        events.push(x)
        x + 1
      },
    )
  })
}

///|
pub fn theorem_fusion_factory() -> (Int) -> Int {
  x => x + 1
}

///|
pub fn theorem_result_factory() -> (Int) -> Result[Int, String] {
  x => Ok(x + 1)
}

///|
pub fn theorem_result_flatten_factory(
  r : Result[Int, String],
) -> Result[Int, String] {
  r.map(theorem_result_factory()).flatten()
}

///|
// Negative: callback factory construction would move into the fused callback.
pub fn no_option_fusion_factory(o : Int?) -> Int? {
  o.map(theorem_fusion_factory()).map(x => x * 2)
}

///|
// Negative: the first callback changes the function read by the second map.
pub fn no_option_fusion_mutable(o : Int?) -> Int? {
  let mut second : (Int) -> Int = x => x + 1
  o
  .map(x => {
    second = y => y * 2
    x
  })
  .map(second)
}

///|
// Negative: a fusion callback captures a mutable local value.
pub fn no_option_fusion_capture(o : Int?) -> Int? {
  let mut factor = 2
  factor = factor + 1
  o.map(x => x + 1).map(x => x * factor)
}

///|
// Negative: this default is eager, with a different evaluation order.
pub fn no_option_eager_default(
  o : Int?,
  f : (Int) -> Int,
  fallback : () -> Int,
) -> Int {
  o.map(f).unwrap_or(fallback())
}

///|
// Negative: bind can return None, so replacing bind by map is invalid.
pub fn no_option_bind_return(o : Int?) -> Int? {
  o.bind(x => {
    Some(
      {
        if x < 0 {
          return None
        }
        x + 1
      },
    )
  })
}

///|
// Negative: the wrapper is Err, not Ok.
pub fn no_result_bind_error(r : Result[Int, String]) -> Result[Int, String] {
  r.bind(x => Err(x.to_string()))
}

///|
// Negative: a return after a local function still exits the bind callback.
pub fn no_option_bind_after_local_function(o : Int?) -> Int? {
  o.bind(x => {
    Some(
      {
        fn inner(y : Int) -> Int {
          return y + 1
        }
        if x < 0 {
          return None
        }
        inner(x)
      },
    )
  })
}

///|
// Negative: recursive function declarations do not hide a following return.
pub fn no_option_bind_after_recursive_function(o : Int?) -> Int? {
  o.bind(x => {
    Some(
      {
        letrec inner = fn(y : Int) -> Int {
          if y > 0 {
            return inner(y - 1)
          }
          return y + 1
        }
        if x < 0 {
          return None
        }
        inner(x)
      },
    )
  })
}
