# Semantic rule guide

[中文](README_CN.md)

`moongrep lint <path>` includes 63 semantic rules. To run one rule, pass its YAML file to `moongrep scan <path> --rule <file>`. The default report shows the rule ID, suggestion and matched source.

| Rule guide | Examples |
| --- | --- |
| [Arrays and iterators](../../examples/semantic-rules/README.md) | Build comprehensions, count without collecting, and spot a second traversal of a consumed iterator. |
| [Collections, Option and Result](../../examples/semantic-theorems/README.md) | Combine filters with terminal operations, compose callbacks, and simplify constructor and identity operations. |
| [Standard-library methods](../../examples/stdlib-patterns/README.md) | Recognize membership and emptiness checks, handwritten Option and Result operations, short-circuit loops and ASCII predicates. |
| [Loop patterns and collection literals](../../examples/syntax-adoption/README.md) | Unpack pairs in loop headers, combine scalar alternatives, use iterator literals, and build arrays with conditional spreads. |
| [Numeric, iteration and text rules](../../examples/core-month/README.md) | Use numeric predicates and extrema, iterate directly, omit a slice end, and stream string interpolation. Includes optional review queries. |

A YAML shape and its guards select candidates in the source. Each semantic check requests the types, definitions or binding references it needs at that location. A custom YAML can narrow a builtin check. [YAML rule specification](../docs/RuleSpec.md#semantic-rules) · [IDE lookup behavior](../ide/README.md)

## Array map fusion

`array_map_fusion` matches two consecutive standard `Array::map` calls with one positional callback each. For `xs.map(g).map(f)`, the receiver and results must have types `Array[A]`, `Array[B]` and `Array[C]`. The callbacks must have compatible synchronous, non-raising types `A → B` and `B → C`.

The suggested composition is `xs.map(x => f(g(x)))`. With pure, terminating callbacks, it produces the same elements in a single traversal. If the callbacks have effects, the order matters. The original finishes every call to `g` before starting `f`. The fused form calls `f` after each element's `g`. Callback factories must also retain their original evaluation time and count.

To see the type flow and reasons for skipped chains, run the dedicated report from the repository root. Each accepted candidate has status `requires_review`. Add `--json` for structured output.

```sh
moon run --target native . -- map-fusion tools/map-fusion/fixture
```
