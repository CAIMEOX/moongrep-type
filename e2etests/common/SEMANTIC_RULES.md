# Semantic YAML rules

A custom semantic rule can scan an unrelated source containing unresolved names.
Its shape has no candidates, so compilation is unnecessary.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep scan ../testdata/prefilter-impl/hits.mbt --rule ../../internal/rule/lintrules/moonbitlang/array_filter_count.yaml --json
@STDOUT (empty)
@STDERR (empty)
```

Lint checks the matched chains in a module whose directory contains shell punctuation.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep lint '../testdata/ide-source with spaces;literal' --target wasm --json | moonx cli/jq@0.2.1 -c 'select(.rule_id == "moonbitlang/array_map_fusion") | [.rule_id,.matched_source]'
["moonbitlang/array_map_fusion","xs.map(x => x + 1).map(x => x * 2)"]
```

The optional project backend must be a single supported target.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep lint --target=all --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"--target must select one of wasm, wasm-gc, js, native, or llvm"}
[2]
```

Syntax-adoption findings point to the destructuring statement and the complete
classifier expression.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep lint ../../examples/syntax-adoption/tuples.mbt --target wasm --json | moonx cli/jq@0.2.1 -c -s 'map(select(.rule_id == "moonbitlang/loop_tuple_unpack") | .matched_source)'
["let (x, y) = pair","let (enabled, n) = pair","let (x, _) = key"]
$ moonx moonbit-community/moongrep scan ../../examples/syntax-adoption/classifiers.mbt --rule ../../internal/rule/lintrules/moonbitlang/repeated_classifier.yaml --target wasm --json | moonx cli/jq@0.2.1 -r 'select(.matched_source | startswith("code")) | .matched_source'
code == -1 || code is (0 | 2) || code == 3
```

The iterator literal builtin can also be disabled for code that exercises the
constructors themselves.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep lint ../../examples/syntax-adoption/iterators.mbt --target wasm --disable moonbitlang/iterator_literal --json
@STDOUT (empty)
@STDERR (empty)
```
