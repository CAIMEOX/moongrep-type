# Map fusion CLI integration

The POC uses the same help and diagnostic handling as other moongrep commands.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep map-fusion --json
@STDOUT (empty)
@STDERR
{"type":"error","category":"usage","exit_code":2,"message":"missing map-fusion --index"}
[2]
```

Bare invocation prints the same help as an explicit help request.

```mooncram moonbit-community/moongrep
#cwd(.)
$ moonx moonbit-community/moongrep map-fusion --help | moonx ../helpers/save.mbtx fusion-help

$ moonx moonbit-community/moongrep map-fusion | moonx ../helpers/save.mbtx fusion-no-args

$ moonx ../helpers/diff.mbtx fusion-help fusion-no-args
files are identical
```
