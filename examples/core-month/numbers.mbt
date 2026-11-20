///|
pub fn nonfinite(x : Double) -> Bool {
  x.is_nan() || x.is_inf()
}

///|
pub fn finite_float(x : @float.Float) -> Bool {
  !x.is_inf() && !x.is_nan()
}

///|
pub fn special(x : Double) -> Bool {
  x.is_inf() || x.is_nan() || x == 0.0
}

///|
pub fn distance_candidates(sub : Int32, del : Int32, ins : Int32) -> Int32 {
  let mut best = sub
  if del < best {
    best = del
  }
  if best > ins {
    best = ins
  }
  best
}

///|
pub fn lower_bound(i : Int32, k : Int32) -> Int32 {
  if i - k > 1 {
    i - k
  } else {
    1
  }
}

///|
pub fn unsigned_larger(a : UInt64, b : UInt64) -> UInt64 {
  if a <= b {
    b
  } else {
    a
  }
}

///|
pub fn raise_floor(initial : Int32, x : Int32) -> Int32 {
  let mut acc = initial
  if x >= acc {
    acc = x
  }
  acc
}
