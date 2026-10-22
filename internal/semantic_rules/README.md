# Semantic rules

The YAML-driven checks run through `scan` and `lint` with `--semantic-index`.
See [the examples](../../examples/semantic-rules/README.md) for configuration,
commands, and each check's scope. Rule loading, compilation, regex guards,
structural matching, prefiltering, disables, source display, and diagnostics use
the existing MoonGrep infrastructure.

`semantic.check` selects one of 27 built-in analyses: seven original checks and
[20 semantic theorems](../../examples/semantic-theorems/README.md). Its `patterns` narrow
the candidates using the same surface-syntax matcher as structural rules.
Semantic checks confirm compiler identities, normalized types, binding uses,
and the required control-flow shape. Incomplete evidence remains explicit.

The standalone map-fusion command below remains a compatibility/demo entrypoint.

The first rule recognizes `xs.map(g).map(f)` when both calls resolve to the
standard library's `Array::map`. The map law is
`map f ∘ map g = map (f ∘ g)`, so the proposed composition is `f(g(x))`.

## Architecture

```text
installed moonc
  → pure MoonBit Marshal / typedtree adapter
  → semantic.Index (validated types, symbols, source snapshots)
  → semantic_source.Source (original CST + exact source ranges)
  → semantic_rules.find_map_fusion (candidates + evidence + skipped reasons)
  → moongrep map-fusion (existing CLI renderers, or --json)
```

The compiler adapter owns the version-specific wire format. Rules depend on the
semantic index and the existing CST traversal, with no compiler source or library
dependency. The rule accepts a checked source and returns data; it performs no
I/O and never edits source. The CLI shares compiler-version and file-freshness
checks with `semantics`. Candidates adapt to `RuleFinding` and `ScanHit` and use
the existing source-context renderer, highlighting, and `NO_COLOR` behavior.
The command also shares argparse, diagnostics, output errors, and exit codes.
`cmd/map-fusion` is a thin compatibility entrypoint to that same CLI.

JSON values and parsing use MoonBit's standard library. Fixed report structures
use `derive(ToJson)`, and fixed display metadata uses `derive(FromJson)`.
Semantic graph validation and rendering MoonBit type names remain domain logic.

The common checks and source-view selection are shared by the YAML analyses.
The existing syntax-only YAML rules still run without compiler artifacts.

## Recognition contract

1. Find adjacent dot calls with one positional callback each.
2. Join the original CST nodes to exact expression ranges. Auxiliary
   `function_body` metadata does not compete with actual typed expression nodes.
   Missing, ambiguous, or multiple typed expression facts produce a skipped
   result. This includes source files represented by multiple package/test views;
   the POC does not guess a view or select an enclosing expression.
3. Require both calls to resolve to the same global method identity:
   `moonbitlang/core/builtin.Array::map`. A user method named `map`, `Option::map`,
   `Iter::map`, and indirect calls do not qualify.
4. Check the receiver, intermediate result, and final result are `Array[A]`,
   `Array[B]`, and `Array[C]`; check callback types `A → B` and `B → C`.
   Type IDs are handles, not equality. Follow resolved variables and compare
   structural types, keeping nominal paths and generic parameter owners.
   Unknown, cyclic, or excessively deep types are not proof of equality.
5. For this POC, callbacks must be synchronous and have no checked error effect.
   This does **not** establish purity or termination.

Candidates include source snippets and ranges, package view, resolved symbol,
fact IDs, type IDs, and the normalized type flow. Skipped results explain which
condition could not be established. A three-map chain produces two overlapping
candidates. Qualified function-call syntax and maps separated by bindings are
outside this first recognizer.

## Why no automatic fix

For a finite array and pure, total callbacks:

```text
xs.map(g).map(f)[i]
= f(xs.map(g)[i])       (definition of map)
= f(g(xs[i]))           (definition of map)
= xs.map(x => f(g(x)))[i]
```

Both sides have the same length and elements. Fusion avoids the intermediate
array and one traversal. Resource failures are outside this algebraic model.

But eager map runs `g(x0), g(x1), f(y0), f(y1)`, whereas fusion runs
`g(x0), f(y0), g(x1), f(y1)`. Mutation, I/O, exceptions, or divergence can make
these differ. Callback expressions themselves can also have effects: a naive
replacement of `xs.map(make_g()).map(make_f())` reevaluates factories per element
and changes when `make_f()` runs. Captured mutable bindings need attention too.

Every result therefore has status `requires_review`, with no replacement edit.
Before implementing fixes, we need effect/termination evidence, preservation of
receiver and callback evaluation, and fresh names for generated bindings. A
non-raising arrow from moonc alone is insufficient.

## Run

From the repository root, using the nightly supported by the reader:

```sh
node scripts/build-moonc-reader.mjs
_build/semantic-reader/moonc-reader --project tools/map-fusion/fixture > /tmp/map-index.json
moon run . -- map-fusion --index /tmp/map-index.json
```

The default output is a terminal report with source ranges, numbered code
snippets, readable type flow, review notes, and explanations for skipped chains:

```text
Array.map fusion: 8 candidates, 4 skipped
Pattern: xs.map(g).map(f) => xs.map(x => f(g(x)))

.../maps.mbt:19:3-19:35
rule: array-map-fusion
description:
  Array.map fusion candidate; review required.
  Types: Array[Int] -> Array[String] -> Array[Int]
source:
17 | ///|
18 | pub fn named(xs : Array[Int]) -> Array[Int] {
19 >   xs.map(to_text).map(text_length)
20 | }
21 |
```

This example uses `NO_COLOR=1`. Without it, matched source is highlighted using
the same colors as `scan` and `lint`.

Use `--json` for the structured report, or run the integration checks:

```sh
moon run . -- map-fusion --index /tmp/map-index.json --json
node tools/map-fusion/test.mjs
```

The command checks the installed `moonc -v` independently, validates the index,
and checks the source files before analysis and before emitting the report.
It fails on stale snapshots rather than returning a misleading empty report.
Input failures use `scan_input` and exit code 6; usage errors use exit code 2.
