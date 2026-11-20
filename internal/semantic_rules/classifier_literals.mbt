///|
priv struct LiteralAlternatives {
  numbers : Array[(BigInt, BigInt)]
  strings : Set[String]
}

///|
/// CST character and byte payloads retain the spelling of escapes. Only use
/// spellings whose value we can compare, including escaped range endpoints.
fn literal_code_point(raw : String) -> Int32? {
  let hex = match raw[:] {
    [c] => return Some(c.to_int())
    ['\\', 'x', .. digits] if digits.length() == 2 => digits
    ['\\', 'u', '{', .. digits, '}'] => digits
    ['\\', 'u', .. digits] if digits.length() == 4 => digits
    _ =>
      return match raw {
        "\\n" => Some(10)
        "\\r" => Some(13)
        "\\t" => Some(9)
        "\\b" => Some(8)
        "\\\\" => Some(92)
        "\\'" => Some(39)
        "\\\"" => Some(34)
        _ => None
      }
  }
  Some(@string.parse_int(hex, radix=16)) catch {
    _ => None
  }
}

///|
fn classifier_number(constant : @untyped_cst.CstNode) -> BigInt? {
  guard @cst.string_payload(constant) is Some(raw) else { return None }
  match constant.kind {
    Constant_Char | Constant_Byte =>
      literal_code_point(raw).map(BigInt::from_int)
    Constant_Int | Constant_UInt | Constant_Int64 | Constant_UInt64 => {
      // The CST has already removed the integer suffix. Parsing the magnitude
      // also covers the minimum signed integer and the maximum UInt64.
      let (negative, magnitude) = match raw[:] {
        ['-', .. magnitude] => (true, magnitude)
        magnitude => (false, magnitude)
      }
      let value = @string.parse_uint64(magnitude, radix=0) catch {
        _ => return None
      }
      Some(
        if negative {
          -BigInt::from_uint64(value)
        } else {
          BigInt::from_uint64(value)
        },
      )
    }
    _ => None
  }
}

///|
fn LiteralAlternatives::add_interval(
  self : LiteralAlternatives,
  lo : BigInt,
  hi : BigInt,
) -> Bool {
  guard lo <= hi && !self.numbers.any(other => lo <= other.1 && other.0 <= hi) else {
    return false
  }
  self.numbers.push((lo, hi))
  true
}

///|
fn LiteralAlternatives::add(
  self : LiteralAlternatives,
  pattern : @untyped_cst.CstNode,
) -> Bool {
  match pattern.kind {
    Expr_Constant | Pattern_Constant => {
      guard @cst.constant(pattern) is Some(c) &&
        !(@cst.raw_child(pattern, "operator")
        is Some({ kind: Operator_UnaryPlus, .. })) else {
        return false
      }
      if c.kind is Constant_String {
        guard @cst.string_payload(c) is Some(s) &&
          !s.contains("\\") &&
          !self.strings.contains(s) else {
          return false
        }
        self.strings.add(s)
        true
      } else {
        classifier_number(c) is Some(n) && self.add_interval(n, n)
      }
    }
    Pattern_Or =>
      @cst.child(pattern, "lhs") is Some(left) &&
      @cst.child(pattern, "rhs") is Some(right) &&
      self.add(left) &&
      self.add(right)
    Pattern_Range => {
      guard @cst.child(pattern, "lhs")
        .bind(@cst.constant)
        .bind(classifier_number)
        is Some(lo) &&
        @cst.child(pattern, "rhs").bind(@cst.constant).bind(classifier_number)
        is Some(hi) &&
        @cst.raw_child(pattern, "range_kind") is Some(range_kind) else {
        return false
      }
      match range_kind.kind {
        RangeKind_Inclusive => self.add_interval(lo, hi)
        RangeKind_Exclusive => self.add_interval(lo, hi - 1N)
        _ => false
      }
    }
    _ => false
  }
}

///|
fn LiteralAlternatives::fits(self : LiteralAlternatives, shape : Json) -> Bool {
  guard shape is { "kind": "builtin", "name": String(name), .. } else {
    return false
  }
  if name == "String" {
    return self.numbers.is_empty() && self.strings.length() >= 2
  }
  guard self.strings.is_empty() else { return false }
  let (lo, hi) = match name {
    "Byte" => (0N, 255N)
    "Char" => (0N, 0x10FFFFN)
    "Int16" => (-32768N, 32767N)
    "UInt16" => (0N, 65535N)
    "Int" => (-2147483648N, 2147483647N)
    "UInt" => (0N, 4294967295N)
    "Int64" => (-9223372036854775808N, 9223372036854775807N)
    "UInt64" => (0N, 18446744073709551615N)
    _ => return false
  }
  self.numbers.all(range => lo <= range.0 && range.1 <= hi)
}
