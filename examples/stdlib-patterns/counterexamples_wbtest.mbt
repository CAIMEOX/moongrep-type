///|
#inline(never)
fn signal_value(n : Int32) -> Result[Int32, String] {
  Ok(n)
}

///|
#cfg(any(target="wasm", target="native"))
test "using the original Result suppresses an identity-sensitive notification" {
  let value = signal_value(42)
  let delivered = []
  let mut notifications = 0
  let notify = (next : Result[Int32, String]) => {
    delivered.push(next)
    if !physical_equal(value, next) {
      notifications += 1
    }
  }
  notify_if_rebuilt(value, notify)
  assert_eq(notifications, 1)
  notify(value)
  assert_eq(notifications, 1)
  assert_eq(delivered, [value, value])
  assert_false(same_optional_box(Some(42L)))
}

///|
test "an optional parser rewinds only a recoverable miss" {
  assert_true(optional_token(Ok(('x', 8)), 7) is Ok((Some('x'), 8)))
  assert_true(optional_token(Err(Miss), 7) is Ok((None, 7)))
  assert_true(optional_token(Err(Committed), 7) is Err(Committed))
  assert_true(optional_token(Err(Need(3)), 7) is Err(Need(3)))
}

///|
test "the caller observes reserved space even when no input passes" {
  let xs = [1, 2, 3, 4, 5]
  let kept = keep_capacity(xs, _ => false)
  assert_true(kept.is_empty())
  assert_true(kept.capacity() >= xs.length())
}

///|
test "a callback can enqueue more work during a flush" {
  let trace = []
  let queue : Array[() -> Unit] = []
  queue.push(() => {
    trace.push(1)
    queue.push(() => trace.push(2))
  })
  flush_callbacks(queue)
  assert_eq(trace, [1, 2])
  assert_true(queue.is_empty())
}

///|
test "data in the final read counts before EOF is interpreted" {
  assert_eq(read_minimum(2, () => (2, true)), (2, false))
  assert_eq(read_minimum(3, () => (2, true)), (2, true))
  let mut pulls = 0
  let read = () => {
    pulls += 1
    (1, pulls == 2)
  }
  assert_eq(read_minimum(4, read), (2, true))
  assert_eq(pulls, 2)
}

///|
test "a prefix can exist without a terminal value" {
  let edges = Map([((0, 'a'), 1), ((1, 'b'), 2)])
  let values = { 2: "leaf" }
  assert_eq(follow_path(['a', 'b'], edges, values), Some("leaf"))
  assert_eq(follow_path(['a'], edges, values), None)
  assert_eq(follow_path(['x'], edges, values), None)
}

///|
test "a lazy fallback can run twice while get_or_init inserts on the first miss" {
  let table : Map[Int32, Int32] = Map([])
  let mut calls = 0
  let next = () => {
    calls += 1
    calls
  }
  assert_eq(read_without_caching(table, next), 1)
  assert_eq(read_without_caching(table, next), 2)
  assert_true(table.is_empty())
  calls = 0
  assert_eq(table.get_or_init(1, next), 1)
  assert_eq(table.get_or_init(1, next), 1)
  assert_eq(table.get(1), Some(1))
}
