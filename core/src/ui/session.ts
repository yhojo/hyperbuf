// セッションの保存(変更のたびに、少し待ってから書く)と、起動時の復元。

import { createModel, killBuffer, windows } from "../model.ts";
import { parseSnapshot, referencedPaths, restoreModel, takeSnapshot } from "../session.ts";
import type { AppContext } from "./context.ts";
import { ensureBuffer } from "./navigation.ts";

/** 変更から保存までの待ち(スクロールのたびに書かない)。 */
const SAVE_DELAY_MS = 1000;

export interface SessionSaver {
  /** 変更があった。少し待って、保存する。 */
  schedule(): void;
  /** いますぐ保存する(終了の直前)。 */
  flush(): Promise<void>;
}

export function createSessionSaver(ctx: AppContext): SessionSaver {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let last = "";
  const flush = async (): Promise<void> => {
    clearTimeout(timer);
    timer = undefined;
    const snapshot = takeSnapshot(ctx.model);
    const json = JSON.stringify(snapshot);
    if (!snapshot || json === last) return;
    last = json;
    try {
      await ctx.host.saveSession?.(snapshot);
    } catch {
      last = ""; // 保存できなかったので、次の機会に、もう一度書く
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
 * 前回のセッションを復元する。復元できたら true(model を置き換え、文書を読み込んである)。
 * 保存がない・壊れている・文書がすべてなくなった、のときは false(model は、そのまま)。
 */
export async function restoreSession(ctx: AppContext, files: readonly string[]): Promise<boolean> {
  const saved = await ctx.host.loadSession?.().catch(() => null);
  const snapshot = parseSnapshot(saved);
  if (!snapshot) return false;
  const restored = restoreModel(snapshot, new Set(files));
  if (!restored) return false;
  Object.assign(ctx.model, restored);
  for (const path of referencedPaths(ctx.model)) {
    try {
      await ensureBuffer(ctx, path);
    } catch {
      killBuffer(ctx.model, path); // 読めなくなった文書は、履歴から外す
    }
  }
  if (windows(ctx.model).some((w) => w.index < 0)) {
    Object.assign(ctx.model, createModel()); // 表示できる文書が残らなかった
    return false;
  }
  return true;
}
