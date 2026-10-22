///|
pub fn run() -> Int {
  let answer = if false {
    let erased = identity(3.0)
    let _ = erased
    0
  } else {
    42
  }
  answer
}
