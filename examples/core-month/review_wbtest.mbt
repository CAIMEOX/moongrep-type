///|
test "creating a predicate can change the array between creating and consuming the iterator" {
  fn factory(xs : Array[Int32], seen : Array[Int32]) -> (Int32) -> Bool {
    xs.push(2)
    x => {
      seen.push(x)
      true
    }
  }
  let xs = [1]
  let before = []
  assert_true(xs.iter().all(factory(xs, before)))
  let ys = [1]
  let after = []
  assert_true(ys.all(factory(ys, after)))
  assert_eq((before, after), ([1], [1, 2]))
}

///|
test "makei can drop a seed effect even when both arrays are empty" {
  let mut seeds = 0
  let seed = () => {
    seeds += 1
    0
  }
  let a = FixedArray::make(0, seed())
  let b = FixedArray::makei(0, i => i)
  assert_eq(a.length(), b.length())
  assert_eq(seeds, 1)
}

///|
test "a split needs the complete delimiter and the same empty sides" {
  for text in ["=x", "x=", "=", "x=y=z", "x"] {
    assert_eq(cookie_item(text[:]), text.split_once("="))
  }
  let text = "x::y"
  let i = text.find("::").unwrap()
  assert_eq(text[i + 1:], ":y")
  assert_eq(text.split_once("::").unwrap().1, "y")
  assert_eq(text.split_at(i).1, "::y")
}

///|
test "replacing an exclusive upper bound plus one can change behavior at the integer limit" {
  let hi = 2147483647
  let old = for i in hi..<(hi + 1) {
    break Some(i)
  } nobreak {
    None
  }
  let new = for i in hi..<=hi {
    break Some(i)
  } nobreak {
    None
  }
  assert_eq((old, new), (None, Some(hi)))
}
