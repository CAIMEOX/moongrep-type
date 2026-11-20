///|
pub fn visit_paths(
  directory : () -> String?,
  home : String,
  visit : (String) -> Unit,
) -> Unit {
  let paths : Array[String] = []
  if directory() is Some(dir) {
    paths.push(dir + "/git/config")
  }
  paths.push(home + "/.gitconfig")
  for path in paths {
    visit(path)
  }
}

///|
pub fn sum_items(include_first : Bool, first : Int32, last : Int32) -> Int32 {
  let mut total = 0
  let items = []
  if include_first {
    items.push(first)
  }
  items.push(last)
  for item in items {
    total += item
  }
  total
}
