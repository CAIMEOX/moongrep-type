///|
test "a concrete method promotion only agrees with its own implementation" {
  let base : Json = { "kind": "named", "package": "test/one", "name": "Buffer" }
  let tr : Json = { "kind": "named", "package": "test/one", "name": "Write" }
  let promotion : Json = {
    "kind": "promotion",
    "package": "test/one",
    "trait": tr,
    "self_type": base,
    "name": "put",
  }
  fn impl_id(owner : Json, pkg : String, method_name : String) -> Json {
    {
      "kind": "trait_impl",
      "package": pkg,
      "trait": tr,
      "self_type": owner,
      "name": method_name,
    }
  }
  assert_true(promotes_impl(promotion, impl_id(base, "test/one", "put")))
  assert_false(promotes_impl(promotion, impl_id(base, "other/module", "put")))
  assert_false(promotes_impl(promotion, impl_id(base, "test/one", "get")))
  assert_false(
    promotes_impl(promotion, impl_id(Json::null(), "test/one", "put")),
  )
}

///|
test "replacement methods must be exported by the requested package with the right shape" {
  let source =
    #|package "example/core"
    #|pub fn Value::available(Value, Value) -> Value
    #|pub fn Value::effect(Value) -> Bool raise
    #|pub fn Value::labelled(Value, label~ : Int) -> Value
  let methods = exported_methods(source, "pkg.generated.mbti", "example/core")
  assert_true(methods.contains(("Value", "available", 2)))
  assert_eq(methods.length(), 1)
  assert_true(
    exported_methods(source, "pkg.generated.mbti", "other/core").is_empty(),
  )
}
