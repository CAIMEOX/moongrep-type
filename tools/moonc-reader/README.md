# MoonBit semantic reader

The Marshal decoder and typedtree adapter are written in MoonBit. Building,
validation and execution use the installed MoonBit toolchain; no OCaml compiler,
compiler checkout, compiler archives, FFI into compiler internals, or generated
compiler-source bindings are used.

## Build and run

```sh
node scripts/build-moonc-reader.mjs

_build/semantic-reader/moonc-reader --project /path/to/project
_build/semantic-reader/moonc-reader --project /path/to/file.mbt --target native

moon run . -- semantics . --reader ./_build/semantic-reader/moonc-reader --json
```

Node.js runs the existing project orchestration. The native executable is built
from `cmd/semantic-reader` using `moon build`. The build script verifies the
installed nightly before publishing the wrapper. All build outputs stay under
`_build/semantic-reader`; the compiler installation is unchanged.

The supported artifact producer is exactly
`v0.10.14+7080b3792-nightly (2026-10-10)`. Other producer versions are rejected.
The typedtree wire schema is version-specific: Marshal itself does not store
record field names or OCaml variant constructor names.

## Decoding and extraction

`internal/ocaml_marshal` implements the uncompressed OCaml Marshal small and big
headers. It decodes signed integers, byte strings, ordinary blocks, shared
references, floating-point bit patterns and float arrays, and the standard
`_i`, `_j` and `_n` integer custom blocks. Shared references and cycles retain
arena node identities. Parsing uses an explicit work stack, including deeply
nested blocks. Bounds, payload length, object counts and backward references are
checked. Unsupported custom codecs, compressed headers and executable values
are rejected. Strings are decoded as UTF-8 only where the typedtree schema calls
for text; binary strings remain bytes.

The public OCaml wire format is described in
[OCaml's format definition](https://github.com/ocaml/ocaml/blob/4.14.1/runtime/caml/intext.h).
The decoder is an independent implementation, not a linked OCaml runtime.

`internal/typedtree` describes the nightly's serialized layouts with checked
tags and field counts. It traverses expressions, patterns, parameters,
declarations, generics, aliases, fields, constructors, constraints and effects.
It performs no type inference or name resolution: types and identities come
from the checked artifact. Unknown layouts produce an error instead of a
partial successful index. Function and trait parameter scopes, local compiler
stamps and package build views keep unrelated symbols separate.

The runner first performs a successful `moon check` into its own temporary build
directory. It reads that fresh package inventory and replays selected package
checks with only their output paths changed. Sources, configuration, dependency
interfaces and source-directory membership are checked for changes before the
result is emitted. Temporary artifacts are removed after extraction. Failed
checks or changed inputs never reuse an older successful snapshot.

## Snapshot and source association

Stdout is one JSON object; diagnostics use stderr. Schema version 1 contains:

- `compiler_version` and `position_encoding: "unicode-scalar"`.
- `sources`: canonical absolute paths and the exact checked source text.
- `types`: an ID-indexed structured graph of builtin, named, function,
  parameter, trait-object, linked-variable, unresolved and recovery types.
- `symbols`: IDs and structural identities for values, methods, type parameters,
  local bindings, fields, constructors, types and labels.
- `facts`: kind, compiler node kind, package build-view key, optional type/symbol
  IDs, optional source range and additional details.

Function types preserve argument/result types, error effects and async status.
Instantiation arguments, generic constraints and alias targets are retained.
Fields are identified by their owning type and position; extensible and error
constructors preserve their declaring identities. Calls through function values
remain indirect or binding calls, rather than being assigned a guessed callee.

Locations contain `{file, start: {line, column}, end: {line, column}}`. Lines and
Unicode scalar columns are one-based, and the end is exclusive. They are not
UTF-8 byte offsets or UTF-16 columns. Each top-level item's own base position is
used. Source aliases supplied by the runner resolve symlink spellings to the
canonical checked file.

The existing `semantic.Index` validates source ranges and type/symbol references.
The query bridge keeps the original CST and supports multiple facts per range:

```moonbit
let index = @semantic.Index::parse(snapshot_json, compiler_version~)
let source = @query.SemanticSource::parse(index, file~, text~)
let query = @query.ExprQuery::ExprQuery("consume($(value:exp))")
for captures in query.captures_from_semantic_source(source) {
  let associations = source.facts_for_capture(captures["value"])
  debug_inspect(associations)
}
```

The supplied compiler version must be independently obtained, and source text
must match the snapshot. A node from another parse is rejected. `Associated`,
`Ambiguous`, and `Unmatched` are explicit; an enclosing location is never silently
substituted for an exact match.

The [map-fusion POC](../../internal/semantic_rules/README.md) uses this index and
the original CST to recognize adjacent standard-library `Array::map` calls. It
checks resolved method identities and type composition, and returns source
evidence and review obligations without editing code.

## Boundaries

The index covers the selected source packages. External references retain their
qualified identities; unavailable external definitions are not fabricated.
Compiler-generated nodes can share ranges or have no source location. Copied
constraints whose defining base is unavailable have no invented caller range.
Opaque auxiliary metadata is not presented as a resolved semantic node.

`details.generated_top_level` records compiler-generated top-level bodies and
is inherited by their child facts. It identifies derived implementations even
when they reuse the authored type declaration's range. Handwritten impls remain
unmarked. The reader preserves these facts; semantic rules exclude them while
default Index/Source queries remain complete. This provenance is distinct from
`details.implicit`, which can describe conversions inside handwritten code.

Packed compiler positions have limits. The runner rejects lines over 65,535
Unicode scalars and delimiter-free blocks over 16,383 lines, rather than using
truncated positions. The block check is conservative when `///|` separators are
omitted. This does not reconstruct a control-flow graph or perform alias/taint
analysis.

The project runner currently buffers the exported JSON with a 256 MiB limit.
Exceeding it fails the command instead of emitting a truncated snapshot.

## Validation

```sh
moon test internal/ocaml_marshal internal/typedtree
node tools/moonc-reader/compatibility.mjs
node tools/moonc-reader/test.mjs
node tools/moonc-reader/tests/runner.mjs
```

The compatibility test uses only the installed `moonc`: it obtains a native
`.typedtree` dump and independently decodes a `.typechecked` artifact from the
same source. It compares every expression/pattern type and range in that test
corpus, plus the equivalence classes of local bindings and references. Debug
printer stamp renumbering does not affect that relationship comparison.

Integration tests cover multiple files/packages, source aliases, generics,
traits, views, async/error effects, dead branches, constructor and field
identities, shadowing, or-patterns and Unicode. Runner tests cover package views,
workspaces, standalone files, input mutations, failed checks and cleanup. All
fixtures are copied to owned temporary directories.
