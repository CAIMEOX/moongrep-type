# Official IDE semantic export

The semantic index is always JSON. The optional JSON flag selects structured
error diagnostics. The backend uses the official MoonBit language service.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics --help | moonx cli/grep@0.2.0 'always JSON'
  --json             Write diagnostics as JSON Lines; the semantic index is always JSON.
```

A checked source with spaces and shell punctuation in its path is passed as a
single process argument. The command needs no separate reader or build script.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics '../testdata/ide-source with spaces;literal' --target wasm --json | moonx cli/jq@0.2.1 -c '[.schema_version,.provider,.position_encoding,(.facts | length > 0),(.symbols | length > 0),(.types | length > 0)]'
[1,"moon-ide","unicode-scalar",true,true,true]
```

Bare invocation prints the same help as an explicit help request.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics --help | moonx ../helpers/save.mbtx semantics-help

$ moonx moonbit-community/moongrep semantics | moonx ../helpers/save.mbtx semantics-no-args

$ moonx ../helpers/diff.mbtx semantics-help semantics-no-args
files are identical
```
