import assert from "node:assert/strict";
import test from "node:test";
import { version } from "../src/index.ts";
import type { HyperbufHost } from "../src/index.ts";

test("バージョンが取れる", () => {
  assert.match(version, /^\d+\.\d+\.\d+$/);
});

test("HyperbufHost の最小の実装が型検査を通る", async () => {
  const host: HyperbufHost = {
    name: "test",
    listFiles: async () => ["index.md"],
    readFile: async () => "# test",
    onFileChanged: () => {},
  };
  assert.deepEqual(await host.listFiles(), ["index.md"]);
});
