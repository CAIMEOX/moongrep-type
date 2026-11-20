///|
/// Feed just the lookups a rule asks for. The rule code is shared with the real IDE.
fn fixture_context(
  file : String,
  text : String,
  types : Array[Json],
  symbols : Array[Json],
  facts : Array[Json],
) -> (CheckContext, @untyped_cst.CstNode) raise {
  let tree = @untyped_cst.parse_structure(text, name=file).root()
  let positions : Map[@semantic.Range, Array[Json]] = Map([])
  let bindings : Map[String, @semantic.Range] = Map([])
  let uses : Map[String, Array[@semantic.Range]] = Map([])
  for fact in facts {
    guard fact is { "location": loc, .. } else { fail("fixture location") }
    let loc : @semantic.Range = @json.from_json(loc)
    if positions.get(loc) is Some(entries) {
      entries.push(fact)
    } else {
      positions[loc] = [fact]
    }
    if fact is { "symbol_id": String(id), .. } {
      if fact is { "kind": "binding", .. } {
        bindings[id] = loc
      }
      if uses.get(id) is Some(entries) {
        entries.push(loc)
      } else {
        uses[id] = [loc]
      }
    }
  }
  let context : CheckContext = {
    file,
    text,
    package_name: () => "fixture",
    shape_at: n => {
      guard positions.get(node_range(file, n)) is Some(facts) else {
        raise Skip("missing_exact_semantics")
      }
      guard facts.filter(f => f is { "kind": "expression", .. })
        is [{ "type_id": Number(id, ..), .. }] else {
        raise Skip("non_unique_expression_type")
      }
      type_shape(i => types.get(i), id.to_int())
    },
    call_header_at: node => {
      guard positions.get(node_range(file, node)) is Some(entries) &&
        entries.filter(entry => entry is { "kind": "expression", .. })
        is [{ "type_id": Number(id, ..), .. }] else {
        return None
      }
      types.get(id.to_int()).bind(function_header)
    },
    symbol_at: n => {
      guard positions.get(node_range(file, n)) is Some(entries) else {
        return None
      }
      if n.kind is Pattern_Constr && entries.length() != 1 {
        raise Unavailable("No unique constructor")
      }
      for entry in entries {
        if entry is { "symbol_id": String(id), .. } {
          for raw in symbols {
            if raw
              is {
                "id": String(key),
                "kind": String(kind),
                "name": String(name),
                "identity": identity,
                ..
              } &&
              key == id {
              let kind = if entry
                is { "details": { "dispatch": String(dispatch), .. }, .. } &&
                dispatch != "resolved_symbol" {
                "local"
              } else {
                kind
              }
              return Some({ id, kind, name, identity, raw, })
            }
          }
        }
      }
      None
    },
    binding: id => bindings.get(id),
    references: n => {
      for id, loc in bindings {
        if loc == node_range(file, n) {
          return uses.get(id).unwrap_or([])
        }
      }
      []
    },
    binders: Map([]),
    previous: Map([]),
  }
  context.inspect_syntax(tree)
  (context, tree)
}
