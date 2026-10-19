// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { version } from "../src/index.ts";
import type { HyperbufHost } from "../src/index.ts";

test("the version can be obtained", () => {
  assert.match(version, /^\d+\.\d+\.\d+$/);
});

test("minimal HyperbufHost implementation passes the type check", async () => {
  const host: HyperbufHost = {
    name: "test",
    home: "/home/test",
    listDirectory: async () => ({ entries: [{ name: "index.md", dir: false }], truncated: false }),
    listTree: async () => ({ files: ["index.md"], truncated: false }),
    readFile: async () => "# test",
    onFileChanged: () => {},
  };
  assert.deepEqual((await host.listDirectory("/home/test")).entries, [
    { name: "index.md", dir: false },
  ]);
});
