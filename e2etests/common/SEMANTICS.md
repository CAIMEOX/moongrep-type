# Semantic index command

The semantic index is always JSON. The optional JSON flag also selects structured
diagnostics. Reader arguments are executable paths, not shell commands.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics --help | moonx cli/grep@0.2.0 'always JSON'
  --json             Write diagnostics as JSON Lines; the semantic index is always JSON.
```

An explicitly empty reader selection is rejected before launching a process.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics . --reader '' --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"missing semantic reader","help":"build tools/moonc-reader for the active compiler, then pass --reader or set MOONGREP_SEMANTIC_READER"}
[2]
```

Bare invocation prints the same help as an explicit help request.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics --help | moonx ../helpers/save.mbtx semantics-help

$ moonx moonbit-community/moongrep semantics | moonx ../helpers/save.mbtx semantics-no-args

$ moonx ../helpers/diff.mbtx semantics-help semantics-no-args
files are identical
```
