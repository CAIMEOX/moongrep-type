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
