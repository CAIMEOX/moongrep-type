///|
fn required(
  value : Json,
  key : String,
  context : String,
) -> Json raise SemanticError {
  guard value is Object(object) else {
    raise Invalid("\{context} must be an object")
  }
  guard object.get(key) is Some(found) else {
    raise Invalid("\{context}.\{key} is required")
  }
  found
}

///|
fn string_value(value : Json, context : String) -> String raise SemanticError {
  guard value is String(found) else {
    raise Invalid("\{context} must be a string")
  }
  found
}

///|
fn integer_value(value : Json, context : String) -> Int raise SemanticError {
  guard value is Number(number, ..) else {
    raise Invalid("\{context} must be an integer")
  }
  if number < -2147483648.0 || number > 2147483647.0 {
    raise Invalid("\{context} must be an integer")
  }
  let integer = number.to_int()
  if integer.to_double() != number {
    raise Invalid("\{context} must be an integer")
  }
  integer
}

///|
fn array_value(
  value : Json,
  context : String,
) -> Array[Json] raise SemanticError {
  guard value is Array(found) else {
    raise Invalid("\{context} must be an array")
  }
  found
}

///|
fn string_field(
  value : Json,
  key : String,
  context : String,
) -> String raise SemanticError {
  string_value(required(value, key, context), "\{context}.\{key}")
}

///|
fn id_field(value : Json, context : String) -> Int raise SemanticError {
  let id = integer_value(required(value, "id", context), "\{context}.id")
  if id < 0 {
    raise Invalid("\{context}.id must be nonnegative")
  }
  id
}

///|
fn position_value(
  value : Json,
  context : String,
) -> Position raise SemanticError {
  {
    line: integer_value(required(value, "line", context), "\{context}.line"),
    column: integer_value(
      required(value, "column", context),
      "\{context}.column",
    ),
  }
}

///|
fn range_value(value : Json, context : String) -> Range raise SemanticError {
  {
    file: string_field(value, "file", context),
    start: position_value(required(value, "start", context), "\{context}.start"),
    end: position_value(required(value, "end", context), "\{context}.end"),
  }
}

///|
fn absolute_path(path : String) -> Bool {
  path.has_prefix("/") ||
  path.has_prefix("\\\\") ||
  (path.length() >= 3 && path[1] == ':' && (path[2] == '/' || path[2] == '\\'))
}

///|
fn source_line_lengths(text : String) -> Array[Int] {
  let lengths : Array[Int] = []
  let mut length = 0
  let mut after_cr = false
  for char in text {
    if char == '\n' && after_cr {
      after_cr = false
      continue
    }
    if char == '\r' ||
      char == '\n' ||
      char.to_int() == 0x2028 ||
      char.to_int() == 0x2029 {
      lengths.push(length)
      length = 0
    } else {
      length += 1
    }
    after_cr = char == '\r'
  }
  lengths.push(length)
  lengths
}

///|
fn valid_position(position : Position, lengths : Array[Int]) -> Bool {
  position.line >= 1 &&
  position.line <= lengths.length() &&
  position.column >= 1 &&
  position.column <= lengths[position.line - 1] + 1
}

///|
fn optional_field(value : Json, key : String) -> Json? {
  if value is Object(fields) {
    fields.get(key)
  } else {
    None
  }
}

///|
fn validate_type_reference(
  value : Json,
  context : String,
  type_ids : Map[Int, Int],
) -> Unit raise SemanticError {
  let id = integer_value(value, context)
  if !type_ids.contains(id) {
    raise Invalid("\{context} references missing type: \{id}")
  }
}

///|
fn validate_symbol_reference(
  value : Json,
  context : String,
  symbol_ids : Map[String, Int],
) -> Unit raise SemanticError {
  let id = string_value(value, context)
  if !symbol_ids.contains(id) {
    raise Invalid("\{context} references missing symbol: \{id}")
  }
}

///|
fn validate_error_reference(
  value : Json,
  context : String,
  type_ids : Map[Int, Int],
) -> Unit raise SemanticError {
  if value is Null {
    return
  }
  if string_field(value, "kind", context) == "typed" {
    validate_type_reference(
      required(value, "type_id", context),
      "\{context}.type_id",
      type_ids,
    )
  }
}

///|
fn validate_type_references(
  info : TypeInfo,
  type_ids : Map[Int, Int],
) -> Unit raise SemanticError {
  let context = "type \{info.id}"
  match info.kind {
    "named" => {
      let arguments = array_value(
        required(info.raw, "arguments", context),
        "\{context}.arguments",
      )
      for argument in arguments {
        validate_type_reference(argument, "\{context}.arguments", type_ids)
      }
    }
    "function" => {
      let parameters = array_value(
        required(info.raw, "parameters", context),
        "\{context}.parameters",
      )
      for parameter in parameters {
        validate_type_reference(parameter, "\{context}.parameters", type_ids)
      }
      validate_type_reference(
        required(info.raw, "return_type", context),
        "\{context}.return_type",
        type_ids,
      )
      let error = required(info.raw, "error", context)
      validate_error_reference(error, "\{context}.error", type_ids)
    }
    "resolved_variable" =>
      validate_type_reference(
        required(info.raw, "target_type", context),
        "\{context}.target_type",
        type_ids,
      )
    _ => ()
  }
}

///|
fn validate_detail_references(
  details : Json,
  id : Int,
  type_ids : Map[Int, Int],
  symbol_ids : Map[String, Int],
) -> Unit raise SemanticError {
  let context = "fact \{id}.details"
  for
    key in [
      "self_type", "receiver_type", "deferred_function_type", "caught_error_type",
      "pattern_type", "record_type", "field_type",
    ] {
    if optional_field(details, key) is Some(value) && !(value is Null) {
      validate_type_reference(value, "\{context}.\{key}", type_ids)
    }
  }
  for
    key in [
      "alias_symbol_id", "target_symbol_id", "constructor_symbol_id", "method_symbol_id",
      "trait_symbol_id", "callee_symbol_id",
    ] {
    if optional_field(details, key) is Some(value) && !(value is Null) {
      validate_symbol_reference(value, "\{context}.\{key}", symbol_ids)
    }
  }
  if optional_field(details, "parameter_types") is Some(parameters) {
    for parameter in array_value(parameters, "\{context}.parameter_types") {
      validate_type_reference(parameter, "\{context}.parameter_types", type_ids)
    }
  }
  if optional_field(details, "error") is Some(error) {
    validate_error_reference(error, "\{context}.error", type_ids)
  }
  if optional_field(details, "type_arguments") is Some(arguments) &&
    !(arguments is Null) {
    let types = array_value(
      required(arguments, "types", "\{context}.type_arguments"),
      "\{context}.type_arguments.types",
    )
    for entry in types {
      validate_type_reference(
        required(entry, "type_id", "\{context}.type_arguments.types"),
        "\{context}.type_arguments.types.type_id",
        type_ids,
      )
    }
    if optional_field(arguments, "error") is Some(error) {
      validate_error_reference(
        error,
        "\{context}.type_arguments.error",
        type_ids,
      )
    }
  }
}

///|
/// Decode with an independently obtained compiler version, not the payload's own value.
pub fn Index::parse(
  text : String,
  compiler_version~ : String,
) -> Index raise SemanticError {
  let value = @json.parse(text) catch { _ => raise Invalid("invalid JSON") }
  Index::from_json(value, compiler_version~)
}

///|
pub fn Index::from_json(
  value : Json,
  compiler_version~ : String,
) -> Index raise SemanticError {
  let schema = integer_value(
    required(value, "schema_version", "index"),
    "schema_version",
  )
  if schema != 1 {
    raise Invalid("unsupported schema version: \{schema}")
  }
  let version = string_field(value, "compiler_version", "index")
  if version != compiler_version {
    raise CompilerMismatch(expected=compiler_version, found=version)
  }
  if version.is_empty() {
    raise Invalid("compiler version must not be empty")
  }
  let encoding = string_field(value, "position_encoding", "index")
  if encoding != "unicode-scalar" {
    raise Invalid("unsupported position encoding: \{encoding}")
  }
  let source_entries : Array[SourceFile] = []
  let source_ids : Map[String, Int] = Map([])
  let line_lengths : Array[Array[Int]] = []
  for item in array_value(required(value, "sources", "index"), "sources") {
    let path = string_field(item, "path", "source")
    let text = string_field(item, "text", "source")
    if !absolute_path(path) {
      raise Invalid("source path must be absolute: \{path}")
    }
    if source_ids.contains(path) {
      raise Invalid("duplicate source: \{path}")
    }
    source_ids[path] = source_entries.length()
    source_entries.push({ path, text, })
    line_lengths.push(source_line_lengths(text))
  }
  let type_entries : Array[TypeInfo] = []
  let type_ids : Map[Int, Int] = Map([])
  for item in array_value(required(value, "types", "index"), "types") {
    let id = id_field(item, "type")
    let kind = string_field(item, "kind", "type")
    if type_ids.contains(id) {
      raise Invalid("duplicate type id: \{id}")
    }
    type_ids[id] = type_entries.length()
    type_entries.push({ id, kind, raw: item, })
  }
  for info in type_entries {
    validate_type_references(info, type_ids)
  }
  let symbol_entries : Array[SymbolInfo] = []
  let symbol_ids : Map[String, Int] = Map([])
  for item in array_value(required(value, "symbols", "index"), "symbols") {
    let id = string_field(item, "id", "symbol")
    let kind = string_field(item, "kind", "symbol")
    let name = string_field(item, "name", "symbol")
    let identity = required(item, "identity", "symbol")
    if id.is_empty() {
      raise Invalid("symbol id must not be empty")
    }
    if symbol_ids.contains(id) {
      raise Invalid("duplicate symbol id: \{id}")
    }
    symbol_ids[id] = symbol_entries.length()
    symbol_entries.push({ id, kind, name, identity, raw: item, })
  }
  let fact_entries : Array[Fact] = []
  let fact_ids : Map[Int, Bool] = Map([])
  let ranges : Map[Range, Array[Int]] = Map([])
  let file_facts : Map[String, Array[Int]] = Map([])
  for item in array_value(required(value, "facts", "index"), "facts") {
    let id = id_field(item, "fact")
    if fact_ids.contains(id) {
      raise Invalid("duplicate fact id: \{id}")
    }
    fact_ids[id] = true
    let package_name = string_field(item, "package", "fact")
    let kind = string_field(item, "kind", "fact")
    let node_kind = string_field(item, "node_kind", "fact")
    let details = required(item, "details", "fact")
    validate_detail_references(details, id, type_ids, symbol_ids)
    let location_json = required(item, "location", "fact")
    let location = if location_json is Null {
      None
    } else {
      let range = range_value(location_json, "fact.location")
      guard source_ids.get(range.file) is Some(source_id) else {
        raise Invalid("fact \{id} references missing source: \{range.file}")
      }
      let lengths = line_lengths[source_id]
      if !valid_position(range.start, lengths) ||
        !valid_position(range.end, lengths) ||
        !position_le(range.start, range.end) {
        raise Invalid("fact \{id} has an invalid source range")
      }
      Some(range)
    }
    let type_json = required(item, "type_id", "fact")
    let type_id = if type_json is Null {
      None
    } else {
      let type_id = integer_value(type_json, "fact.type_id")
      if !type_ids.contains(type_id) {
        raise Invalid("fact \{id} references missing type: \{type_id}")
      }
      Some(type_id)
    }
    let symbol_json = required(item, "symbol_id", "fact")
    let symbol_id = if symbol_json is Null {
      None
    } else {
      let symbol_id = string_value(symbol_json, "fact.symbol_id")
      if !symbol_ids.contains(symbol_id) {
        raise Invalid("fact \{id} references missing symbol: \{symbol_id}")
      }
      Some(symbol_id)
    }
    let index = fact_entries.length()
    fact_entries.push({
      id,
      package_name,
      kind,
      node_kind,
      location,
      type_id,
      symbol_id,
      details,
      raw: item,
    })
    if location is Some(range) {
      if ranges.get(range) is Some(indices) {
        indices.push(index)
      } else {
        ranges[range] = [index]
      }
      if file_facts.get(range.file) is Some(indices) {
        indices.push(index)
      } else {
        file_facts[range.file] = [index]
      }
    }
  }
  {
    version,
    original: value,
    source_entries,
    type_entries,
    symbol_entries,
    fact_entries,
    source_ids,
    type_ids,
    symbol_ids,
    ranges,
    file_facts,
  }
}
