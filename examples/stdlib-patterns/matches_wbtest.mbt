///|
test "fallbacks and transforms run only in the selected branch" {
  let calls : Array[String] = []
  let read = () => {
    calls.push("read")
    9
  }
  let values : Array[Int32?] = [None, Some(4)]
  for n in values {
    let original = optional_read(n, read)
    let trace = calls.copy()
    calls.clear()
    assert_eq(original, n.unwrap_or_else(() => read()))
    assert_eq(trace, calls)
    calls.clear()
    assert_eq(optional_default(n, 9), n.unwrap_or(9))
    assert_eq(bumped(n), n.map(x => x + 1))
    fn step(x : Int32) -> Int32? {
      calls.push("step")
      if x == 4 {
        None
      } else {
        Some(x)
      }
    }
    let chained = optional_lookup(n, step)
    let seen = calls.copy()
    calls.clear()
    assert_eq(chained, n.bind(x => step(x)))
    assert_eq(seen, calls)
    calls.clear()
  }
  let inputs : Array[Result[Int32, String]] = [Ok(4), Err("missing")]
  for r in inputs {
    assert_eq(keep_success(r), r.to_option())
    assert_eq(convert(r, n => n * 2), r.map(n => n * 2))
    assert_eq(convert_error(r, s => s + "!"), r.map_err(s => s + "!"))
    fn step(n : Int32) -> Result[String, String] {
      calls.push("step")
      Ok(n.to_string())
    }
    let chained = continue_result(r, step)
    let seen = calls.copy()
    calls.clear()
    assert_eq(chained, r.bind(x => step(x)))
    assert_eq(seen, calls)
    calls.clear()
    assert_eq(result_default(r), r.unwrap_or(42))
    let original = result_read(r, read)
    let trace = calls.copy()
    calls.clear()
    assert_eq(original, r.unwrap_or_else(() => read()))
    assert_eq(trace, calls)
    calls.clear()
  }
}

///|
test "conversion preserves a successful None and a raised fallback" {
  let nested : Result[Int32?, String] = Ok(None)
  assert_eq(keep_success(nested), Some(None))
  fn read() -> Int32 raise {
    fail("missing")
  }
  assert_eq(result_read(Ok(3), read), 3)
  assert_eq((Ok(3) : Result[Int32, String]).unwrap_or_else(() => read()), 3)
  let original = result_read(Err("e"), read) catch { _ => -1 }
  let standard = (Err("e") : Result[Int32, String]).unwrap_or_else(() => read()) catch {
    _ => -1
  }
  assert_eq((original, standard), (-1, -1))
}
