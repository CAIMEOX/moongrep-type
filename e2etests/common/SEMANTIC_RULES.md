# Semantic YAML options

Enabled semantic rules require an index before traversal begins.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep scan --rule ../../internal/rule/lintrules/moonbitlang/avoid_collect_for_count.yaml --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"semantic rules require --semantic-index"}
[2]
```

Index and view options use ordinary CLI validation and diagnostics.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep lint --semantic-index '' --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"--semantic-index must not be empty"}
[2]

$ moonx moonbit-community/moongrep lint --semantic-view wbtest --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"--semantic-view requires --semantic-index"}
[2]

$ moonx moonbit-community/moongrep lint --semantic-index missing.json --semantic-view unknown --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"--semantic-view must be normal, wbtest, or bbtest"}
[2]
```
