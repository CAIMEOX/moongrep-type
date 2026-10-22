///|
pub(all) struct External {
  value : Int
}

///|
pub fn make_external(value : Int) -> External { { value } }

///|
pub extenum Open {
  Original(Int)
}
