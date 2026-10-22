///|
fn packet(payload : Array[Int], objects : Int) -> Bytes {
  let out : Array[Byte] = [0x84, 0x95, 0xa6, 0xbe]
  for n in [payload.length(), objects, 0, 0] {
    for shift in [24, 16, 8, 0] {
      out.push(((n >> shift) & 255).to_byte())
    }
  }
  for byte in payload {
    out.push(byte.to_byte())
  }
  Bytes::from_array(out)
}

///|
test "Marshal shared references and cycles retain identity" {
  // Block(tag=0,size=2) with itself and a zero-sized constructor.
  let graph = decode(packet([0xa0, 0x04, 1, 0x82], 1))
  guard graph.get(graph.root()) is Block(tag=0, fields~) else { fail("block") }
  inspect(fields[0] == graph.root(), content="true")
  debug_inspect(graph.get(fields[1]), content="Block(tag=2, fields=[])")
  let shared = decode(packet([0xa0, 0x23, 97, 98, 99, 0x04, 1], 2))
  guard shared.get(shared.root()) is Block(fields~, ..) else { fail("block") }
  inspect(fields[0] == fields[1], content="true")
  inspect(shared.text(fields[0]), content="abc")
}

///|
test "Marshal signed integers custom integers and float bits" {
  debug_inspect(decode(packet([0, 255], 0)).get(0), content="Integer(-1)")
  debug_inspect(
    decode(packet([0x19, 95, 105, 0, 255, 255, 255, 254], 1)).get(0),
    content="Custom(name=\"_i\", value=-2)",
  )
  debug_inspect(
    decode(packet([12, 0, 0, 0, 0, 0, 0, 240, 63], 1)).get(0),
    content="FloatBits(4607182418800017408)",
  )
}

///|
test "Marshal malformed objects fail without partial graphs" {
  for
    bytes in [
      packet([4, 1], 0),
      packet([0xa0, 0x40], 1),
      packet([0x20], 0),
      packet([0x40, 0x40], 0),
      packet([0x10], 0),
    ] {
    try decode(bytes) catch {
      _ => ()
    } noraise {
      _ => fail("invalid data accepted")
    }
  }
}

///|
test "Marshal large headers and explicit block and string encodings" {
  let payload = [
    8, 0, 0, 12, 0, 9, 1, 97, 10, 0, 0, 0, 1, 98, 0x15, 0, 0, 0, 0, 0, 0, 0, 1, 99,
  ]
  let small = packet(payload, 4)
  let bytes : Array[Byte] = [0x84, 0x95, 0xa6, 0xbf, 0, 0, 0, 0]
  for n in [payload.length(), 4, 0] {
    bytes.append([0, 0, 0, 0])
    for shift in [24, 16, 8, 0] {
      bytes.push(((n >> shift) & 255).to_byte())
    }
  }
  for n in payload {
    bytes.push(n.to_byte())
  }
  for graph in [decode(small), decode(Bytes::from_array(bytes))] {
    guard graph.get(0) is Block(tag=0, fields~) else { fail("block") }
    debug_inspect(
      fields.map(id => graph.text(id)),
      content="[\"a\", \"b\", \"c\"]",
    )
  }
}

///|
test "Marshal all shared reference widths and float arrays" {
  for (code, width) in [(4, 1), (5, 2), (6, 4), (0x14, 8)] {
    let payload = [0xa0, 0x21, 120, code]
    for _ in 0..<(width - 1) {
      payload.push(0)
    }
    payload.push(1)
    let graph = decode(packet(payload, 2))
    guard graph.get(0) is Block(fields~, ..) else { fail("block") }
    assert_eq(fields[0], fields[1])
  }
  for
    (code, width, little) in [
      (13, 1, false),
      (14, 1, true),
      (15, 4, false),
      (7, 4, true),
      (0x16, 8, false),
      (0x17, 8, true),
    ] {
    let payload = [code]
    for _ in 0..<(width - 1) {
      payload.push(0)
    }
    payload.push(1)
    payload.append(
      if little {
        [0, 0, 0, 0, 0, 0, 240, 63]
      } else {
        [63, 240, 0, 0, 0, 0, 0, 0]
      },
    )
    guard decode(packet(payload, 1)).get(0) is FloatArray(values) else {
      fail("float array")
    }
    assert_eq(values[0], 4607182418800017408L)
  }
}

///|
test "Marshal binary strings, custom lengths, and native integers" {
  let graph = decode(packet([0x22, 255, 0], 1))
  guard graph.get(0) is ByteString(value) else { fail("bytes") }
  assert_eq(value, b"\xff\x00")
  try graph.text(0) catch {
    _ => ()
  } noraise {
    _ => fail("invalid UTF-8 accepted")
  }
  debug_inspect(
    decode(
      packet(
        [0x18, 95, 105, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 42],
        1,
      ),
    ).get(0),
    content="Custom(name=\"_i\", value=42)",
  )
  debug_inspect(
    decode(packet([0x19, 95, 110, 0, 1, 0, 0, 0, 42], 1)).get(0),
    content="Custom(name=\"_n\", value=42)",
  )
  debug_inspect(
    decode(
      packet([0x19, 95, 106, 0, 255, 255, 255, 255, 255, 255, 255, 255], 1),
    ).get(0),
    content="Custom(name=\"_j\", value=-1)",
  )
}

///|
test "Marshal decoding is iterative and rejects every truncated prefix" {
  let payload = Array::make(20000, 0x90)
  payload.push(0x6a)
  let graph = decode(packet(payload, 20000))
  inspect(graph.length(), content="20001")
  debug_inspect(graph.get(20000), content="Integer(42)")
  let valid = packet([0xa0, 0x23, 97, 98, 99, 0x04, 1], 2)
  for i in 0..<valid.length() {
    try decode(valid[:i].to_owned()) catch {
      _ => ()
    } noraise {
      _ => fail("truncation accepted")
    }
  }
}

///|
test "Marshal nested oversized field claims have a linear allocation budget" {
  let payload : Array[Int] = []
  for _ in 0..<3 {
    payload.append([8, 0, 1, 144, 0])
  }
  for _ in 0..<100 {
    payload.push(0x40)
  }
  try decode(packet(payload, 3)) catch {
    Invalid(offset~, reason~) => {
      assert_true(offset < 40)
      inspect(reason, content="block field budget exceeds input size")
    }
  } noraise {
    _ => fail("invalid nested size claims accepted")
  }
}
