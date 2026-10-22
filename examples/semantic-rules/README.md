# Semantic rule examples

`collections.mbt` contains positive examples, including generic and Unicode
cases. `negative.mbt` contains cases that the checks must reject. `foreign/`
defines lookalike methods to show why spelling alone is insufficient.

Run from the MoonGrep repository root with the reader's supported nightly:

```sh
node scripts/build-moonc-reader.mjs
_build/semantic-reader/moonc-reader --project examples/semantic-rules > /tmp/collection-index.json
moon run . -- lint examples/semantic-rules --semantic-index /tmp/collection-index.json
```

The default output uses MoonGrep's existing source context and highlighting.
Set `NO_COLOR=1` for plain text, or add `--json` for the existing finding and
diagnostic JSON Lines formats. These are suggestions; no source is rewritten.
There are 18 semantic findings in this example, plus any ordinary lint findings.

## YAML configuration

All seven checks have YAML rule files in
[`internal/rule/lintrules/moonbitlang`](../../internal/rule/lintrules/moonbitlang).
`lint --semantic-index` enables these builtins alongside the ordinary rules.
`lint` without an index keeps its existing syntax-only behavior.

`custom-count.yaml` demonstrates a user-authored semantic rule:

```yaml
id: custom_count
description: Prefer count() when only the length is needed.
semantic:
  check: collect-count
  patterns:
    - shape: $(iterator:id).collect().length()
      guard:
        $iterator: '^it$'
```

Run that rule alone through the normal rule loader:

```sh
moon run . -- scan examples/semantic-rules --rule examples/semantic-rules/custom-count.yaml --semantic-index /tmp/collection-index.json
```

YAML controls the rule id, description, structural alternatives, and regex
guards. `check` selects a built-in semantic analysis; adding a new analysis
requires MoonBit code. Unknown checks and unsupported keys are rejected.
Regex guards use the same id/constant capture restrictions as structural rules.
`semantic` cannot be mixed with structural or taint fields in one rule.

Disable a loaded builtin with its ordinary qualified rule id:

```sh
moon run . -- lint examples/semantic-rules --semantic-index /tmp/collection-index.json --disable moonbitlang/array_map_fusion
```

## Checks and limits

| `semantic.check` | Recognized scope |
| --- | --- |
| `array-comprehension` | A contiguous fresh-array binding, one `for in` loop, and the final array value. The loop pushes once per selected element, optionally under `if`. No other accumulator references, escapes, early exits, or loop-state clauses. |
| `filter-map-comprehension` | `Array.filter_map` with a synchronous non-raising lambda using `if` with `Some`/`None`, or an exhaustive `Option` match with a simple payload binder. |
| `iter-comprehension` | Standard `Iter.filter(...).map(...)`, optionally immediately collected. Requires an already-bound immutable iterator and simple synchronous non-raising callbacks. Factories, mutable callback bindings, and abrupt control flow are excluded. |
| `collect-count` | Standard `Iter.collect()` / `to_array()` immediately followed by `Array.length()`. |
| `discarded-array-map` | Standard `ignore(Array.map(...))`. The suggestion preserves callback effects and requires preserving evaluation of callback expressions. |
| `consumed-iterator` | Two adjacent statements consume the same immutable iterator binding through `count`, `collect` / `to_array`, or `last`. Calls may be direct, let-bound, or wrapped in standard `ignore`. This does not attempt alias analysis or control-flow analysis across intervening statements. |
| `array-map-fusion` | The existing type-compatible Array.map fusion candidate. Purity and termination still require review. |

The checks confirm resolved compiler identities and types. Missing, ambiguous,
or unresolved evidence yields a semantic warning rather than an asserted match.
`#moongrep.skip` suppresses these findings just as it suppresses structural rules.

`--semantic-view normal` is the default. Use `wbtest` or `bbtest` explicitly to
analyze a test build view. Selecting a view filters facts without deleting the
other views from the index. The scan scope must be covered by the index; unreadable,
incompatible, missing-source, or stale snapshots fail with exit code 6.
Regenerate the index after changing source. Loading an enabled semantic rule
without `--semantic-index` is a usage error (exit code 2).

The contracts are pinned to `v0.10.14+7080b3792-nightly (2026-10-10)`.
For example, this compiler evaluates an Iter comprehension's source immediately
and its body lazily. Rules preserve the already-bound iterator and do not turn
an eager Array pipeline into a lazy Iter pipeline.

Run the integration checks:

```sh
node tools/semantic-rules/test.mjs
```
