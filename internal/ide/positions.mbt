///|
fn source_lines(text : String) -> Array[Array[Char]] {
  text
  .replace_all(old="\r\n", new="\n")
  .replace_all(old="\r", new="\n")
  .replace_all(old="\u{2028}", new="\n")
  .replace_all(old="\u{2029}", new="\n")
  .split("\n")
  .map(line => line.to_owned().iter().to_array())
  .to_array()
}

///|
/// Official IDE CLI ranges use one-based source positions, unlike LSP wire
/// offsets. Preserve the scalar columns and require exact authored CST ranges.
fn cli_span(text : String) -> Span raise {
  let ends = text.split("-").to_array()
  guard ends is [start, end] else { fail("invalid IDE range: \{text}") }
  fn point(text : StringView) -> Point raise {
    let parts = text.split(":").to_array()
    guard parts is [line, column] else { fail("invalid IDE position: \{text}") }
    let line = @string.parse_int(line)
    let column = @string.parse_int(column)
    guard line >= 1 && column >= 1 else { fail("nonpositive IDE position") }
    { line, column, }
  }
  let start = point(start)
  let end = point(end)
  guard start.line < end.line ||
    (start.line == end.line && start.column <= end.column) else {
    fail("reversed IDE range")
  }
  { start, end, }
}

///|
fn require_source_span(range : Span, text : String) -> Unit raise {
  let lines = source_lines(text)
  for point in [range.start, range.end] {
    guard point.line <= lines.length() &&
      point.column <= lines[point.line - 1].length() + 1 else {
      fail("IDE definition range lies outside its source")
    }
  }
}
