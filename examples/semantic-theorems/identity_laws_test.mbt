///|
test "Option and Result map identity preserve every constructor and payload alias" {
  let payload = [1]
  let optional = Some(payload)
  let mapped = optional.map(x => x)
  mapped.unwrap().push(2)
  debug_inspect(optional, content="Some([1, 2])")
  assert_eq((None : Int?).map(x => x), None)
  assert_eq((Ok(4) : Result[Int, String]).map(x => x), Ok(4))
  assert_eq((Err("failure") : Result[Int, String]).map(x => x), Err("failure"))
}

///|
test "Option and Result bind right identity preserve success failure and aliases" {
  let payload = [1]
  let optional = Some(payload)
  let bound = optional.bind(x => Some(x))
  bound.unwrap().push(2)
  debug_inspect(optional, content="Some([1, 2])")
  assert_eq((None : Int?).bind(x => Some(x)), None)
  assert_eq((Ok(4) : Result[Int, String]).bind(x => Ok(x)), Ok(4))
  assert_eq(
    (Err("failure") : Result[Int, String]).bind(x => Ok(x)),
    Err("failure"),
  )
}

///|
test "constructor unwrap evaluates a payload once" {
  let trace : Array[Int] = []
  let payload = () => {
    trace.push(trace.length())
    trace
  }
  let optional = Some(payload()).unwrap()
  let success = (Ok(payload()) : Result[Array[Int], String]).unwrap()
  let failure = (Err(payload()) : Result[String, Array[Int]]).unwrap_err()
  debug_inspect(trace, content="[0, 1, 2]")
  optional.push(3)
  success.push(4)
  failure.push(5)
  debug_inspect(trace, content="[0, 1, 2, 3, 4, 5]")
}

///|
test "negative identities preserve effects and independent Array storage" {
  let calls = []
  assert_eq(
    @semantic-theorems-example.identity_negative_effect(Some(7), calls),
    Some(7),
  )
  debug_inspect(calls, content="[7]")
  assert_eq(
    @semantic-theorems-example.identity_negative_shadowing(Some(7)),
    Some(8),
  )
  assert_eq(
    @semantic-theorems-example.identity_negative_other_binding(Some(7), 9),
    Some(9),
  )
  let source = [1]
  let copied = @semantic-theorems-example.identity_negative_array(source)
  copied.push(2)
  debug_inspect(source, content="[1]")
  ignore(@semantic-theorems-example.identity_negative_unwrap_argument(5, calls))
  debug_inspect(calls, content="[7, 5]")
}
