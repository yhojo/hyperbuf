// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { firstChangedLine } from "../src/diff.ts";

test("firstChangedLine: 最初に違う行を返す", () => {
  assert.equal(firstChangedLine("a\nb\nc", "a\nb\nc"), null);
  assert.equal(firstChangedLine("a\nb\nc", "a\nX\nc"), 2);
  assert.equal(firstChangedLine("a\nb", "a\nb\nc"), 3);
  assert.equal(firstChangedLine("a\nb\nc", "a\nb"), 3);
  assert.equal(firstChangedLine("a", "Z\na"), 1);
});
