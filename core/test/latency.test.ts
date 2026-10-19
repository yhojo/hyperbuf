// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { summarize } from "../src/ui/latency.ts";

test("computes median, p95 and max", () => {
  const s = summarize(Array.from({ length: 100 }, (_, i) => i + 1));
  assert.equal(s.n, 100);
  assert.equal(s.median, 51);
  assert.equal(s.p95, 96);
  assert.equal(s.max, 100);
});

test("does not fail when empty", () => {
  assert.deepEqual(summarize([]), { n: 0, median: 0, p95: 0, max: 0 });
});
