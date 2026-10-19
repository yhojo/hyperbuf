// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// docs/dev/integration-protocol.md の操作とエラーコードの表が、JSON Schema とずれていないかを確かめる。
// 操作やエラーコードを足す・消すときは、スキーマと文書の表を同時に直す。
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const doc = read("../../docs/dev/integration-protocol.md");
const request = JSON.parse(read("../schema/request.schema.json"));
const response = JSON.parse(read("../schema/response.schema.json"));

/** 見出し(`### 3.3 操作` など)の次の見出しまでにある表の、先頭の列の `名前`。 */
function firstColumn(heading) {
  const start = doc.indexOf(heading);
  assert.notEqual(start, -1, `${heading} が文書にない`);
  const rest = doc.slice(start + heading.length);
  const end = rest.search(/\n#{2,3} /);
  const section = end === -1 ? rest : rest.slice(0, end);
  return [...section.matchAll(/^\| `([a-z-]+)` +\|/gm)].map((m) => m[1]);
}

test("操作の表が、request.schema.json の op と一致する", () => {
  assert.deepEqual(firstColumn("### 3.3 操作").sort(), [...request.properties.op.enum].sort());
});

test("エラーコードの表が、response.schema.json の error.code と一致する", () => {
  const codes = response.oneOf[1].properties.error.properties.code.enum;
  assert.deepEqual(firstColumn("### 3.4 エラーコード").sort(), [...codes].sort());
});
