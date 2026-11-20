///|
priv struct Footnote {
  id : Int32
  mut count : Int32
}

///|
test "destructure the loop element and preserve later reads of mutable fields" {
  let flags = Map([("first", (1, true)), ("second", (2, false))])
  let original = []
  for name, pair in flags {
    let (number, enabled) = pair
    if enabled {
      original.push((name, number))
    }
  }
  let rewritten = []
  for name, (number, enabled) in flags {
    if enabled {
      rewritten.push((name, number))
    }
  }
  assert_eq(rewritten, original)
  let notes : Array[Footnote] = [{ id: 7, count: 0, }]
  fn render(note : Footnote) -> Unit {
    note.count += 1
  }
  let seen = []
  for note in notes {
    let { id, .. } = note
    render(note)
    let { count, .. } = note
    seen.push((id, count))
  }
  assert_eq(seen, [(7, 1)])
  // Reading count in the header would see zero on this fresh note.
  let notes : Array[Footnote] = [{ id: 7, count: 0, }]
  let early = []
  for { id, count, } as note in notes {
    render(note)
    early.push((id, count))
  }
  assert_eq(early, [(7, 0)])
}

///|
fn attribute_by_character(name : String) -> Bool {
  guard !name.is_empty() else { return false }
  for i, ch in name {
    if ch is ('A'..<='Z' | 'a'..<='z' | '_' | ':') {
      continue
    }
    if i > 0 && ch is ('0'..<='9' | '.' | '-') {
      continue
    }
    return false
  }
  true
}

///|
fn attribute_by_grammar(name : String) -> Bool {
  lexmatch name {
    re"^[A-Za-z_:]([A-Za-z0-9_:.]|-)*$" => true
    _ => false
  }
}

///|
test "the complete attribute grammar agrees on 16105 short strings" {
  let alphabet = ["a", "Z", "0", ":", "_", ".", "-", " ", "\n", "é", "😀"]
  let mut tested = 0
  fn visit(prefix : String, remaining : Int32) -> Unit raise {
    assert_eq(
      attribute_by_grammar(prefix),
      attribute_by_character(prefix),
      msg=prefix,
    )
    tested += 1
    if remaining > 0 {
      for suffix in alphabet {
        visit(prefix + suffix, remaining - 1)
      }
    }
  }
  visit("", 4)
  assert_eq(tested, 16105)
}

///|
priv enum CommandFlag {
  Set(Ref[Bool])
  Clear(Ref[Bool])
  Ignore
}

///|
test "with in disjoint alternatives preserves the flag, target and action order" {
  let a = Ref(false)
  let b = Ref(true)
  let commands : Array[(CommandFlag, Int32)] = [
    (Set(a), 1),
    (Clear(b), 2),
    (Ignore, 3),
    (Clear(a), 4),
  ]
  let trace = []
  for command in commands {
    match command {
      ((Set(cell), step) with value = true)
      | ((Clear(cell), step) with value = false) => {
        cell.val = value
        trace.push((step, cell.val))
      }
      _ => ()
    }
  }
  assert_eq(trace, [(1, true), (2, false), (4, false)])
  assert_eq((a.val, b.val), (false, false))
}

///|
#derive(Eq, Debug)
priv enum FloatField {
  Short
  WrongTag
  Bits(UInt64)
}

///|
fn read_float_field(bytes : Bytes) -> FloatField {
  guard bytes.length() >= 9 else { return Short }
  match bytes {
    [b'\xfb', u64be(bits), ..] => Bits(bits)
    _ => WrongTag
  }
}

///|
test "a CBOR float pattern retains byte order, trailing bytes and error priority" {
  assert_eq(read_float_field(b""), Short)
  assert_eq(read_float_field(b"\xf0\x01"), Short)
  assert_eq(read_float_field(b"123456789"), WrongTag)
  assert_eq(
    read_float_field(b"\xfb\x80\x00\x00\x00\x00\x00\x00\x00x"),
    Bits(0x8000000000000000UL),
  )
  assert_eq(
    read_float_field(b"\xfb\x7f\xf8\x12\x34\x56\x78\x9a\xbc"),
    Bits(0x7ff8123456789abcUL),
  )
}

///|
priv enum SyntaxTree {
  Leaf(String)
  Branch
}

///|
test "a nested prefix pattern checks the constructor and the first character" {
  for token in ["", ";", ";🚀", "🚀;", "；", "x"] {
    let tree = SyntaxTree::Leaf(token)
    assert_eq(tree is Leaf([';', ..]), token.length() > 0 && token[0] == ';')
  }
  let branch : SyntaxTree = Branch
  assert_false(branch is Leaf([';', ..]))
}
