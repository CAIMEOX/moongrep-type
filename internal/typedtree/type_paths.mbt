///|
/// Read a type's nominal head without registering its declaration's generic
/// parameters in the calling function's scope.
fn Exporter::wire_path(
  self : Exporter,
  id : Int,
  result~ : Bool = false,
  seen~ : Array[Int] = [],
) -> Json? raise {
  if seen.contains(id) {
    return None
  }
  let w = self.wire
  match w.value(id) {
    Block(tag=0, ..) if result =>
      self.wire_path(w.fields(id, 0, 4)[1], result~, seen=[..seen, id])
    Block(tag=1, ..) => Some(self.path(w.fields(id, 1, 3)[0]))
    Block(tag=2, ..) => {
      let link = w.record(w.fields(id, 2, 1)[0], 1)[0]
      if w.tag(link) == 1 {
        self.wire_path(w.fields(link, 1, 1)[0], result~, seen=[..seen, id])
      } else {
        None
      }
    }
    Block(tag=4, ..) => Some(self.path(w.fields(id, 4, 1)[0]))
    Block(tag=5, ..) =>
      Some(
        obj([
          ("kind", str("builtin")),
          (
            "name",
            str(
              select_name(
                primitive_names,
                w.integer(w.fields(id, 5, 1)[0]),
                "builtin",
              ),
            ),
          ),
        ]),
      )
    _ => None
  }
}

///|
fn Exporter::nominal_context(
  self : Exporter,
  ctx : Context,
  path : Json,
) -> Context raise {
  let w = self.wire
  if self.type_env.get(path.stringify()) is Some(info) && w.tag(info) == 0 {
    let data = w.record(w.fields(info, 0, 1)[0], 12)
    self.context(ctx, data[6], path.stringify(), false)
  } else {
    { ..ctx, owner: "type:" + path.stringify(), origin_known: false, }
  }
}
