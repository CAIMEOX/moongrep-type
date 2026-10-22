# External semantic reader

The test reader records argv so a path with spaces and shell metacharacters
must arrive as one unchanged argument. Extra index fields survive validation.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics 'project with spaces;literal' --reader ../testdata/semantics/mock-reader.mjs --target native --json | moonx cli/jq@0.2.1 -c '[.schema_version,.position_encoding,.test_reader_arguments]'
@STDOUT
[1,"unicode-scalar",["--project","project with spaces;literal","--target","native"]]
@STDERR (empty)
```

Nonzero reader status is fatal even if stdout contains JSON.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics failure --reader ../testdata/semantics/mock-reader.mjs --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"scan_input","exit_code":6,"message":"could not load semantic index","source":"../testdata/semantics/mock-reader.mjs","reason":"reader exited with status 9: incompatible compiler artifact","help":"check the project and use a reader built for the active moonc version"}
[6]
```

Malformed successful output is rejected before any index is printed.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep semantics invalid --reader ../testdata/semantics/mock-reader.mjs --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"scan_input","exit_code":6,"message":"could not load semantic index","source":"invalid","reason":"invalid reader output: invalid semantic index: invalid JSON","help":"check the project and use a reader built for the active moonc version"}
[6]
```
