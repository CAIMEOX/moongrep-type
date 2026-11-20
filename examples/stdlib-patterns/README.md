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

## Handwritten Option and Result operations

Scan `examples/stdlib-patterns/matches.mbt` for these examples. Both case
orders qualify. The matcher resolves constructors and checks that forwarded
values refer to the corresponding pattern binder.

| Rule | Match arms | Standard-library expression |
| --- | --- | --- |
| `match_option_map` | `Some(x) => Some(f(x))`, `None => None` | `v.map(x => f(x))` |
| `match_option_bind` | `Some(x) => f(x)`, `None => None` | `v.bind(x => f(x))` |
| `match_option_unwrap_or` | `Some(x) => x`, `None => d` | `v.unwrap_or(d)` |
| `match_option_unwrap_or_else` | `Some(x) => x`, `None => read()` | `v.unwrap_or_else(() => read())` |
| `match_result_map` | `Ok(x) => Ok(f(x))`, `Err(e) => Err(e)` | `r.map(x => f(x))` |
| `match_result_map_err` | `Ok(x) => Ok(x)`, `Err(e) => Err(f(e))` | `r.map_err(e => f(e))` |
| `match_result_bind` | `Ok(x) => f(x)`, `Err(e) => Err(e)` | `r.bind(x => f(x))` |
| `match_result_to_option` | `Ok(x) => Some(x)`, `Err(_) => None` | `r.to_option()` |
| `match_result_unwrap_or` | `Ok(x) => x`, `Err(_) => d` | `r.unwrap_or(d)` |
| `match_result_unwrap_or_else` | `Ok(x) => x`, `Err(_) => read()` | `r.unwrap_or_else(() => read())` |

A transform may be a synchronous unary call (including a checked error) or
primitive arithmetic/comparison with a literal, such as `Some(x + 1)`.
`bind` requires a callback returning the expected sum type. An eager default
must be a primitive literal or an immutable local. A nullary fallback call
stays in a closure and may raise. Guards, complex payload patterns and extra
statements need individual review.

## Short-circuit loops and ASCII predicates

Scan `examples/stdlib-patterns/predicates.mbt` for these examples.

| Rule | Recognized source | Standard-library expression |
| --- | --- | --- |
| `loop_any` | Break with `true` on a hit and finish with `false` | `xs.any(x => p(x))` |
| `loop_all` | Break with `false` on a failed test and finish with `true` | `xs.all(x => p(x))` |
| `loop_find_first` | Break with `Some(x)` on a hit and finish with `None` | `it.find_first(x => p(x))` |
| `char_ascii_digit` | `'0' <= c && c <= '9'` | `c.is_ascii_digit()` |
| `char_ascii_lowercase` | `c is ('a'..<='z')` | `c.is_ascii_lowercase()` |
| `char_ascii_uppercase` | `'Z' >= c && c >= 'A'` | `c.is_ascii_uppercase()` |

The loop must have one conditional exit and a matching `nobreak`. The
predicate may call a synchronous function or compare the element with a
primitive literal. `all` also accepts a `guard`. Core array types and `Iter`
support `any` and `all`. The element-returning `find_first` requires `Iter`.
A successful iterator search leaves the next element available to the caller.

Match and loop rules that introduce a closure check the binding of each named
callback. MoonBit requires a parameter marked `#locals` to stay in its
declaring function. An ordinary binding with the same spelling can still qualify.

The three ASCII checks accept either order of inclusive comparisons on the
same stable `Char` binding, or a single inclusive range pattern. Each bound
is exact. Range tests on UTF-16 code units have a different receiver type.

To run the behavioral examples, including raised defaults, predicate call
order, iterator consumption and non-ASCII input, run:

```sh
MOON_WORK=off moon -C examples/stdlib-patterns test
```
