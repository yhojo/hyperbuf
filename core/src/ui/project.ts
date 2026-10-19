// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// プロジェクト単位のバッファ操作(`C-x p b` / `C-x p k`)。docs/buffer-model.md §6.8。
// プロジェクトは、バッファのパスから、そのつど求める(バッファにもフレームにも、保存しない)。

import { isVirtualPath } from "../model.ts";
import { parseVirtualPath } from "../names.ts";
import { dirname } from "../paths.ts";
import type { AppContext } from "./context.ts";
import { currentProjectRoot, projectRootOf } from "./directory.ts";

/** バッファのプロジェクト・ルート。基準のディレクトリを持たない仮想バッファ(Help など)は null。 */
export async function bufferProjectRoot(ctx: AppContext, path: string): Promise<string | null> {
  const dir = isVirtualPath(path) ? parseVirtualPath(path).dir : dirname(path);
  return dir ? projectRootOf(ctx, dir) : null;
}

/**
 * 現在のバッファと同じプロジェクト・ルートの、このフレームのバッファ(最近使った順)。
 * HyperBuf のバッファは、フレームごとに持つので、他のフレームのバッファは含まない。
 */
export async function projectBuffers(ctx: AppContext): Promise<{ root: string; paths: string[] }> {
  const root = await currentProjectRoot(ctx);
  const roots = await Promise.all(ctx.model.mru.map((path) => bufferProjectRoot(ctx, path)));
  return { root, paths: ctx.model.mru.filter((_, i) => roots[i] === root) };
}
