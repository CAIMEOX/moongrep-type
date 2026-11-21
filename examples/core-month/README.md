# Numeric, iteration, and text rules

[中文](README_CN.md)

`moongrep lint` includes the following rules under the `moonbitlang/` prefix.

| Rule | Matched source | Suggested form |
| --- | --- | --- |
| [float_finiteness](../../internal/rule/lintrules/moonbitlang/float_finiteness.yaml) | `x.is_nan() \|\| x.is_inf()` or `!x.is_nan() && !x.is_inf()` | `!x.is_finite()` or `x.is_finite()`, respectively |
| [integer_min](../../internal/rule/lintrules/moonbitlang/integer_min.yaml) | `if x < best { best = x }` | `best = best.min(x)` |
| [integer_max](../../internal/rule/lintrules/moonbitlang/integer_max.yaml) | `if i - k > 1 { i - k } else { 1 }` | `(i - k).max(1)` |
| [iter_next_loop](../../internal/rule/lintrules/moonbitlang/iter_next_loop.yaml) | `while it.next() is Some(x)` | `for x in it`, keeping the loop body, `break` and `nobreak` |
| [direct_view_iteration](../../internal/rule/lintrules/moonbitlang/direct_view_iteration.yaml) | `for ch in text.iter()` | `for ch in text` |
| [slice_to_end](../../internal/rule/lintrules/moonbitlang/slice_to_end.yaml) | `s[i:s.length()]` or `s[:s.length()]` | `s[i:]` or `s[:]` |
| [builder_stream_interpolation](../../internal/rule/lintrules/moonbitlang/builder_stream_interpolation.yaml) | `buf.write_string("key=\{i}")` | `buf <+ "key=\{i}"` |

The numeric rules check that the installed standard library exports the replacement method. Both floating-point tests must read the same immutable `Float` or `Double` binding. Either predicate order works. The rule highlights just the two predicates in a longer expression and preserves assertions that compare `is_finite()` with its expanded definition. Both integer rules support an `if` that returns a value or updates a mutable local. Repeated operands can be integer literals, local bindings, or simple built-in addition and subtraction.

The iterator loop must pull from the same immutable `Iter` binding. The payload of `Some` can be a variable or `_`. Direct iteration and open-ended slicing apply to `String`, `StringView`, `Bytes` and `BytesView`. The slice and `length()` must use the same receiver, which may also be a field such as `self.text`. The start expression must be a simple, stable value.

Streaming interpolation applies to the standard `StringBuilder` implementation of `Logger::write_string`. Each hole must be a built-in scalar literal or an immutable local of a built-in scalar type. A hole such as `buf.to_string()` can see a partially written prefix during streaming.

## Optional review rules

These structural queries run with `scan --rules`. Each result identifies a change to review.

| Rule | Possible change | What to check |
| --- | --- | --- |
| [review_fixed_array_overwrite](review/fixed_array_overwrite.yaml) | Replace `FixedArray::make(n, seed)` and a full indexed fill with `FixedArray::makei`. | Evaluating `seed` may have effects even when `n == 0`. The fill must preserve the bounds and never read or expose the partially filled array. |
| [review_iter_then_predicate](review/iter_then_predicate.yaml) | Call the collection's `any` or `all` directly in place of `xs.iter().any(p)` or `xs.iter().all(p)`. | Check the collection's traversal semantics. If constructing the predicate appends to the array, the two forms can visit different elements. |
| [review_find_then_split](review/find_then_split.yaml) | Replace `find` and two slices around a delimiter with `split_once`. | Check the index has no other uses and the right slice skips exactly the delimiter. The query matches one of `=`, `;`, `/`, `:` or `,`. |

## Run

From the MoonGrep repository root, run the numeric examples, one slice rule, or the optional queries. The default output includes the matched source and its location.

```sh
moon run --target native . -- lint examples/core-month/numbers.mbt --target wasm
moon run --target native . -- scan examples/core-month/text.mbt --rule internal/rule/lintrules/moonbitlang/slice_to_end.yaml --target wasm
moon run --target native . -- scan examples/core-month/review_examples.mbt --rules examples/core-month/review
```
