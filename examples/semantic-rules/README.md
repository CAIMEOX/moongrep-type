# Array and iterator rules

[中文](README_CN.md)

These rules cover comprehension syntax, discarded allocations and repeated traversal. `moongrep lint` reports a source location and a suggestion. Builtin rule IDs use the `moonbitlang/` prefix.

| Rule | YAML `semantic.check` | When it applies |
| --- | --- | --- |
| `prefer_array_comprehension` | `array-comprehension` | A fresh `[]`, a loop that pushes one value per selected item, and the array as the result. Use `[for x in xs if keep(x) => f(x)]`. The accumulator must have no other uses and the loop must have no early exits or loop-state clauses. |
| `prefer_filter_map_comprehension` | `filter-map-comprehension` | A synchronous, non-raising `Array::filter_map` lambda selects `Some(value)` or `None` with an `if` or a simple exhaustive `Option` match. A filtered array comprehension keeps the condition and payload in order. |
| `prefer_iter_comprehension` | `iter-comprehension` | For `it.filter(p).map(f)` on an immutable iterator binding, use `[\| for x in it if p(x) => f(x) \|]`. An immediately collected pipeline can use an array comprehension. The callbacks must be synchronous and non-raising, and their evaluation must be safe to move. |
| `avoid_collect_for_count` | `collect-count` | `it.collect().length()` or `it.to_array().length()` consumes the iterator to obtain its length. Use `it.count()`. |
| `discarded_array_map` | `discarded-array-map` | `ignore(xs.map(f))` builds an unused array. Use a loop or `Array::each` for the callback's effects. Preserve the evaluation of `xs` and `f`, and discard the callback result if needed. |
| `consumed_iterator` | `consumed-iterator` | Two adjacent statements call `count`, `collect`, `to_array` or `last` on the same immutable iterator binding. Obtain a fresh iterator if the second statement needs another traversal. |
| `array_map_fusion` | `array-map-fusion` | `xs.map(g).map(f)` with compatible standard `Array::map` calls can become `xs.map(x => f(g(x)))` after reviewing callback effects and termination. |

Eager array fusion changes the order of calls across elements. On a two-element array the original runs `g, g, f, f`, while the fused version runs `g, f, g, f`. The types alone cannot establish purity. Also preserve when callback factories run. [Fusion details](../../internal/semantic_rules/README.md#array-map-fusion)

## Run and configure

Run from the MoonGrep repository root. The first command uses the builtins and the second runs only the example YAML rule.

```sh
moon run --target native . -- lint examples/semantic-rules/collections.mbt
moon run --target native . -- scan examples/semantic-rules --rule examples/semantic-rules/custom-count.yaml
```

`semantic.check` selects the type and symbol checks. YAML can narrow the source shapes and add regex guards. This example limits the count suggestion to an iterator named `it`.

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

Use `--disable moonbitlang/array_map_fusion` to turn off one builtin or `#moongrep.skip` to skip a declaration. Add `--target wasm` to select the target of the code being checked. [Builtin YAML files](../../internal/rule/lintrules/moonbitlang) · [Rule specification](../../internal/docs/RuleSpec.md#semantic-rules)
