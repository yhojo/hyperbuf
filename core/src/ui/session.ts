// セッションの保存(変更のたびに、少し待ってから書く)と、起動時の復元。

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
    const snapshot = takeSnapshot(ctx.model, captureSelection(ctx));
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
 * 前回のセッションを復元する。復元できたら、戻す選択範囲(なければ null)を返す(model を置き換え、
 * 文書を読み込んである。選択範囲は、描画のあとに、呼び出し側が戻す)。
 * 保存がない・壊れている・文書がすべてなくなった、のときは null(model は、そのまま)。
 */
export async function restoreSession(
  ctx: AppContext,
): Promise<{ selection: SessionSelection | null } | null> {
  const saved = await ctx.host.loadSession?.().catch(() => null);
  const snapshot = parseSnapshot(saved);
  if (!snapshot) return null;
  // 文書が存在するかは、読んでみて分かる(読めなかったものは、下で履歴から外す)
  const restored = restoreModel(snapshot, () => true);
  if (!restored) return null;
  Object.assign(ctx.model, restored);
  for (const path of referencedPaths(ctx.model)) {
    try {
      await ensureBuffer(ctx, path);
    } catch {
      killBuffer(ctx.model, path); // 読めなくなった文書は、履歴から外す
    }
  }
  // 表示できる文書が残らなかった window は、取り除く(分割をたたむ)。すべてなくなれば、通常の起動
  for (const win of windows(ctx.model)) {
    if (win.index < 0 && !removeWindow(ctx.model, win)) {
      Object.assign(ctx.model, createModel());
      return null;
    }
  }
  return { selection: restoredSelection(snapshot, ctx.model) };
}
