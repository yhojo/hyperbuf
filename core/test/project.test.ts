// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { test } from "node:test";
import { createModel, openBuffer, selectedWindow, visit } from "../src/model.ts";
import { virtualPath } from "../src/names.ts";
import type { AppContext } from "../src/ui/context.ts";
import { bufferProjectRoot, projectBuffers } from "../src/ui/project.ts";

const HOME = "/Users/me";
/** `/w/a` and `/w/b` are project roots; anything else is its own directory. */
const projectRoot = async (dir: string): Promise<string> => {
  for (const root of ["/w/a", "/w/b"]) if (dir === root || dir.startsWith(`${root}/`)) return root;
  return dir;
};
const ctxOf = (model = createModel()): AppContext =>
  ({ model, host: { home: HOME, projectRoot } }) as unknown as AppContext;

test("バッファのルート: ファイルは親のディレクトリから、仮想バッファは起点から、起点がなければ null", async () => {
  const ctx = ctxOf();
  assert.equal(await bufferProjectRoot(ctx, "/w/a/docs/x.md"), "/w/a");
  assert.equal(await bufferProjectRoot(ctx, virtualPath("search: q", "/w/b/sub")), "/w/b");
  assert.equal(await bufferProjectRoot(ctx, virtualPath("Help: keybindings")), null);
  assert.equal(await bufferProjectRoot(ctx, "/tmp/loose/y.md"), "/tmp/loose");
});

test("プロジェクトのバッファ: 現在のバッファと同じルートのものだけ(最近使った順)", async () => {
  const model = createModel();
  for (const path of ["/w/a/1.md", "/w/b/2.md", "/w/a/docs/3.md", "/other/4.md"]) {
    openBuffer(model, path, "");
    visit(model, selectedWindow(model), path);
  }
  visit(model, selectedWindow(model), "/w/a/1.md");
  const { root, paths } = await projectBuffers(ctxOf(model));
  assert.equal(root, "/w/a");
  assert.deepEqual([...paths].sort(), ["/w/a/1.md", "/w/a/docs/3.md"]);
  for (const path of paths) assert.ok(model.mru.includes(path));
});

test("プロジェクトのバッファ: ルートのない仮想バッファは、履歴を戻った先のルートになる", async () => {
  const model = createModel();
  openBuffer(model, "/w/b/1.md", "");
  visit(model, selectedWindow(model), "/w/b/1.md");
  const help = virtualPath("Help: keybindings");
  openBuffer(model, help, "");
  visit(model, selectedWindow(model), help);
  const { root, paths } = await projectBuffers(ctxOf(model));
  assert.equal(root, "/w/b");
  assert.deepEqual(paths, ["/w/b/1.md"]);
});
