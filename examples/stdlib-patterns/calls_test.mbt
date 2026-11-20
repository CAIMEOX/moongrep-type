///|
test "presence tests include empty substrings and stored None" {
  for text in ["", "a🚀bc"] {
    for needle in ["", "🚀", "ab", "z"] {
      assert_eq(text.find(needle) is Some(_), text.contains(needle))
      assert_eq(text.strip_prefix(needle) is Some(_), text.has_prefix(needle))
      assert_eq(text.strip_suffix(needle) is None, !text.has_suffix(needle))
    }
  }
  let m : Map[String, Int32?] = { "present": None }
  for key in ["present", "missing"] {
    assert_eq(m.get(key) is Some(_), m.contains(key))
  }
  let counts = { "a": 3 }
  for key in ["a", "b"] {
    assert_eq(counts.get(key).unwrap_or(0), counts.get_or_default(key, 0))
  }
}

///|
test "nth preserves the next pull even on exhaustion" {
  for n in [0, 1, 3, 8] {
    let a = [1, 2, 3].iter()
    let b = [1, 2, 3].iter()
    assert_eq(a.drop(n).next(), b.nth(n))
    assert_eq(a.next(), b.next())
  }
  let a = [1, 2].iter()
  let b = [1, 2].iter()
  assert_eq(a.drop(-1).next(), Some(1))
  assert_eq(b.nth(-1), None)
}

///|
test "predicate search and any stop after the same call" {
  for values in [[1, 2, 3], [1], []] {
    let before = []
    let after = []
    let hit = values.search_by(x => {
        before.push(x)
        x == 2
      })
      is Some(_)
    assert_eq(
      hit,
      values.any(x => {
        after.push(x)
        x == 2
      }),
    )
    assert_eq(before, after)
    assert_eq(values.search(1) is Some(_), values.contains(1))
    assert_eq(values.length() == 0, values.is_empty())
  }
}

///|
test "a mutating fallback can change the result when moved before lookup" {
  let old_map : Map[String, Int32] = Map([])
  let new_map : Map[String, Int32] = Map([])
  let original = old_map
    .get("k")
    .unwrap_or(
      {
        old_map.set("k", 1)
        0
      },
    )
  let reordered = new_map.get_or_default(
    "k",
    {
      new_map.set("k", 1)
      0
    },
  )
  assert_eq(original, 0)
  assert_eq(reordered, 1)
}
