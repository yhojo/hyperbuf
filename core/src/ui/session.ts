// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Saving the session (written after a short wait on each change) and restoring it at startup.

import { createModel, killBuffer, removeWindow, windows } from "../model.ts";
import {
  parseSnapshot,
  referencedPaths,
  restoredSelection,
  restoreModel,
  takeSnapshot,
} from "../session.ts";
import type { SessionSelection } from "../session.ts";
import type { AppContext } from "./context.ts";
import { ensureBuffer } from "./navigation.ts";
import { captureSelection } from "./selection-state.ts";

/** Wait from a change to saving (do not write on every scroll). Use the same value as the table in docs/dev/session-restore.md §4. */
export const SAVE_DELAY_MS = 1000;

export interface SessionSaver {
  /** A change occurred. Wait a little, then save. */
  schedule(): void;
  /** Save right now (just before quitting). */
  flush(): Promise<void>;
}

export function createSessionSaver(ctx: AppContext): SessionSaver {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let last = "";
  const flush = async (): Promise<void> => {
    clearTimeout(timer);
    timer = undefined;
    const snapshot = takeSnapshot(ctx.model, captureSelection(ctx));
    const json = JSON.stringify(snapshot);
    if (!snapshot || json === last) return;
    last = json;
    try {
      await ctx.host.saveSession?.(snapshot);
    } catch {
      last = ""; // could not save, so write again next time
    }
  };
  return {
    schedule() {
      clearTimeout(timer);
      timer = setTimeout(() => void flush(), SAVE_DELAY_MS);
    },
    flush,
  };
}

/**
 * Restores the previous session. If restored, returns the selection to put back (null if none) (replaces the model
 * and has loaded the documents. The caller restores the selection after rendering).
 * Returns null (model unchanged) when there is no saved data, it is broken, or all documents are gone.
 */
export async function restoreSession(
  ctx: AppContext,
): Promise<{ selection: SessionSelection | null } | null> {
  const saved = await ctx.host.loadSession?.().catch(() => null);
  const snapshot = parseSnapshot(saved);
  if (!snapshot) return null;
  // Whether a document exists is known by trying to read it (those that could not be read are removed from the history below)
  const restored = restoreModel(snapshot, () => true);
  if (!restored) return null;
  Object.assign(ctx.model, restored);
  for (const path of referencedPaths(ctx.model)) {
    try {
      await ensureBuffer(ctx, path);
    } catch {
      killBuffer(ctx.model, path); // a document that became unreadable is removed from the history
    }
  }
  // Windows with no displayable document left are removed (collapsing the split). If none remain, a normal startup
  for (const win of windows(ctx.model)) {
    if (win.index < 0 && !removeWindow(ctx.model, win)) {
      Object.assign(ctx.model, createModel());
      return null;
    }
  }
  return { selection: restoredSelection(snapshot, ctx.model) };
}
