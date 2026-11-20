///|
#cfg(not(any(target="js", target="wasm")))
pub fn native_extremum(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}
