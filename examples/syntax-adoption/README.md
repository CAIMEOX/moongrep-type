# Loop patterns and collection literals

[中文](README_CN.md)

`moongrep lint` includes these four rules. The builtin ID is `moonbitlang/` followed by the rule name.

| Rule | Matched source | Suggested form |
| --- | --- | --- |
| [loop_tuple_unpack](../../internal/rule/lintrules/moonbitlang/loop_tuple_unpack.yaml) | `for pair in rows { let (x, y) = pair; … }` | `for (x, y) in rows { … }` |
| [repeated_classifier](../../internal/rule/lintrules/moonbitlang/repeated_classifier.yaml) | `c == 'a' \|\| c is ('b'..<='f')` | `c is ('a' \| 'b'..<='f')` |
| [iterator_literal](../../internal/rule/lintrules/moonbitlang/iterator_literal.yaml) | `Iter::empty()`, `Iter::singleton(v)`, `[a, b].iter()` | `[\|\|]`, `[\|v\|]`, `[\|a, b\|]` |
| [conditional_array_spread](../../internal/rule/lintrules/moonbitlang/conditional_array_spread.yaml) | Start with `[]`, push one element conditionally, push another unconditionally, then iterate. | `let items = [..if condition { [optional] }, required]` followed by the original loop |

**Tuple unpacking.** The first statement must unpack a pair bound by the loop. This can be the sole loop binding or either binding in a key/value loop. The original binding must have no other uses. Nested tuple patterns, names and wildcards can move into the header when the names remain distinct. A type annotation on the `let` or a loop-state clause prevents the suggestion. [Examples](tuples.mbt)

**Alternatives on a scalar.** Each test must read the same immutable local `Char`, `Byte`, fixed-width integer or `String`. Equality must resolve to the standard implementation. Literals and forward ranges must be disjoint. String alternatives must be plain, unescaped literals. A chain such as `next() == 'a' || next() == 'b'` can call `next` twice. [Examples](classifiers.mbt)

**Iterator literals.** The constructor must be a standard `Iter` method or a call to `Array::iter` on an ordinary array literal. Its elements are evaluated in order when the iterator is created. Existing arrays, slices, spreads and comprehensions fall outside the rule. [Examples](iterators.mbt)

**Conditional array spreads.** The two `Array::push` calls and the loop input must be the only uses of the fresh array. The condition and the elements retain their evaluation order. Keep any type annotation on the original binding. Aliases, capacity reads and extra work in the conditional branch prevent the suggestion. [Examples](spreads.mbt)

## Run

From the repository root, run the builtins on one file or select a single YAML rule. The default output highlights the corresponding source.

```sh
moon run --target native . -- lint examples/syntax-adoption/tuples.mbt --target wasm
moon run --target native . -- scan examples/syntax-adoption/classifiers.mbt --rule internal/rule/lintrules/moonbitlang/repeated_classifier.yaml --target wasm
```

For syntax-only searches, use the [structural YAML examples](rules). For typed rules, the [YAML specification](../../internal/docs/RuleSpec.md#semantic-rules) explains how to narrow the built-in check with a custom shape or guard.
