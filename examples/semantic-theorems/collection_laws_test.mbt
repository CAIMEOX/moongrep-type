///|
priv suberror CollectionTraceFailure {
  TraceStop
}

///|
fn collection_recording_iter(trace : Array[String]) -> Iter[Int] {
  let mut value = 0
  Iter::new(() => {
    value += 1
    trace.push("pull:\{value}")
    if value <= 4 {
      Some(value)
    } else {
      None
    }
  })
}

///|
fn collection_recording_predicate(trace : Array[String]) -> (Int) -> Bool {
  trace.push("predicate factory")
  x => {
    trace.push("predicate:\{x}")
    x % 2 == 0
  }
}

///|
test "array filter count preserves source factories and predicate effects" {
  let before = []
  let after = []
  let source = fn(trace : Array[String]) {
    trace.push("source factory")
    [1, 2, 3, 4]
  }
  let a = source(before).filter(collection_recording_predicate(before)).length()
  let b = source(after).count_if(collection_recording_predicate(after))
  assert_eq(a, b)
  assert_eq(before, after)
  debug_inspect(
    before,
    content=(
      #|[
      #|  "source factory",
      #|  "predicate factory",
      #|  "predicate:1",
      #|  "predicate:2",
      #|  "predicate:3",
      #|  "predicate:4",
      #|]
    ),
  )
}

///|
test "array filter count propagates the same exception before later elements" {
  let before = []
  let after = []
  let predicate = fn(
    trace : Array[Int],
    x : Int,
  ) -> Bool raise CollectionTraceFailure {
    trace.push(x)
    if x == 3 {
      raise TraceStop
    }
    x % 2 == 0
  }
  let a = [1, 2, 3, 4].filter(x => predicate(before, x)).length() catch {
      TraceStop => -1
    }
  let b = [1, 2, 3, 4].count_if(x => predicate(after, x)) catch {
    TraceStop => -1
  }
  assert_eq(a, b)
  assert_eq(before, after)
  debug_inspect(before, content="[1, 2, 3]")
}

///|
test "iterator filter count preserves all pulls including exhaustion" {
  let before = []
  let after = []
  let a = collection_recording_iter(before)
    .filter(collection_recording_predicate(before))
    .count()
  let b = collection_recording_iter(after).count_if(
    collection_recording_predicate(after),
  )
  assert_eq(a, b)
  assert_eq(before, after)
  debug_inspect(
    before,
    content=(
      #|[
      #|  "predicate factory",
      #|  "pull:1",
      #|  "predicate:1",
      #|  "pull:2",
      #|  "predicate:2",
      #|  "pull:3",
      #|  "predicate:3",
      #|  "pull:4",
      #|  "predicate:4",
      #|  "pull:5",
      #|]
    ),
  )
}

///|
test "iterator filter next preserves short circuit and remaining input" {
  let before = []
  let after = []
  let xs = collection_recording_iter(before)
  let ys = collection_recording_iter(after)
  let a = xs.filter(collection_recording_predicate(before)).next()
  let b = ys.find_first(collection_recording_predicate(after))
  assert_eq(a, b)
  assert_eq(before, after)
  debug_inspect(
    before,
    content=(
      #|[
      #|  "predicate factory",
      #|  "pull:1",
      #|  "predicate:1",
      #|  "pull:2",
      #|  "predicate:2",
      #|]
    ),
  )
  assert_eq(xs.next(), ys.next())
  assert_eq(before, after)
}

///|
test "iterator existence preserves matching and nonmatching predicate traces" {
  for matched in [true, false] {
    let before = []
    let after = []
    let xs = collection_recording_iter(before)
    let ys = collection_recording_iter(after)
    let predicate = fn(trace : Array[String], x : Int) {
      trace.push("predicate:\{x}")
      matched && x == 2
    }
    let a = xs.find_first(x => predicate(before, x)).is_some()
    let b = ys.any(x => predicate(after, x))
    assert_eq(a, b)
    assert_eq(before, after)
    assert_eq(xs.next(), ys.next())
    assert_eq(before, after)
  }
  assert_eq(
    [1, 3].iter().find_first(x => x % 2 == 0).is_none(),
    ![1, 3].iter().any(x => x % 2 == 0),
  )
}

///|
test "iterator existence preserves predicate exceptions and pull order" {
  let before = []
  let after = []
  let predicate = fn(
    trace : Array[String],
    x : Int,
  ) -> Bool raise CollectionTraceFailure {
    trace.push("predicate:\{x}")
    if x == 2 {
      raise TraceStop
    }
    false
  }
  let a = collection_recording_iter(before)
    .find_first(x => predicate(before, x))
    .is_none() catch {
      TraceStop => false
    }
  let b = try
    !collection_recording_iter(after).any(x => predicate(after, x))
  catch {
    TraceStop => false
  }
  assert_eq(a, b)
  assert_eq(before, after)
  debug_inspect(
    before,
    content="[\"pull:1\", \"predicate:1\", \"pull:2\", \"predicate:2\"]",
  )
}

///|
test "iterator map flatten preserves factories laziness and nested pulls" {
  let before = []
  let after = []
  let source = fn(trace : Array[String]) {
    trace.push("source factory")
    collection_recording_iter(trace)
  }
  let transform = fn(trace : Array[String]) {
    trace.push("transform factory")
    fn(x : Int) {
      trace.push("transform:\{x}")
      let mut available = x % 2 == 0
      Iter::new(() => {
        trace.push("nested:\{x}")
        if available {
          available = false
          Some(x * 10)
        } else {
          None
        }
      })
    }
  }
  let a = source(before).map(transform(before)).flatten()
  let b = source(after).flat_map(transform(after))
  assert_eq(before, after)
  debug_inspect(before, content="[\"source factory\", \"transform factory\"]")
  assert_eq(a.size_hint(), b.size_hint())
  assert_eq(a.next(), b.next())
  assert_eq(before, after)
  assert_eq(a.collect(), b.collect())
  assert_eq(before, after)
  debug_inspect(
    before,
    content=(
      #|[
      #|  "source factory",
      #|  "transform factory",
      #|  "pull:1",
      #|  "transform:1",
      #|  "nested:1",
      #|  "pull:2",
      #|  "transform:2",
      #|  "nested:2",
      #|  "nested:2",
      #|  "pull:3",
      #|  "transform:3",
      #|  "nested:3",
      #|  "pull:4",
      #|  "transform:4",
      #|  "nested:4",
      #|  "nested:4",
      #|  "pull:5",
      #|]
    ),
  )
}

///|
test "array emptiness short circuit is not a filter count theorem" {
  let before = []
  let after = []
  let a = [1, 2, 3]
    .filter(x => {
      before.push(x)
      x == 1
    })
    .is_empty()
  let b = ![1, 2, 3].any(x => {
    after.push(x)
    x == 1
  })
  assert_eq(a, b)
  debug_inspect(before, content="[1, 2, 3]")
  debug_inspect(after, content="[1]")
}
