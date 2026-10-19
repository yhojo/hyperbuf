// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Base directory (Emacs `default-directory`) and buffer names. docs/dev/buffer-model.md §3, §4.

import { currentEntry, isVirtualPath, selectedWindow } from "../model.ts";
import { parseVirtualPath, uniquifyNames } from "../names.ts";
import { dirname } from "../paths.ts";
import type { AppContext } from "./context.ts";

/**
 * Base directory. Uses that of the current buffer of the selected window.
 * - File document: the file's directory
 * - Virtual buffer (search results): the search origin
 * - Virtual buffer without an origin (Help etc.): that of the nearest earlier buffer in the history that has one
 * - No buffer: the host (`~`)
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

/** Project root of `dir`. If the host cannot determine it, `dir` itself (`default-directory`). */
export async function projectRootOf(ctx: AppContext, dir: string): Promise<string> {
  try {
    return (await ctx.host.projectRoot?.(dir)) ?? dir;
  } catch {
    return dir;
  }
}

/** Project root of the current buffer (`C-x p ...`; derived from the buffer, not the frame). */
export function currentProjectRoot(ctx: AppContext): Promise<string> {
  return projectRootOf(ctx, defaultDirectory(ctx));
}

/** Current name of the current buffer (uniquified). */
export function bufferNames(ctx: AppContext): Map<string, string> {
  return uniquifyNames([...ctx.model.buffers.keys()], ctx.host.home);
}

/** Name of the buffer shown by the current window (empty if none). */
export function currentBufferName(ctx: AppContext): string {
  const entry = currentEntry(selectedWindow(ctx.model));
  return entry ? (bufferNames(ctx).get(entry.path) ?? entry.path) : "";
}
