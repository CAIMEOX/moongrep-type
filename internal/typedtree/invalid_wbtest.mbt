///|
test "typedtree adapter rejects unknown versions before decoding" {
  try extract("unknown", [], []) catch {
    Invalid(reason) => assert_true(reason.contains("unverified"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("unknown compiler accepted")
  }
}

///|
test "typedtree adapter rejects non-typedtree Marshal values" {
  let scalar : Bytes = b"\x84\x95\xa6\xbe\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40"
  try
    extract("v0.10.14+7080b3792-nightly (2026-10-10)", [], [
      {
        key: "test",
        name: "test",
        source_root: "/tmp",
        artifact: scalar,
        source_aliases: [],
      },
    ])
  catch {
    Invalid(reason) => assert_true(reason.contains("expected block"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("wrong schema accepted")
  }
}
