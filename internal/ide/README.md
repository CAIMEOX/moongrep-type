# Official IDE semantic backend

`moongrep semantics` uses official `moon ide hover` and `moon ide peek-def`
commands after a successful `moon check --no-mbti`. The query scheduler, type
parser, symbol resolution, and index builder are MoonBit. No compiler source, compiler
libraries, serialized frontend representation, or version-specific layout is
used. The former decoder, adapter, runner, and build scripts have been removed.

```sh
moon run --target native . -- semantics examples/semantic-theorems --target wasm > /tmp/index.json
moon run --target native . -- lint examples/semantic-theorems/collections.mbt --semantic-index /tmp/index.json
moon test tests/ide --target native
```

Use a toolchain compatible with the current upstream dependencies. Validation
covers the official 0.10.20 release and 0.10.21 nightly (2026-11-13); the backend
does not pin a compiler layout.
`MOON_HOME`, when set, selects the compiler and IDE tool
together. The original installation is not changed by exporting an index.

## Evidence contract

The source planner reuses MoonGrep's CST parser. It selects authored declarations
containing calls/iteration and enumerates their expression and binding queries.
Derived bodies do not exist in that CST. The snapshot covers those queries,
not every internal compiler node. An unqueried node remains `Unmatched`.

Hover ranges must match the source expression. Constructor/member anchors and
the result type of an already-resolved operator signature have explicit syntax
roles. Non-overloadable language forms such as `is` have their language-defined
Bool type after the project check. No arbitrary enclosing hover is substituted.
Implicit conversions are not exported as extra source expressions.

Hover's MoonBit type syntax is parsed with the existing parser. Types preserve
nominal package paths, function arguments/results, error effects, async status,
and lexical generic owners. Generic declaration schemes carry `polymorphic:
true`; rule type equality does not treat them as instantiated expression types.
Unsupported syntax, unresolved aliases, missing hover results, and ambiguous
definitions remain unavailable. Type strings are never compared for equality.

Definitions identify local variables by canonical file and exact binder range.
Global methods and constructors are checked against their public source
declarations. Alias and re-export locations are canonicalized only when all
returned definitions agree. Qualified constructors query the constructor leaf,
not the type qualifier. A same-spelled user method is a distinct symbol.

The CLI supplies one-based source ranges. They must agree with the authored
CST's scalar columns and exclusive ends. Non-BMP characters, CRLF, qualified
constructor leaves, and field anchors have integration regressions. The adapter
does not translate undocumented LSP offsets or compare types by printed names.

## Snapshot and lifecycle

The first check supplies Moon's JSON source inventory and prebuild outputs.
A second cached check validates captured inputs before queries. Source text,
configuration (including absent configuration files), directory membership,
definition sources, and the active compiler version are rechecked before
publication. Failed checks and input changes publish no partial index.

An enclosing workspace is used when it includes the selected module. An
independent nested module gets its own check with `MOON_WORK=off`; an explicit
`MOON_WORK` manifest remains authoritative. Workspace membership is read with
the existing public syntax parser, not a handwritten manifest lexer.

Queries use `--no-check --target <backend>` against those checked inputs, with
four processes at most and a timeout per query. Results are cached within one
snapshot, then consumed in deterministic source order. Process handles are
closed on success, timeout, or cancellation. There is no persistent cache that
could silently serve data from an earlier source revision.

The direct LSP path was rejected during validation: opening or querying a
project can trigger a check for its preferred target, replacing an explicitly
checked target. The official CLI preserves that selection with `--no-check`.
The backend verifies Moon's active backend inventory before publication.

This correctness tradeoff has a cost: the official CLI starts a process per
unique query. The twenty-theorem corpus (2,634 authored facts, forty findings)
took about 173 seconds in a native integration run on the validation machine.
Deduplication and bounded concurrency reduce repeated work; large exports can
still take minutes. This timing includes checks and index construction, not
just the rule scan against an existing index.

`provider: "moon-ide"` snapshots use the IDE's file context, including the
context selected for test files. They do not combine alternative normal,
whitebox, and blackbox compiler trees. `--semantic-view auto` is the default;
`ide` explicitly selects that label. Other labels apply to imported snapshots
that actually contain them.

The schema, source validation, YAML rules, guards, scan/lint reporting,
`#moongrep.skip`, disables, and the standalone map-fusion report reuse the
existing infrastructure. Missing evidence remains a diagnostic or skipped
candidate; no source edit is authorized by a finding.
