# Semantic rule examples

`collections.mbt` contains positive examples, including generic and Unicode
cases. `negative.mbt` contains cases that the checks must reject. `foreign/`
defines lookalike methods to show why spelling alone is insufficient.

Run from the MoonGrep repository root with the active MoonBit toolchain:

```sh
moon run --target native . -- lint examples/semantic-rules
```

The default output uses MoonGrep's existing source context and highlighting.
Set `NO_COLOR=1` for plain text, or add `--json` for the existing finding and
diagnostic JSON Lines formats. These are suggestions; no source is rewritten.
The original checks produce 18 findings. The nested match in `filter_map_option`
also qualifies for `match_option_map`, giving 19 semantic findings.

## YAML configuration

The seven checks demonstrated here have YAML rule files in
[`internal/rule/lintrules/moonbitlang`](../../internal/rule/lintrules/moonbitlang).
Ordinary `lint` includes the semantic builtins. It queries the IDE only after a YAML shape and its guards match.

The additional [20 semantic theorems](../semantic-theorems/README.md) use the
same pipeline. The [25 standard-library patterns](../stdlib-patterns/README.md)
have their own runnable examples and negative cases.

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
moon run --target native . -- scan examples/semantic-rules --rule examples/semantic-rules/custom-count.yaml
```

YAML controls the rule id, description, structural alternatives, and regex
guards. `check` selects a built-in semantic analysis; adding a new analysis
requires MoonBit code. Unknown checks and unsupported keys are rejected.
Regex guards use the same id/constant capture restrictions as structural rules.
`semantic` cannot be mixed with structural or taint fields in one rule.

Disable a loaded builtin with its ordinary qualified rule id:

```sh
moon run --target native . -- lint examples/semantic-rules --disable moonbitlang/array_map_fusion
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

Use `--target` to check a specific backend. Each candidate uses the IDE context
for its source file. Failed checks or changes to checked sources use exit code 6.

Run the integration checks:

```sh
moon test tests/ide --target native
```
