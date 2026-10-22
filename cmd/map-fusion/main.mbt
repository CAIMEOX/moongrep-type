///|
#cfg(target="native")
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
#cfg(target="wasm")
fn exit_process(code : Int) -> Unit = "moonbitlang/async" "runtime/exit"

///|
async fn run(args : Array[String]) -> Unit {
  guard args is [_, "--index", path] else {
    fail("usage: moon run cmd/map-fusion -- --index <semantic-index.json>")
  }
  let (status, version, diagnostics) = @process.collect_output("moonc", ["-v"])
  if status != 0 {
    fail("moonc -v failed: \{diagnostics.text()}")
  }
  let index = @semantic.Index::parse(
    @fs.read_file(path).text(),
    compiler_version=version.text().trim().to_owned(),
  )
  let reports : Array[Json] = []
  for file in index.sources() {
    let source = @semantic_source.Source::parse(
      index,
      file=file.path,
      text=@fs.read_file(file.path).text(),
    )
    let report = @semantic_rules.find_map_fusion(source)
    reports.push({ "file": file.path, "report": report.to_json() })
  }
  for file in index.sources() {
    index.require_source(file.path, @fs.read_file(file.path).text())
  }
  let output : Json = {
    "schema_version": 1,
    "compiler_version": index.compiler_version(),
    "position_encoding": "unicode-scalar",
    "files": reports,
  }
  @stdio.stdout.write(output.stringify() + "\n")
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("map-fusion: \{error}\n")
      exit_process(2)
    }
  }
}
