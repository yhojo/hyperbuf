// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Project-scoped buffer operations (`C-x p b` / `C-x p k`). docs/dev/buffer-model.md §6.8.
// The project is derived from buffer paths each time (not stored on buffers or frames).

import { isVirtualPath } from "../model.ts";
import { parseVirtualPath } from "../names.ts";
import { dirname } from "../paths.ts";
import type { AppContext } from "./context.ts";
import { currentProjectRoot, projectRootOf } from "./directory.ts";

/** Project root of a buffer. null for virtual buffers without a base directory (Help etc.). */
export async function bufferProjectRoot(ctx: AppContext, path: string): Promise<string | null> {
  const dir = isVirtualPath(path) ? parseVirtualPath(path).dir : dirname(path);
  return dir ? projectRootOf(ctx, dir) : null;
}

/**
 * Buffers of this frame that share the current buffer's project root (most recently used first).
 * HyperBuf buffers are per frame, so buffers of other frames are not included.
 */
export async function projectBuffers(ctx: AppContext): Promise<{ root: string; paths: string[] }> {
  const root = await currentProjectRoot(ctx);
  const roots = await Promise.all(ctx.model.mru.map((path) => bufferProjectRoot(ctx, path)));
  return { root, paths: ctx.model.mru.filter((_, i) => roots[i] === root) };
}
