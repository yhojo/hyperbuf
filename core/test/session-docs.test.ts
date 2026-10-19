// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import * as session from "../src/session.ts";
import * as sessionUi from "../src/ui/session.ts";

// Checks that the limits table in docs/dev/session-restore.md §4 matches the values in the code.
// (The Swift-side `maxBytes` / `maxFrames` are not checked here; a comment at their definition asks to keep them in sync)

const doc = readFileSync(new URL("../../docs/dev/session-restore.md", import.meta.url), "utf8");

const rows = new Map<string, number>();
for (const m of doc.matchAll(/^\|\s*`([A-Za-z_]+)`\s*\|\s*([0-9]+)\s*\|/gm)) {
  rows.set(m[1] as string, Number(m[2]));
}

const values: Record<string, number> = {
  MAX_HISTORY: session.MAX_HISTORY,
  MAX_MRU: session.MAX_MRU,
  MAX_WINDOWS: session.MAX_WINDOWS,
  MAX_DEPTH: session.MAX_DEPTH,
  MAX_STRING: session.MAX_STRING,
  MAX_SELECTION: session.MAX_SELECTION,
  SAVE_DELAY_MS: sessionUi.SAVE_DELAY_MS,
};

for (const [name, value] of Object.entries(values)) {
  test(`session-restore.md の制限値 ${name} が、コードと一致する`, () => {
    assert.equal(rows.get(name), value, `docs/dev/session-restore.md §4 の ${name} を確かめる`);
  });
}
