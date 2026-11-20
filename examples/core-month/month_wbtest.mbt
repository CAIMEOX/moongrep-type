///|
test "finiteness covers signed zero, subnormals, infinities and NaN payloads" {
  for
    bits in [
      0UL, 0x8000_0000_0000_0000UL, 1UL, 0x7fef_ffff_ffff_ffffUL, 0x7ff0_0000_0000_0000UL,
      0xfff0_0000_0000_0000UL, 0x7ff8_0000_0000_0042UL,
    ] {
    let x = bits.reinterpret_as_double()
    assert_eq(nonfinite(x), !x.is_finite())
    assert_eq(special(x), !x.is_finite() || x == 0.0)
  }
  for
    bits in [
      0, 0x8000_0000, 1, 0x7f7f_ffff, 0x7f80_0000, 0xff80_0000, 0x7fc0_0042,
    ] {
    let x = @float.Float::reinterpret_from_int(bits)
    assert_eq(finite_float(x), x.is_finite())
  }
}

///|
test "direct Iter traversal preserves the exit value and the caller's next pull" {
  for items in [[], [0, 1], [0, 2, 3]] {
    let a = items.iter()
    let b = items.iter()
    let before = drain_until(a, x => x == 2)
    let after = for x in b {
      if x == 2 {
        break Some(x)
      }
    } nobreak {
      None
    }
    assert_eq(before, after)
    assert_eq(a.collect(), b.collect())
  }
  let mut calls = 0
  let make = () => {
    calls += 1
    if calls <= 2 {
      [|calls|]
    } else {
      [||]
    }
  }
  let seen = []
  while make().next() is Some(x) {
    seen.push(x)
  }
  assert_eq((seen, calls), ([1, 2], 3))
}

///|
test "single-element text and byte iteration includes supplementary characters and byte zero" {
  let seen = []
  let view = "xA🚀é!"[1:5]
  visit_text(view, x => seen.push(x))
  assert_eq(seen, [ for c in view => c ])
  assert_eq(seen, ['A', '🚀', 'é'])
  let bytes = b"\x00\x80\xff"
  let seen = []
  visit_bytes(bytes, x => seen.push(x))
  assert_eq(seen, [ for b in bytes => b ])
}

///|
test "an omitted end retains slice boundaries and an effectful start is a counterexample" {
  let input : MatchInput = { text: "xA🚀é!"[1:5], }
  for i in [-3, 0, 1, 2, 3, 4, 9] {
    assert_eq(input.tail(i), input.text[i:])
  }
  let s : Source = { text: "abcd", }
  assert_eq(changes_field(s), "a")
  let t : Source = { text: "abcd", }
  assert_eq(
    t.text[{
      t.text = "z"
      0
    }:],
    "abcd",
  )
}

///|
test "pure template holes preserve output; reading the destination sees a different prefix" {
  let old = StringBuilder()
  let new = StringBuilder()
  write_key(old, 42, "é🚀")
  new <+ "key=\{42} name=\{"é🚀"}"
  assert_eq(old.to_string(), new.to_string())
  let a = StringBuilder()
  let b = StringBuilder()
  a.write_string("A")
  b.write_string("A")
  reads_builder(a)
  b <+ "prefix\{b.to_string()}"
  assert_eq(a.to_string(), "AprefixA")
  assert_eq(b.to_string(), "AprefixAprefix")
}

///|
test "integer extrema preserve ties and overflow of the original arithmetic" {
  for a in [-2147483648, -1, 0, 1, 2147483647] {
    for b in [-1, 0, 1] {
      assert_eq(distance_candidates(a, b, 0), a.min(b).min(0))
      assert_eq(lower_bound(a, b), (a - b).max(1))
      assert_eq(raise_floor(a, b), a.max(b))
    }
  }
  assert_eq(
    unsigned_larger(0UL, 0xffff_ffff_ffff_ffffUL),
    0xffff_ffff_ffff_ffffUL,
  )
  let nan = 0x7ff8_0000_0000_0042UL.reinterpret_as_double()
  assert_true(floating_bound(1.0, nan).is_nan())
  assert_eq(1.0.min(nan), 1.0)
}
