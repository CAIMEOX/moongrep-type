///|
fn Exporter::arity(self : Exporter, id : Int) -> Json raise {
  let w = self.wire
  match w.tag(id) {
    0 =>
      obj([
        ("kind", str("positional")),
        ("count", num(w.integer(w.fields(id, 0, 1)[0]))),
      ])
    1 => {
      let params = w
        .list(w.fields(id, 1, 1)[0])
        .map(param => {
          let tag = w.tag(param)
          if tag == 0 {
            return obj([
              ("kind", str("positional")),
              ("index", num(w.integer(w.fields(param, 0, 1)[0]))),
            ])
          }
          let f = w.fields(param, tag, if tag == 3 { 3 } else { 5 })
          let aliases = w
            .list(f[if tag == 3 { 1 } else { 3 }])
            .map(item => {
              let alias_data = w.record(item, 2)
              let label = w.record(alias_data[0], 2)
              obj([
                ("name", str(w.text(label[0]))),
                (
                  "message",
                  match w.option(alias_data[1]) {
                    Some(s) => str(w.text(s))
                    None => Json::null()
                  },
                ),
              ])
            })
          let fields = [
            (
              "kind",
              str(
                select_name(
                  ["labelled", "optional", "autofill"],
                  tag - 1,
                  "arity parameter",
                ),
              ),
            ),
            ("label", str(w.text(f[0]))),
            ("aliases", Json::array(aliases)),
          ]
          if tag == 1 {
            fields.push(("mutable", bool(w.bool(f[1]))))
          }
          if tag == 2 {
            fields.push(("default", self.raw(f[1], 8)))
          }
          obj(fields)
        })
      obj([("kind", str("labelled")), ("parameters", Json::array(params))])
    }
    _ => raise Invalid("unknown function arity")
  }
}

///|
fn Exporter::param_kind(self : Exporter, id : Int) -> String raise {
  match self.wire.value(id) {
    Integer(0L) => "positional"
    Integer(1L) => "autofill"
    Integer(2L) => "question_optional"
    Block(tag=0, ..) => "labelled"
    Block(tag=1, ..) => "optional"
    _ => raise Invalid("unknown parameter kind")
  }
}
