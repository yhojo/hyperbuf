// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { test } from "node:test";
import { createModel, openBuffer, selectedWindow, visit } from "../src/model.ts";
import { virtualPath } from "../src/names.ts";
import { bufferNames, currentProjectRoot, defaultDirectory } from "../src/ui/directory.ts";
import type { AppContext } from "../src/ui/context.ts";

const HOME = "/Users/me";
const ctxOf = (model = createModel()): AppContext =>
  ({ model, host: { home: HOME } }) as unknown as AppContext;

test("基準のディレクトリ: バッファがなければ、ホスト", () => {
  assert.equal(defaultDirectory(ctxOf()), HOME);
});

test("基準のディレクトリ: ファイルの文書は、そのファイルのディレクトリ", () => {
  const model = createModel();
  visit(model, selectedWindow(model), "/Users/me/work/docs/a.md");
  assert.equal(defaultDirectory(ctxOf(model)), "/Users/me/work/docs");
});

test("基準のディレクトリ: 検索結果は起点。起点のない仮想バッファは、履歴を戻って直前のもの", () => {
  const model = createModel();
  const win = selectedWindow(model);
  visit(model, win, "/p/a.md");
  visit(model, win, virtualPath("search: x", "/p/sub"));
  assert.equal(defaultDirectory(ctxOf(model)), "/p/sub");
  visit(model, win, virtualPath("Help: keybindings"));
  assert.equal(defaultDirectory(ctxOf(model)), "/p/sub");
  const only = createModel();
  visit(only, selectedWindow(only), virtualPath("Help: keybindings"));
  assert.equal(defaultDirectory(ctxOf(only)), HOME);
});

test("バッファ名: 開いているバッファ全体で uniquify する", () => {
  const model = createModel();
  openBuffer(model, "/a/docs/README.md", "");
  openBuffer(model, "/a/emacs/README.md", "");
  openBuffer(model, "/a/docs/design.md", "");
  const names = bufferNames(ctxOf(model));
  assert.equal(names.get("/a/docs/README.md"), "README.md<docs>");
  assert.equal(names.get("/a/emacs/README.md"), "README.md<emacs>");
  assert.equal(names.get("/a/docs/design.md"), "design.md");
});

test("プロジェクト・ルート: ホストが求める。求められなければ(または失敗したら)、基準のディレクトリ自身", async () => {
  const model = createModel();
  visit(model, selectedWindow(model), "/p/repo/docs/a.md");
  const withHost = (projectRoot?: (dir: string) => Promise<string>): AppContext =>
    ({ model, host: { home: HOME, projectRoot } }) as unknown as AppContext;
  assert.equal(await currentProjectRoot(withHost(async () => "/p/repo")), "/p/repo");
  assert.equal(await currentProjectRoot(withHost()), "/p/repo/docs");
  assert.equal(
    await currentProjectRoot(
      withHost(async () => {
        throw new Error("x");
      }),
    ),
    "/p/repo/docs",
  );
});
