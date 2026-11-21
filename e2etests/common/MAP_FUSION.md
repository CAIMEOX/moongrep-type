# Map fusion CLI integration

The `map-fusion` command reports the matched and skipped chains for each file.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep map-fusion '../testdata/ide-source with spaces;literal' --target wasm --json | moonx cli/jq@0.2.1 -c '[.schema_version,(.files[0].report.candidates | length),(.files[0].report.skipped | length)]'
[2,1,0]
```

Bare invocation prints the same help as an explicit help request.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep map-fusion --help | moonx ../helpers/save.mbtx fusion-help

$ moonx moonbit-community/moongrep map-fusion | moonx ../helpers/save.mbtx fusion-no-args

$ moonx ../helpers/diff.mbtx fusion-help fusion-no-args
files are identical
```
