///|
priv struct Client {
  root : String
  backend : String
  environment : Map[String, String]
  cache : Map[String, @async.Lazy[Json]]
}

///|
fn query_key(command : String, file : String, point : Point) -> String {
  "\{command}:\{file}:\{point.line}:\{point.column}"
}

///|
async fn Client::request(
  self : Client,
  subcommand : String,
  file : String,
  point : Point,
) -> Json {
  let key = query_key(subcommand, file, point)
  if self.cache.get(key) is Some(answer) {
    return answer.wait()
  }
  let answer = @async.Lazy::Lazy(() => self.fetch(subcommand, file, point))
  self.cache[key] = answer
  answer.wait()
}

///|
async fn Client::fetch(
  self : Client,
  subcommand : String,
  file : String,
  point : Point,
) -> Json {
  let location = "\{file}:\{point.line}:\{point.column}"
  let (status, stdout, stderr) = @async.with_timeout(30000, () => {
    @process.collect_output(
      tool_program("moon"),
      [
        "-C",
        self.root,
        "ide",
        subcommand,
        "--loc",
        location,
        "--target",
        self.backend,
        "--no-check",
        "--json",
      ],
      cwd=self.root,
      extra_env=self.environment,
    )
  })
  let result = if status == 0 {
    stdout.json()
  } else {
    let output = stdout.text().trim().to_owned()
    let missing = if subcommand == "hover" {
      "No hover information found at " + location
    } else {
      "Error: could not find definition at " + location
    }
    if status != 1 || output != missing || !stderr.text().trim().is_empty() {
      fail(
        "moon ide \{subcommand} exited with \{status}: \{stderr.text()}\{stdout.text()}",
      )
    }
    Json::null()
  }
  result
}

///|
async fn Client::hover(
  self : Client,
  file : String,
  point : Point,
) -> (String, Span)? {
  let result = self.request("hover", file, point)
  if result is Null {
    return None
  }
  guard result is { "range": String(range), "contents": Array(contents), .. } else {
    fail("unsupported moon ide hover response")
  }
  guard contents is [String(markdown), ..] else {
    fail("unsupported moon ide hover contents")
  }
  guard markdown.replace_all(old="\r\n", new="\n").strip_prefix("```moonbit\n")
    is Some(code) else {
    return None
  }
  let text = code.split("```").to_array()[0].trim().to_owned()
  Some((text, cli_span(range)))
}

///|
priv struct Definition {
  file : String
  range : Span
}

///|
async fn Client::locations(
  self : Client,
  file : String,
  point : Point,
  documents : Map[String, String],
  command~ : String = "peek-def",
) -> Array[Definition] {
  let result = self.request(command, file, point)
  if result is Null {
    return []
  }
  guard result is Array(definitions) else {
    fail("unsupported moon ide definition response")
  }
  let found = []
  for definition in definitions {
    guard definition is { "path": String(file), "range": String(range), .. } else {
      fail("unsupported moon ide definition location")
    }
    let file = @fs.realpath(file)
    if !documents.contains(file) {
      let text = @fs.read_file(file).text()
      if documents.get(file) is Some(before) && before != text {
        fail("IDE definition changed: \{file}")
      }
      documents[file] = text
    }
    let range = cli_span(range)
    require_source_span(range, documents[file])
    found.push({ file, range, })
  }
  found
}
