///|
fn match_early_exit(value : Int?) -> Int {
  let inner = match value {
    Some(inner) => inner
    _ => return 0
  }
  inner
}
