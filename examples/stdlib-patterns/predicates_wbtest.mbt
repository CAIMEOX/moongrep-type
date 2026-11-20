///|
test "collection predicates retain early exit, order, and the rest of the iterator" {
  for values in [[], [1, -2, -3], [2, 3]] {
    let seen : Array[Int32] = []
    let negative = (v : Int32) => {
      seen.push(v)
      v < 0
    }
    let from_loop = any_item(values, negative)
    let trace = seen.copy()
    seen.clear()
    assert_eq(from_loop, values.any(negative))
    assert_eq(trace, seen)
    seen.clear()
    let lhs = values.iter()
    let rhs = values.iter()
    let from_loop = all_items(lhs, negative)
    let trace = seen.copy()
    seen.clear()
    assert_eq(from_loop, rhs.all(negative))
    assert_eq(trace, seen)
    assert_eq(lhs.collect(), rhs.collect())
    assert_eq(guarded_all(values[:], negative), values[:].all(negative))
    let lhs = values.iter()
    let rhs = values.iter()
    assert_eq(first_negative(lhs), rhs.find_first(x => x < 0))
    assert_eq(lhs.collect(), rhs.collect())
  }
}

///|
test "ASCII predicates cover endpoints, neighbors and non-ASCII characters" {
  for
    c in [
      '/', '0', '5', '9', ':', '@', 'A', 'M', 'Z', '[', '`', 'a', 'm', 'z', '{',
      '９', 'é', '𐐀',
    ] {
    assert_eq(digit(c), c.is_ascii_digit())
    assert_eq(lowercase(c), c.is_ascii_lowercase())
    assert_eq(uppercase(c), c.is_ascii_uppercase())
  }
}
