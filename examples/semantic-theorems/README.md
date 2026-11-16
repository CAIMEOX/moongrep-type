# Semantic theorems

These 20 checks recognize instances of standard-library laws with verified
type, symbol, and evaluation-order conditions. They use the existing YAML rule
loader, `scan` / `lint`, source highlighting, and diagnostics. They report
suggestions; they do not rewrite code or produce machine-checked proofs.

## Run

From the repository root, with a toolchain compatible with upstream dependencies:

```sh
for file in collections option_fusion identities; do
  moon run --target native . -- lint "examples/semantic-theorems/$file.mbt"
done
```

This prints **40 theorem findings** across the three source files, including
generic types, checked errors, factories where permitted, and Unicode positions.
Ordinary lint findings may also appear. The `no_*` and `identity_negative_*`
functions demonstrate rejected cases. The collection examples also reject eager
Array flattening, removal of mapping effects, and full-traversal to short-circuit
changes. The `is_some` / `is_none` examples intentionally use deprecated methods
so checking the examples may produce compiler deprecation warnings.

Set `NO_COLOR=1` for plain terminal output; add `--json` for JSON Lines. The
`*_test.mbt` files exercise behavior. The IDE selects each file's context; the
command above scans only the demonstration files.

## Catalogue

Each row is a separate check and YAML rule. Builtin rule IDs use
`moonbitlang/` followed by the check name with hyphens replaced by underscores.
For example, disable the first with `--disable moonbitlang/array_filter_count`.

| `semantic.check` | Law / suggested form |
| --- | --- |
| `array-filter-count` | `a.filter(p).length()` → `a.count_if(p)` |
| `iter-filter-count` | `it.filter(p).count()` → `it.count_if(p)` |
| `iter-filter-next` | `it.filter(p).next()` → `it.find_first(p)` |
| `iter-find-first-exists` | `it.find_first(p) is Some(_)` → `it.any(p)`; `is None` → `!it.any(p)`; also supports `.is_some()` / `.is_none()` |
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

The official IDE supplies source-expression types directly. No generated
conversion nodes are traversed. The backend parses language type syntax and
keeps generic parameter scopes, errors, and async status. A generic declaration
scheme is marked `polymorphic` and is not treated as an instantiated value type.
Missing or unsupported information stays unavailable instead of being guessed.

Derived implementation bodies are absent from the authored CST and are not
queried. Handwritten impls remain eligible.

The count laws unfold to the same full traversal and predicate call sequence.
The search laws stop at the same successful pull, or at the same exhaustion
pull. Iter map/flatten and flat_map create the same nested lazy traversal. These
rules preserve evaluation of receiver and callback expressions once, in order,
so callback factories are allowed. Checked errors are allowed when supported
by both standard-library operations; an effect-free function type is never
treated as a purity proof.

Iterator presence tests accept only the complete builtin Option patterns `None`
and `Some(_)`, including qualified forms such as `Option::Some(_)`. The compiler
constructor identity decides which Option is meant. `Some(value)`, literal or
nested payload patterns, aliases, and alternatives are rejected: they can bind
a value or test more than presence. The suggested `any` / `!any` preserves the
predicate's effects, checked errors, and the iterator's remaining position.

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

The laws use the installed standard library's Array, Iter, Option, and Result
operations. Evidence comes from the official IDE protocol, not a compiler-private
layout. See the [IDE backend contract](../../internal/ide/README.md).

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
moon test tests/ide --target native
```

The runtime tests compare values, mutation traces, error paths, receiver/callback
factory evaluation, iterator pulls and remaining position, and mutable payload
aliases. The native integration tests cover all 20 checks through builtin YAML,
Unicode positions, negative cases, file and test contexts, stale sources,
derives, handwritten impls, and implicit conversions. Unit and CLI tests cover
custom YAML, disables, and missing evidence. Both analysis entrypoints consume
the same authored evidence.
