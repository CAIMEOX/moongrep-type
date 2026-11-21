# Collection, Option, and Result rules

[中文](README_CN.md)

## Catalogue

Each row names a YAML `semantic.check`. Its builtin rule ID uses the `moonbitlang/` prefix and underscores in place of hyphens, as in `moonbitlang/array_filter_count`.

| Check | Matched expression → suggested expression |
| --- | --- |
| `array-filter-count` | `a.filter(p).length()` → `a.count_if(p)` |
| `iter-filter-count` | `it.filter(p).count()` → `it.count_if(p)` |
| `iter-filter-next` | `it.filter(p).next()` → `it.find_first(p)` |
| `iter-find-first-exists` | `it.find_first(p) is Some(_)` → `it.any(p)`, or `is None` → `!it.any(p)`. Also accepts `.is_some()` and `.is_none()`. |
| `iter-map-flatten` | `it.map(f).flatten()` → `it.flat_map(f)` |
| `option-map-fusion` | `o.map(f).map(g)` → `o.map(x => g(f(x)))` |
| `result-map-fusion` | `r.map(f).map(g)` → `r.map(x => g(f(x)))` |
| `result-map-err-fusion` | `r.map_err(f).map_err(g)` → `r.map_err(e => g(f(e)))` |
| `option-bind-map` | `o.bind(x => Some(body))` → `o.map(x => body)` |
| `result-bind-map` | `r.bind(x => Ok(body))` → `r.map(x => body)` |
| `result-map-flatten` | `r.map(f).flatten()` → `r.bind(f)` |
| `option-filter-fusion` | `o.filter(p).filter(q)` → `o.filter(x => p(x) && q(x))` |
| `option-map-default` | `o.map(f).unwrap_or_else(d)` → `o.map_or_else(d, f)` |
| `option-map-identity` | `o.map(x => x)` → `o` |
| `result-map-identity` | `r.map(x => x)` → `r` |
| `option-bind-identity` | `o.bind(x => Some(x))` → `o` |
| `result-bind-identity` | `r.bind(x => Ok(x))` → `r` |
| `option-unwrap-some` | `Some(x).unwrap()` → `x` |
| `result-unwrap-ok` | `Ok(x).unwrap()` → `x` |
| `result-unwrap-err` | `Err(e).unwrap_err()` → `e` |

## Matching conditions

**Iterator consumption.** Counting traverses the full input. Searching stops at the first hit and leaves the remaining elements available. The presence check requires the standard `None` or `Some(_)` pattern, including qualified forms such as `Option::Some(_)`. Binding a payload or testing a nested pattern requires more than a presence test. `flat_map` preserves the nested lazy traversal. These collection rules preserve the evaluation order of the receiver and callback expressions, including callback factories.

**Callback evaluation.** In Option and Result map fusion, only the selected branch calls `f` and then `g`. With Option filter fusion, `q` runs only when `p` succeeds. Fusing a lazy default evaluates only the selected transform or fallback. A callback moved into a closure must be an immutable function binding or a literal lambda that does not capture a mutable binding. When composing callbacks, keep each function's `return` inside its own scope. The rules require synchronous callbacks and preserve checked errors where both methods support them.

**Constructors and identity.** Bind-to-map suggestions remove only the outer standard `Some` or `Ok` from a literal lambda. An early return targeting that callback can change the result. In `r.map(f).flatten()`, the receiver and the `Result` returned by `f` must share an error type. The identity rules require the returned variable to be the actual callback parameter. Rebuilding a variant can change its physical identity, so the four map/bind identity rules require an immediate tag test, a match that does not bind the whole variant, or a standard payload accessor. Unwrapping a known standard constructor preserves the payload and evaluates it once.

## Run

From the repository root, run the builtins on an example or select a single YAML rule. The examples cover [collections](collections.mbt), [callback fusion](option_fusion.mbt) and [identities](identities.mbt).

```sh
moon run --target native . -- lint examples/semantic-theorems/option_fusion.mbt --target wasm
moon run --target native . -- scan examples/semantic-theorems/collections.mbt --rule internal/rule/lintrules/moonbitlang/iter_filter_count.yaml --target wasm
```

A custom YAML rule can narrow the candidate shape or add guards. The selected semantic check still verifies standard-library symbols, types and binding identities. [Rule specification](../../internal/docs/RuleSpec.md#semantic-rules)
