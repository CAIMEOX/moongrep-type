# Docs command

## Embedded CLI document headings

The named CLI document prints the embedded source.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep docs CLISpec | moonx cli/grep@0.2.0 -E '^# Command-Line Interface Specification$|^## (`scan` and `lint`|JSON Lines Output|Diagnostics and Exit Status)$'
# Command-Line Interface Specification
## `scan` and `lint`
## JSON Lines Output
## Diagnostics and Exit Status
```

The embedded rule specification stays synchronized with its source.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep docs RuleSpec | moonx cli/cmp@0.2.0 ../../internal/docs/RuleSpec.md -
```
