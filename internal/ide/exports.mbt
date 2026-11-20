///|
/// Look in the public interface belonging to the resolved definition. The
/// SDK running the IDE may predate the API a lint rule wants to suggest.
pub async fn CheckedFile::exports_method(
  self : CheckedFile,
  witness : @semantic.SymbolInfo,
  package_name : String,
  owner : String,
  name : String,
  arity : Int32,
) -> Bool {
  guard witness.raw is { "definition": { "file": String(file), .. }, .. } else {
    return false
  }
  let catalog = self.project.catalog
  let mut root = ""
  for dir, pkg in catalog.packages {
    if pkg == package_name && inside(dir, file) && dir.length() > root.length() {
      root = dir
    }
  }
  guard !root.is_empty() else { return false }
  let path = root + "/pkg.generated.mbti"
  let methods = if catalog.exports.get(path) is Some(cached) {
    cached
  } else {
    let lookup = @async.Lazy::Lazy(() => {
      guard @fs.exists(path) else {
        self.project.snapshots[path] = None
        return Set([])
      }
      let text = @fs.read_file(path).text()
      if catalog.documents.get(path) is Some(before) && before != text {
        fail("public interface changed during semantic verification: \{path}")
      }
      catalog.documents[path] = text
      exported_methods(text, path, package_name)
    })
    catalog.exports[path] = lookup
    lookup
  }
  methods.wait().contains((owner, name, arity))
}

///|
fn exported_methods(
  text : String,
  path : String,
  package_name : String,
) -> Set[(String, String, Int32)] {
  let result : Set[(String, String, Int32)] = Set([])
  let (api, errors) = @mbti_parser.parse_string(text, name=path)
  guard errors.is_empty() && api.package_name == package_name else {
    return result
  }
  for (sig_, _) in api.sigs {
    if sig_ is Func(f) &&
      f.type_name is Some({ name: Ident(name=ty), is_object: false, .. }) &&
      f.is_async is None &&
      f.return_.1 is (NoErrorType | Noraise(..)) &&
      !f.attrs.iter().any(a => a.name() == Some("cfg")) &&
      f.params.iter().all(p => p is (Positional(..) | DiscardPositional(..))) {
      result.add((ty, f.name.name, f.params.length()))
    }
  }
  result
}
