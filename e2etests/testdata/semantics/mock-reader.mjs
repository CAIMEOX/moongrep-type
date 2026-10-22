#!/usr/bin/env node
import { execFileSync } from "node:child_process";

const args = process.argv.slice(2);
if (args[0] !== "--project") throw new Error("missing --project");
if (args[1] === "failure") {
  process.stderr.write("incompatible compiler artifact\n");
  process.stdout.write("{}\n");
  process.exit(9);
}
if (args[1] === "invalid") {
  process.stdout.write("not JSON\n");
  process.exit(0);
}
process.stdout.write(JSON.stringify({
  schema_version: 1,
  compiler_version: execFileSync("moonc", ["-v"], { encoding: "utf8" }).trim(),
  position_encoding: "unicode-scalar",
  sources: [], types: [], symbols: [], facts: [],
  test_reader_arguments: args,
}) + "\n");
