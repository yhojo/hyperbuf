// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Checks that the operations and error codes tables in docs/dev/integration-protocol.md match the JSON Schema.
// When adding or removing an operation or error code, fix the schema and the document tables together.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const doc = read("../../docs/dev/integration-protocol.md");
const request = JSON.parse(read("../schema/request.schema.json"));
const response = JSON.parse(read("../schema/response.schema.json"));

/** The `name` in the first column of the table between a heading (such as `### 3.3 Operations`) and the next heading. */
function firstColumn(heading) {
  const start = doc.indexOf(heading);
  assert.notEqual(start, -1, `${heading} が文書にない`);
  const rest = doc.slice(start + heading.length);
  const end = rest.search(/\n#{2,3} /);
  const section = end === -1 ? rest : rest.slice(0, end);
  return [...section.matchAll(/^\| `([a-z-]+)` +\|/gm)].map((m) => m[1]);
}

test("操作の表が、request.schema.json の op と一致する", () => {
  assert.deepEqual(
    firstColumn("### 3.3 Operations").sort(),
    [...request.properties.op.enum].sort(),
  );
});

test("エラーコードの表が、response.schema.json の error.code と一致する", () => {
  const codes = response.oneOf[1].properties.error.properties.code.enum;
  assert.deepEqual(firstColumn("### 3.4 Error codes").sort(), [...codes].sort());
});
