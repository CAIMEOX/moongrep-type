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
