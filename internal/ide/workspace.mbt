///|
/// Workspace members are a literal string array. Reuse the public language
/// parser for the manifest's assignment syntax, including comments/escapes.
fn workspace_members(text : String, json~ : Bool) -> Array[String] raise {
  if json {
    guard @json.parse(text) is { "members": Array(members), .. } else {
      fail("workspace manifest has no members array")
    }
    return members.map(value => {
      guard value is String(path) else {
        fail("workspace member is not a path")
      }
      path
    })
  }
  let parsed = @untyped_cst.parse_expression("{\n" + text + "\n}")
  let (expr, reports) = parsed.to_expr()
  guard parsed.diagnostics_view().is_empty() &&
    reports.is_empty() &&
    expr is Some(expr) else {
    fail("cannot parse workspace members")
  }
  let pending = [expr]
  let mut members : Array[String]? = None
  while pending.pop() is Some(expr) {
    match expr {
      Sequence(exprs~, last_expr~, ..) => {
        pending.push(last_expr)
        for expr in exprs {
          pending.push(expr)
        }
      }
      Group(expr~, ..) => pending.push(expr)
      Assign(var_={ name: Ident(name="members"), .. }, expr~, ..) => {
        guard members is None && expr is Array(exprs~, is_iter=false, ..) else {
          fail("workspace members must be one literal array")
        }
        members = Some(
          exprs
          .map(expr => {
            guard expr is Constant(c=String(path), ..) else {
              fail("workspace member is not a path")
            }
            path
          })
          .to_array(),
        )
      }
      _ => ()
    }
  }
  members.unwrap_or([])
}

///|
async fn workspace_contains(manifest : String, module_root : String) -> Bool {
  for
    entry in workspace_members(
      @fs.read_file(manifest).text(),
      json=manifest.has_suffix(".json"),
    ) {
    let path = @path.Path(entry)
    let path = if path.is_absolute() {
      path
    } else {
      @path.Path(parent(manifest)).join(path)
    }
    if @fs.exists(path.to_string()) &&
      @fs.realpath(path.to_string()) == module_root {
      return true
    }
  }
  false
}
