# Standard-library patterns

Run these commands from the MoonGrep repository. The outer target builds the
native CLI. The inner target selects the backend for checking the example.

```sh
moon run --target native . -- lint examples/stdlib-patterns/idioms.mbt --target wasm
moon run --target native . -- scan examples/stdlib-patterns/idioms.mbt --rule internal/rule/lintrules/moonbitlang/map_get_contains.yaml --target wasm
```

Each row has a YAML rule in [the builtin rule directory](../../internal/rule/lintrules/moonbitlang).
The builtin ID is `moonbitlang/` followed by the name in the first column.
All findings are suggestions. A custom shape still has to pass its semantic check.

| Rule | Recognized source | Suggestion or condition |
| --- | --- | --- |
| `collection_is_empty` | `xs.length() == 0`, `!= 0`, `> 0`, and reversed comparisons | `xs.is_empty()` or its negation. Supports core arrays, read-only arrays, array views, maps, strings, bytes and their string/byte views. |
| `string_find_contains` | `s.find(needle) is Some(_)` | `s.contains(needle)`, including an empty needle. |
| `string_prefix_presence` | `s.strip_prefix(prefix) is Some(_)` | `s.has_prefix(prefix)`. |
| `string_suffix_presence` | `s.strip_suffix(suffix) is Some(_)` | `s.has_suffix(suffix)`. |
| `map_get_contains` | `m.get(k) is Some(_)` | `m.contains(k)`. A key holding `None` is present. |
| `array_search_contains` | `a.search(v) is Some(_)` | `a.contains(v)` for primitive elements with builtin equality. |
| `array_search_by_any` | `a.search_by(p) is Some(_)` | `a.any(p)` with the same short-circuit order and synchronous predicate. |
| `iter_drop_next` | `it.drop(3).next()` | `it.nth(3)`. Only a representable nonnegative decimal Int literal qualifies. |
| `map_get_default` | `m.get(k).unwrap_or(d)` | `m.get_or_default(k, d)` for a primitive literal or immutable local binding. Evaluating an effectful default before the lookup could change the result. |

The presence checks also accept `is None` (negate the suggested predicate)
and the legacy Option methods `is_some()` and `is_none()`. A pattern testing
a payload or binding a value needs more than a presence test. Source methods
and constructors must resolve to the standard library.
