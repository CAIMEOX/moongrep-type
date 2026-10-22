///|
priv struct Reader {
  bytes : Bytes
  mut offset : Int
  limit : Int
  values : Array[Value]
  objects : Array[Int]
  pending : Array[(Int, Int)]
  mut field_slots : Int
}

///|
fn Reader::take(self : Reader, size : Int) -> Bytes raise DecodeError {
  if size < 0 || size > self.limit - self.offset {
    raise Invalid(offset=self.offset, reason="truncated value")
  }
  let start = self.offset
  self.offset += size
  self.bytes[start:self.offset].to_owned()
}

///|
fn Reader::byte(self : Reader) -> Int raise DecodeError {
  if self.offset >= self.limit {
    raise Invalid(offset=self.offset, reason="truncated value")
  }
  let value = self.bytes[self.offset].to_int()
  self.offset += 1
  value
}

///|
fn Reader::word(
  self : Reader,
  width : Int,
  little~ : Bool = false,
) -> Int64 raise DecodeError {
  let bytes = self.take(width)
  let mut value = 0L
  for i in 0..<width {
    let index = if little { width - i - 1 } else { i }
    value = (value << 8) | bytes[index].to_int64()
  }
  value
}

///|
fn Reader::count(self : Reader, width : Int) -> Int raise DecodeError {
  let value = self.word(width)
  if value < 0L || value > 2147483647L {
    raise Invalid(
      offset=self.offset - width,
      reason="length exceeds supported range",
    )
  }
  value.to_int()
}

///|
fn Reader::add(
  self : Reader,
  value : Value,
  shared~ : Bool,
) -> Int raise DecodeError {
  // Every new value consumes at least one input byte. Bound allocations by the
  // checked payload, not by untrusted counts in the header.
  if self.values.length() >= self.limit {
    raise Invalid(offset=self.offset, reason="value count exceeds input size")
  }
  let id = self.values.length()
  self.values.push(value)
  if shared {
    self.objects.push(id)
  }
  id
}

///|
fn Reader::block(self : Reader, tag : Int, size : Int) -> Int raise DecodeError {
  if size < 0 || size > self.limit - self.offset {
    raise Invalid(
      offset=self.offset,
      reason="block fields exceed remaining input",
    )
  }
  // Every field requires a value opcode somewhere in this payload. Check the
  // cumulative allocation too: nested malicious headers must not allocate a
  // quadratic number of pending slots before reaching their truncated tail.
  if size > self.limit - self.field_slots {
    raise Invalid(
      offset=self.offset,
      reason="block field budget exceeds input size",
    )
  }
  self.field_slots += size
  let fields = Array::make(size, -1)
  let id = self.add(Block(tag~, fields~), shared=size != 0)
  for i = size - 1; i >= 0; i = i - 1 {
    self.pending.push((id, i))
  }
  id
}

///|
fn Reader::string(self : Reader, size : Int) -> Int raise DecodeError {
  self.add(ByteString(self.take(size)), shared=true)
}

///|
fn Reader::shared(self : Reader, width : Int) -> Int raise DecodeError {
  let distance = self.count(width)
  if distance <= 0 || distance > self.objects.length() {
    raise Invalid(
      offset=self.offset - width,
      reason="invalid backward reference",
    )
  }
  self.objects[self.objects.length() - distance]
}

///|
fn Reader::float_array(
  self : Reader,
  width : Int,
  little~ : Bool,
) -> Int raise DecodeError {
  let count = self.count(width)
  if count > (self.limit - self.offset) / 8 {
    raise Invalid(offset=self.offset, reason="truncated float array")
  }
  let values = Array::make(count, 0L)
  for i in 0..<count {
    values[i] = self.word(8, little~)
  }
  self.add(FloatArray(values), shared=true)
}

///|
fn Reader::custom(self : Reader, sized~ : Bool) -> Int raise DecodeError {
  let name = StringBuilder()
  while true {
    let byte = self.byte()
    if byte == 0 {
      break
    }
    if byte > 127 || name.to_string().length() > 128 {
      raise Invalid(offset=self.offset, reason="invalid custom identifier")
    }
    name.write_char(byte.unsafe_to_char())
  }
  let name = name.to_string()
  if sized {
    // These are OCaml heap sizes, not wire payload lengths.
    ignore(self.word(4))
    ignore(self.word(8))
  }
  let value = match name {
    "_i" => {
      let n = self.word(4)
      if (n & 0x80000000L) != 0L {
        n - 0x100000000L
      } else {
        n
      }
    }
    "_j" => self.word(8)
    "_n" =>
      match self.byte() {
        1 => {
          let n = self.word(4)
          if (n & 0x80000000L) != 0L {
            n - 0x100000000L
          } else {
            n
          }
        }
        2 => self.word(8)
        _ =>
          raise Invalid(
            offset=self.offset - 1,
            reason="invalid nativeint width",
          )
      }
    _ =>
      raise Invalid(
        offset=self.offset,
        reason="unsupported custom block: \{name}",
      )
  }
  self.add(Custom(name~, value~), shared=true)
}

///|
fn Reader::value(self : Reader) -> Int raise DecodeError {
  let code = self.byte()
  if code >= 0x80 {
    return self.block(code & 15, (code >> 4) & 7)
  }
  if code >= 0x40 {
    return self.add(Integer((code & 63).to_int64()), shared=false)
  }
  if code >= 0x20 {
    return self.string(code & 31)
  }
  match code {
    0 | 1 | 2 | 3 => {
      let width = 1 << code
      let value = self.word(width)
      let value = if width < 8 && (value & (1L << (width * 8 - 1))) != 0L {
        value - (1L << (width * 8))
      } else {
        value
      }
      self.add(Integer(value), shared=false)
    }
    4 => self.shared(1)
    5 => self.shared(2)
    6 => self.shared(4)
    0x14 => self.shared(8)
    8 | 0x13 => {
      let header = self.word(if code == 8 { 4 } else { 8 })
      let size = header.reinterpret_as_uint64() >> 10
      if size > 2147483647UL {
        raise Invalid(offset=self.offset, reason="oversized block")
      }
      self.block((header & 255L).to_int(), size.to_int())
    }
    9 => self.string(self.count(1))
    10 => self.string(self.count(4))
    0x15 => self.string(self.count(8))
    11 | 12 => self.add(FloatBits(self.word(8, little=code == 12)), shared=true)
    13 | 14 => self.float_array(1, little=code == 14)
    15 | 7 => self.float_array(4, little=code == 7)
    0x16 | 0x17 => self.float_array(8, little=code == 0x17)
    0x18 => self.custom(sized=true)
    0x19 => self.custom(sized=false)
    _ =>
      raise Invalid(
        offset=self.offset - 1,
        reason="unsupported opcode: \{code}",
      )
  }
}

///|
/// Decode one uncompressed OCaml 4.14 Marshal value. Trailing data, unsupported
/// custom codecs and executable values are rejected rather than guessed.
pub fn decode(bytes : Bytes) -> Graph raise DecodeError {
  let header : Reader = {
    bytes,
    offset: 0,
    limit: bytes.length(),
    values: [],
    objects: [],
    pending: [],
    field_slots: 0,
  }
  let magic = header.word(4)
  let (payload_size, object_count) = match magic {
    0x8495A6BEL => {
      let size = header.count(4)
      let objects = header.count(4)
      ignore(header.word(4))
      ignore(header.word(4))
      (size, objects)
    }
    0x8495A6BFL => {
      if header.word(4) != 0L {
        raise Invalid(offset=4, reason="nonzero reserved header")
      }
      let size = header.count(8)
      let objects = header.count(8)
      ignore(header.word(8))
      (size, objects)
    }
    _ => raise Invalid(offset=0, reason="unsupported Marshal header")
  }
  if payload_size != bytes.length() - header.offset ||
    object_count > payload_size {
    raise Invalid(
      offset=header.offset,
      reason="invalid payload length or object count",
    )
  }
  let root_id = header.value()
  while header.pending.pop() is Some((parent, slot)) {
    let value = header.value()
    guard header.values[parent] is Block(fields~, ..) else {
      raise Invalid(offset=header.offset, reason="invalid pending block")
    }
    fields[slot] = value
  }
  if header.offset != bytes.length() || header.objects.length() != object_count {
    raise Invalid(
      offset=header.offset,
      reason="payload or object count mismatch",
    )
  }
  { values: header.values, root_id, shared_count: object_count, }
}
