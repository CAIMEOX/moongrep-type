# Subcommands without arguments

## moongrep subcommands without arguments

The `docs` and `dump` subcommands print their help when invoked without
arguments. `scan` and `lint` instead treat an omitted scan root as the current
directory. `scan` uses its default rules directory, while `lint` enables
builtin rules automatically.

The docs subcommand uses the same no-argument help behavior.
Save each command's output to a separate file, then compare the files byte for
byte, printing a unified diff to stderr if they differ. Both helpers read
`E2E_TEMP` from the environment because mooncram does not expand environment
variables in command arguments.
A successful comparison prints `files are identical`.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep docs --help | moonx ../helpers/save.mbtx docs-help

$ moonx moonbit-community/moongrep docs | moonx ../helpers/save.mbtx docs-no-args

$ moonx ../helpers/diff.mbtx docs-help docs-no-args
files are identical
```

The dump subcommand also prints help instead of attempting to parse an empty
input.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep dump --help | moonx ../helpers/save.mbtx dump-help

$ moonx moonbit-community/moongrep dump | moonx ../helpers/save.mbtx dump-no-args

$ moonx ../helpers/diff.mbtx dump-help dump-no-args
files are identical
```

Running bare `lint` from a fixture directory produces the same output as an
explicit current-directory lint target.

```mooncram moonbit-community/moongrep
#cwd(../testdata/builtin-rules)
$ moonx moonbit-community/moongrep lint | moonx ../../helpers/save.mbtx lint-no-args

$ moonx moonbit-community/moongrep lint . | moonx ../../helpers/save.mbtx lint-dot

$ moonx ../../helpers/diff.mbtx lint-no-args lint-dot
files are identical
```
