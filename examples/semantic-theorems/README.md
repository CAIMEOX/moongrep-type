# Semantic theorems

These 20 checks recognize instances of standard-library laws with verified
type, symbol, and evaluation-order conditions. They use the existing YAML rule
loader, `scan` / `lint`, source highlighting, and diagnostics. They report
suggestions; they do not rewrite code or produce machine-checked proofs.

## Run

From the repository root, with the supported nightly installed:

```sh
node scripts/build-moonc-reader.mjs
_build/semantic-reader/moonc-reader --project examples/semantic-theorems > /tmp/theorems-index.json
for file in collections option_fusion identities; do
  moon run . -- lint "examples/semantic-theorems/$file.mbt" --semantic-index /tmp/theorems-index.json
done
```

This prints **33 theorem findings** across the three source files, including
generic types, checked errors, factories where permitted, and Unicode positions.
Ordinary lint findings may also appear. The `no_*` and `identity_negative_*`
functions demonstrate rejected cases. The collection examples also reject eager
Array flattening, removal of mapping effects, and full-traversal to short-circuit
changes. The `is_some` / `is_none` examples intentionally use deprecated methods
so the reader may print compiler deprecation warnings when building the index.

Set `NO_COLOR=1` for plain terminal output; add `--json` for JSON Lines. The
`*_test.mbt` files exercise behavior and belong to the `bbtest` view, so the
command above scans only the demonstration files in the default `normal` view.
Regenerate the index after editing any source.

## Catalogue

Each row is a separate check and YAML rule. Builtin rule IDs use
`moonbitlang/` followed by the check name with hyphens replaced by underscores.
For example, disable the first with `--disable moonbitlang/array_filter_count`.

| `semantic.check` | Law / suggested form |
| --- | --- |
| `array-filter-count` | `a.filter(p).length()` → `a.count_if(p)` |
| `iter-filter-count` | `it.filter(p).count()` → `it.count_if(p)` |
| `iter-filter-next` | `it.filter(p).next()` → `it.find_first(p)` |
| `iter-find-first-exists` | `it.find_first(p).is_some()` → `it.any(p)`; `is_none()` → `!it.any(p)` |
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

## Evidence and side conditions

Every call must resolve to the expected standard-library method or constructor.
The checks compare normalized types, including generic parameter owners and
Result error types, rather than type IDs or printed names. Unknown, missing, or
ambiguous facts produce diagnostics instead of definite findings. Method syntax
must have the expected positional arguments; cascade calls and extra arguments
do not qualify. All callbacks must be synchronous.

The count laws unfold to the same full traversal and predicate call sequence.
The search laws stop at the same successful pull, or at the same exhaustion
pull. Iter map/flatten and flat_map create the same nested lazy traversal. These
rules preserve evaluation of receiver and callback expressions once, in order,
so callback factories are allowed. Checked errors are allowed when supported
by both standard-library operations; an effect-free function type is never
treated as a purity proof.

Option/Result map fusion operates on at most one payload. In a mapped branch,
both forms call `f` then `g`; the other branch skips both. Option filter fusion
calls `q` only after `p` succeeds. Lazy default fusion calls exactly the selected
transform or fallback. For these fusions, callback expressions must be immutable
function bindings or literal lambdas without captures of outer mutable bindings.
Factories and reads of mutable function bindings are rejected because moving
their evaluation can change behavior. Mutation through a stable Array/Ref
binding is allowed; callback effects and checked errors retain their order.
Keep the original callbacks as functions when composing them, so explicit
`return` keeps its original function boundary. Generated names must be fresh.

Bind/map removes only the outer standard Some/Ok wrapper from a literal lambda.
The callback scope and effects remain. A return inside the payload targeting
that callback is rejected; returns inside nested functions are separate.
If the original lambda has an explicit return type, adjust it when removing
the wrapper. The right-unit checks own `x => Some(x)` / `x => Ok(x)` to avoid
duplicate bind/map hints. Result map/flatten verifies both error parameters
agree and can keep a callback factory in its original argument position.

Identity checks compare actual binder symbols. Same-spelled or same-typed
variables are insufficient. The callback must contain only the identity body;
extra statements cannot be discarded. Constructor elimination requires an
empty unwrap argument list, preserves payload evaluation once, and retains
references to mutable payloads. None of these identities applies to Array
copying operations. As in the standard library, allocation failures and results
of `physical_equal` are outside these laws; ordinary aliasing, iterator state,
callback effects, exceptions, and termination behavior are not ignored.

The contracts are pinned to `moonc v0.10.14+7080b3792-nightly (2026-10-10)` and
its installed core definitions (`builtin/array.mbt`, `iterator.mbt`,
`option.mbt`, and `result.mbt`). The reader uses no compiler source or library.

## YAML and tests

All 20 checks can be selected by user YAML through the normal `--rule` option:

```yaml
id: compact_option_map
description: Compose these Option callbacks in one map.
semantic:
  check: option-map-fusion
  patterns:
    - shape: $(value:id).map($(first:exp)).map($(second:exp))
      guard:
        $value: '^value$'
```

YAML may narrow candidates, change descriptions, or disable rules. It cannot
waive semantic evidence or declare a callback pure. See the [rule specification](../../internal/docs/RuleSpec.md).

```sh
moon -C examples/semantic-theorems test --target wasm
moon -C examples/semantic-theorems test --target native
node tools/semantic-rules/theorems.mjs
```

The runtime tests compare values, mutation traces, error paths, receiver/callback
factory evaluation, iterator pulls and remaining position, and mutable payload
aliases. The integration test covers all 20 checks through builtin and custom
YAML, exact source slices, Unicode columns, negative cases, disables, selected
normal/wbtest/bbtest views, missing evidence, and stale sources.
