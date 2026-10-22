///|
priv struct SourceInput {
  path : String
  text : String
} derive(FromJson)

///|
priv struct PackageInput {
  key : String
  name : String
  source_root : String
  artifact : String
  import_kind : String
  source_aliases : Array[(String, String)]
} derive(FromJson)

///|
priv struct Manifest {
  compiler_version : String
  sources : Array[SourceInput]
  packages : Array[PackageInput]
} derive(FromJson)

///|
#cfg(target="native")
extern "c" fn exit_process(code : Int) -> Unit = "exit"

///|
#cfg(target="wasm")
fn exit_process(code : Int) -> Unit = "moonbitlang/async" "runtime/exit"

///|
async fn run(args : Array[String]) -> Unit {
  match args {
    [_, "--graph", path] => {
      let graph = @marshal.decode(@fs.read_file(path).binary())
      let summary : Json = {
        "nodes": graph.length(),
        "shared_objects": graph.shared_objects(),
        "root": "\{graph.get(graph.root()).to_repr()}",
      }
      @stdio.stdout.write(summary.stringify() + "\n")
    }
    [_, "--manifest", path] => {
      let manifest : Manifest = @json.from_json(@fs.read_file(path).json())
      let sources : Array[@typedtree.Source] = []
      for source in manifest.sources {
        if @fs.read_file(source.path).text() != source.text {
          fail("source changed before semantic extraction: \{source.path}")
        }
        sources.push({ path: source.path, text: source.text, })
      }
      let packages : Array[@typedtree.Package] = []
      for input_package in manifest.packages {
        if input_package.import_kind != "normal" &&
          input_package.import_kind != "wbtest" &&
          input_package.import_kind != "bbtest" {
          fail("unknown import kind: \{input_package.import_kind}")
        }
        packages.push({
          key: input_package.key,
          name: input_package.name,
          source_root: input_package.source_root,
          artifact: @fs.read_file(input_package.artifact).binary(),
          source_aliases: input_package.source_aliases,
        })
      }
      let json = @typedtree.extract(
        manifest.compiler_version,
        sources,
        packages,
      )
      ignore(
        @semantic.Index::from_json(
          json,
          compiler_version=manifest.compiler_version,
        ),
      )
      for source in sources {
        if @fs.read_file(source.path).text() != source.text {
          fail("source changed during semantic extraction: \{source.path}")
        }
      }
      @stdio.stdout.write(json.stringify() + "\n")
    }
    _ => fail("usage: semantic-reader --manifest <file> | --graph <file>")
  }
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      @stdio.stderr.write("moonc-reader: \{error}\n")
      exit_process(2)
    }
  }
}
