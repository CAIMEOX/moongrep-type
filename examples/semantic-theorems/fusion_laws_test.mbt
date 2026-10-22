///|
test "Option and Result map fusion preserve effects for every branch" {
  for option in [Some(2), None] {
    let events : Array[String] = []
    let first = x => {
      events.push("first")
      x + 1
    }
    let second = x => {
      events.push("second")
      x * 2
    }
    let before = option.map(first).map(second)
    let trace = events.copy()
    events.clear()
    let after = option.map(x => second(first(x)))
    assert_eq(before, after)
    assert_eq(trace, events)
  }
  for result in [Ok(2), Err("error")] {
    let events : Array[String] = []
    let first = x => {
      events.push("first")
      x + 1
    }
    let second = x => {
      events.push("second")
      x * 2
    }
    let before = result.map(first).map(second)
    let trace = events.copy()
    events.clear()
    let after = result.map(x => second(first(x)))
    assert_eq(before, after)
    assert_eq(trace, events)
  }
}

///|
test "Result map_err fusion retains success and error evaluation order" {
  for result in [Ok(2), Err("error")] {
    let events : Array[String] = []
    let first = (message : String) => {
      events.push("first")
      message.length()
    }
    let second = size => {
      events.push("second")
      size > 0
    }
    let before = result.map_err(first).map_err(second)
    let trace = events.copy()
    events.clear()
    let after = result.map_err(error => second(first(error)))
    assert_eq(before, after)
    assert_eq(trace, events)
  }
}

///|
test "Option and Result bind wrapping is map with the same callback effects" {
  for option in [Some(2), None] {
    let events : Array[Int] = []
    let before = option.bind(x => {
      Some(
        {
          events.push(x)
          x + 1
        },
      )
    })
    let trace = events.copy()
    events.clear()
    let after = option.map(x => {
      events.push(x)
      x + 1
    })
    assert_eq(before, after)
    assert_eq(trace, events)
  }
  for result in [Ok(2), Err("error")] {
    let events : Array[Int] = []
    let before = result.bind(x => {
      Ok(
        {
          events.push(x)
          x + 1
        },
      )
    })
    let trace = events.copy()
    events.clear()
    let after = result.map(x => {
      events.push(x)
      x + 1
    })
    assert_eq(before, after)
    assert_eq(trace, events)
  }
}

///|
test "Result map flatten preserves both errors and factory evaluation" {
  for result in [Ok(2), Ok(-1), Err("outer")] {
    let events : Array[String] = []
    let factory = () => {
      events.push("factory")
      x => {
        events.push("callback")
        if x < 0 {
          Err("inner")
        } else {
          Ok(x + 1)
        }
      }
    }
    let before = result.map(factory()).flatten()
    let trace = events.copy()
    events.clear()
    let after = result.bind(factory())
    assert_eq(before, after)
    assert_eq(trace, events)
  }
}

///|
test "Option filter fusion preserves short circuit effects" {
  for option in [Some(-1), Some(0), Some(2), None] {
    let events : Array[String] = []
    let first = x => {
      events.push("first")
      x >= 0
    }
    let second = x => {
      events.push("second")
      x > 0
    }
    let before = option.filter(first).filter(second)
    let trace = events.copy()
    events.clear()
    let after = option.filter(x => first(x) && second(x))
    assert_eq(before, after)
    assert_eq(trace, events)
  }
}

///|
test "Option map default fusion keeps the fallback lazy" {
  for option in [Some(2), None] {
    let events : Array[String] = []
    let transform = x => {
      events.push("map")
      x + 1
    }
    let fallback = () => {
      events.push("default")
      99
    }
    let before = option.map(transform).unwrap_or_else(fallback)
    let trace = events.copy()
    events.clear()
    let after = option.map_or_else(fallback, transform)
    assert_eq(before, after)
    assert_eq(trace, events)
  }
  // The superficially similar eager-default fusion is not a theorem.
  let events : Array[String] = []
  let transform = x => {
    events.push("map")
    x + 1
  }
  let fallback = () => {
    events.push("default")
    99
  }
  ignore(Some(2).map(transform).unwrap_or(fallback()))
  assert_eq(events, ["map", "default"])
  events.clear()
  ignore(Some(2).map_or(fallback(), transform))
  assert_eq(events, ["default", "map"])
}

///|
test "Option map fusion propagates either checked callback error in order" {
  for mode in 0..<2 {
    for option in [Some(2), None] {
      let events : Array[String] = []
      let first = x => {
        events.push("first")
        if mode == 0 {
          fail("first")
        } else {
          x + 1
        }
      }
      let second = x => {
        events.push("second")
        if mode == 1 {
          fail("second")
        } else {
          x * 2
        }
      }
      let before = Ok(option.map(first).map(second)) catch {
        _ => Err("raised")
      }
      let trace = events.copy()
      events.clear()
      let after = Ok(option.map(x => second(first(x)))) catch {
        _ => Err("raised")
      }
      assert_eq(before, after)
      assert_eq(trace, events)
    }
  }
}
