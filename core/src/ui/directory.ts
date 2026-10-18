// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 基準のディレクトリ(Emacs の `default-directory`)と、バッファの名前。docs/project-model.md §2・§9。

import { currentEntry, isVirtualPath, selectedWindow } from "../model.ts";
import { parseVirtualPath, uniquifyNames } from "../names.ts";
import { dirname } from "../paths.ts";
import type { AppContext } from "./context.ts";

/**
 * 基準のディレクトリ。選択中の window の、いまのバッファのものを使う。
 *  - ファイルの文書: そのファイルのディレクトリ
 *  - 仮想バッファ(検索結果): 検索の起点
 *  - 起点のない仮想バッファ(Help など): 履歴を戻って、直前の、基準を持つバッファのもの
 *  - バッファがない: ホスト(`~`)
 */
export function defaultDirectory(ctx: AppContext): string {
  const win = selectedWindow(ctx.model);
  for (let i = win.index; i >= 0; i--) {
    const path = win.history[i]?.path;
    if (!path) continue;
    if (!isVirtualPath(path)) return dirname(path);
    const dir = parseVirtualPath(path).dir;
    if (dir) return dir;
  }
  return ctx.host.home;
}

/** `dir` のプロジェクト・ルート。ホストが求められなければ、`dir` 自身(`default-directory`)。 */
export async function projectRootOf(ctx: AppContext, dir: string): Promise<string> {
  try {
    return (await ctx.host.projectRoot?.(dir)) ?? dir;
  } catch {
    return dir;
  }
}

/** 現在のバッファのプロジェクト・ルート(`C-x p ...`。フレームではなく、バッファから求める)。 */
export function currentProjectRoot(ctx: AppContext): Promise<string> {
  return projectRootOf(ctx, defaultDirectory(ctx));
}

/** 現在のバッファの現在の名前(uniquify 済み)。 */
export function bufferNames(ctx: AppContext): Map<string, string> {
  return uniquifyNames([...ctx.model.buffers.keys()], ctx.host.home);
}

/** 現在の window が表示しているバッファの名前(なければ空)。 */
export function currentBufferName(ctx: AppContext): string {
  const entry = currentEntry(selectedWindow(ctx.model));
  return entry ? (bufferNames(ctx).get(entry.path) ?? entry.path) : "";
}
