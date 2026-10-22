///|
pub fn imported_field(value : @dep.External) -> Int {
  value.value
}

///|
pub using @dep {make_external as forwarded}

///|
pub fn alias_call() -> Int { forwarded(3).value }

///|
pub extenum @dep.Open += {
  Extra(Int)
}

///|
pub fn extension() -> @dep.Open { Extra(3) }
