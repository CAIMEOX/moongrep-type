# Windows junction traversal

## Scan-directory cycle

The setup script prepares a directory junction back to the scan root.
Source traversal follows the junction, reports the cycle as
skipped, and scans the source only once.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --verbose --pattern 'target()' fs-walk-scan.tmp | moonx cli/grep@0.2.0 -x 'rule: target()' | moonx cli/wc@0.2.0 -l
1
```

The same traversal exposes its entering, skipping, and file events on stderr.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --verbose --pattern 'target()' fs-walk-scan.tmp
@STDOUT (ignore)
@STDERR
moongrep scan: loaded rule target()
moongrep scan: entering fs-walk-scan.tmp
moongrep scan: skipping fs-walk-scan.tmp\again
moongrep scan: file fs-walk-scan.tmp\hit.mbt
```

## Rule-directory cycle

The setup script also prepares a rule directory with a junction back to itself.
Rule discovery follows the junction, stops at the already visited directory,
and reports one finding with no stderr output.

```mooncram moonbit-community/moongrep
$ moonx moonbit-community/moongrep scan --rules fs-walk-rules.tmp ../testdata/symlink/scan-dir-target/hit.mbt | moonx cli/grep@0.2.0 -x 'rule: example' | moonx cli/wc@0.2.0 -l
@STDOUT
1
@STDERR (empty)
```
