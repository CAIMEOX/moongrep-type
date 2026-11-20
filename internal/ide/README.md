# Semantic checks with moon ide

Run `moongrep lint <path>` to include the builtin semantic rules, or
`moongrep scan <path> --rule <yaml>` for a custom rule. An optional
`--target wasm` (or another backend) selects the compilation context.

The scanner matches enabled YAML shapes and regex guards on the original CST.
It drops declarations marked `#moongrep.skip`. A scan with no semantic
candidates ends here and needs neither a compiler check nor an IDE process.

When a candidate first needs semantic evidence, a scan session prepares the
owning MoonBit project. Syntax-only rejections can therefore skip this step. The
first `moon check --no-mbti` supplies the checked source inventory, including
generated inputs. A cached check validates those captured inputs. Files share
this preparation across packages in the same workspace. Independent nested
modules and standalone scripts get their own context. The selected backend,
normal or test file context, and `MOON_WORK` apply to every query.

Each rule asks for evidence while verifying one candidate. For example,
`xs.filter(p).length()` needs two `peek-def` calls for the methods and four
`hover` calls for the receiver, predicate, intermediate call, and final result.
A failed guard stops the remaining lookups. A check that proves exclusive
use of a local accumulator asks `find-references` about that binding. A check
for an already-consumed iterator may inspect its preceding statement.

The official CLI receives `--no-check --target <backend> --json`. Up to four
candidates are verified concurrently. Identical requests share the same
in-flight or completed result within the scan. A later scan starts fresh.
Use `--verbose` to see the number of distinct IDE queries.

Hover results must match exact source ranges, or the appropriate constructor,
field, or operator token. Positions use one-based Unicode scalar columns and
exclusive ends. The adapter parses MoonBit type syntax, preserves package names,
generic scopes, checked errors and async types, and distinguishes polymorphic
declarations from instantiated expression types. Definitions and re-exports
must resolve to one symbol. Derived bodies have no authored CST candidate.

Moving a tuple pattern needs only the tuple's arity. The IDE adapter parses the
type at the exact operand range for this check, including tuples whose element
types refer to transitive dependencies. Comparisons of payload types still use
their resolved nominal identities.

Before emitting semantic findings, the scanner rechecks input contents, source
membership, definition files, the backend selector and the compiler version.
Input failures produce a scan-input error. The rule reports only verified
findings. See the [examples](../../examples/semantic-rules/README.md).

## Measured scan costs

These are wall times for one native CLI run per corpus against the 2026-11-13
nightly with `--target wasm`. Each corpus contains the same three demonstration
files as the previous benchmark, with a fresh project build directory. The
current timings include candidate selection, project checks, IDE queries,
validation and lint output.

| Corpus | Previous export alone | Previous IDE queries | Current lint | Current IDE queries |
| --- | ---: | ---: | ---: | ---: |
| Collection rules, 18 semantic findings | 110.9 s | 839 | 22.5 s | 187 |
| Theorems, 40 semantic findings | 154.5 s | 1,174 | 33.3 s | 293 |

All rule IDs and source ranges matched the previous reports. Selecting just
`array_filter_count.yaml` on the theorem corpus took 2.9 s with the project
build cached. Its four candidates issued 24 queries. A scan with no candidates
issued zero queries and created no build directory.
