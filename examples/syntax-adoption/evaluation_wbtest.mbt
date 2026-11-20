///|
priv struct Entry {
  path : String
  revision : Int32
}

///|
test "map construction preserves duplicate string keys and their traversal order" {
  let rows : Array[Entry] = [
    { path: "a", revision: 1, },
    { path: "b", revision: 2, },
    { path: "a", revision: 3, },
  ]
  let before : Map[String, Entry] = Map([])
  for entry in rows {
    before[entry.path] = entry
  }
  let after = Map([ for entry in rows => (entry.path, entry) ])
  assert_eq(before.keys().collect(), after.keys().collect())
  assert_eq(after.keys().collect(), ["a", "b"])
  for key in before.keys() {
    assert_eq(after[key].revision, before[key].revision)
  }
  assert_eq(after["a"].revision, 3)
}

///|
test "stream plain string fields into the same HTML builder" {
  for tag in ["x", "svg:path", "é", "🚀", "x&y"] {
    let before = StringBuilder()
    before.write_string("</")
    before.write_string(tag)
    before.write_char('>')
    let after = StringBuilder()
    after <+ "</\{tag}>"
    assert_eq(before.to_string(), after.to_string())
  }
}

///|
test "descending ranges visit the same slots, including empty and early exit" {
  fn visit(xs : Array[Int32]) -> Array[Int32] {
    let seen = []
    for i in xs.length()>..0 {
      seen.push(i)
      if xs[i] < 0 {
        break
      }
    }
    seen
  }
  assert_eq(visit([]), [])
  assert_eq(visit([42]), [0])
  assert_eq(visit([3, -1, 3, 3]), [3, 2, 1])
}

///|
test "iterator literal elements run on construction, with a single traversal" {
  let calls = []
  fn record(n : Int32) -> Int32 {
    calls.push(n)
    n
  }
  let before = [record(1), record(2)].iter()
  let expected = calls.copy()
  calls.clear()
  let after = [|record(1), record(2)|]
  assert_eq(calls, expected)
  assert_eq(calls, [1, 2])
  assert_eq(after.size_hint(), before.size_hint())
  assert_eq(after.next(), before.next())
  assert_eq(after.collect(), before.collect())
  assert_eq(after.next(), None)
}

///|
test "a fallback runs only when the original operation raises" {
  fn compute(n : Int32) -> Int32 raise {
    if n == 0 {
      fail("zero")
    }
    n
  }
  let calls = []
  fn fallback(n : Int32) -> Int32 {
    calls.push(n)
    -1
  }
  for n in [3, 0] {
    let materialized : Result[Int32, Error] = Ok(compute(n)) catch {
      e => Err(e)
    }
    let before = match materialized {
      Ok(value) => value
      Err(_) => fallback(n)
    }
    let trace = calls.copy()
    calls.clear()
    let after = compute(n) catch { _ => fallback(n) }
    assert_eq(after, before)
    assert_eq(calls, trace)
    calls.clear()
  }
}

///|
test "optional listener handling always continues into the child" {
  let trace = []
  fn descend(listener : Int32?) -> Unit {
    if listener is Some(id) {
      trace.push(id)
    }
    trace.push(9)
  }
  descend(None)
  descend(Some(7))
  assert_eq(trace, [9, 7, 9])
  trace.clear()
  fn guard_at_function_scope(listener : Int32?) -> Unit {
    guard listener is Some(id) else { () }
    trace.push(id)
    trace.push(9)
  }
  guard_at_function_scope(None)
  assert_eq(trace, [])
}

///|
test "optional spread preserves config lookup and path precedence" {
  let trace = []
  fn lookup(base : String?) -> String? {
    trace.push("lookup")
    base
  }
  fn build(base : String) -> String {
    trace.push("path")
    base + "/git/config"
  }
  for base in ([None, Some("/xdg")] : Array[String?]) {
    let before = []
    if lookup(base) is Some(path) {
      before.push(build(path))
    }
    before.push("/home/.gitconfig")
    let expected_trace = trace.copy()
    trace.clear()
    let after = [
      ..if lookup(base) is Some(path) {
        [build(path)]
      },
      "/home/.gitconfig",
    ]
    assert_eq(after, before)
    assert_eq(trace, expected_trace)
    trace.clear()
  }
}
