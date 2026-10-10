// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 全体のキー入力。キー列 → コマンドの対応と、コマンドの直列実行。

import { createDispatcher, keyName } from "../keys.ts";
import type { Keymap } from "../keys.ts";
import type { Commands } from "./commands.ts";
import type { AppContext } from "./context.ts";
import { errorMessage } from "./navigation.ts";
import { LatencyRecorder } from "./latency.ts";

export interface KeyboardHandle {
  readonly latency: LatencyRecorder;
  /** 直前までに受け付けたコマンドが、すべて終わるまで待つ(テスト用)。 */
  idle(): Promise<void>;
}

export function installKeyboard(
  ctx: AppContext,
  commands: Commands,
  keymap: Keymap,
): KeyboardHandle {
  const dispatcher = createDispatcher(keymap);
  const latency = new LatencyRecorder();
  // 非同期コマンド(ファイル読み込みなど)の完了前に、次のキーが処理されないよう、実行は直列にする
  let queue: Promise<void> = Promise.resolve();

  window.addEventListener("keydown", (e) => {
    if (ctx.minibuffer.active) return; // 入力欄が専用のキー処理を持つ
    const name = keyName(e);
    if (!name) return;
    const t0 = e.timeStamp;
    if (name === "C-g") {
      dispatcher.reset();
      e.preventDefault();
      ctx.echo.message("Quit");
      return;
    }
    const r = dispatcher.feed(name);
    if (r.type === "unbound") {
      if (r.keys.length > 1) {
        e.preventDefault();
        ctx.echo.message(`${r.keys.join(" ")} は未割り当てです`);
      }
      return; // 単独の未割り当てキーは WebView 既定に任せる(Cmd+C など)
    }
    e.preventDefault();
    if (r.type === "prefix") {
      ctx.echo.message(`${r.pending.join(" ")} -`);
      return;
    }
    ctx.echo.message("");
    const command = commands[r.command as keyof Commands];
    queue = queue.then(async () => {
      try {
        await command();
      } catch (err) {
        ctx.echo.message(`${r.command}: ${errorMessage(err)}`);
      }
      ctx.views.refresh();
      latency.record(t0, (ms, s) => {
        ctx.echo.status(
          `${ctx.host.name} | ${name} → ${r.command}: ${ms.toFixed(1)}ms (描画 ${ctx.views.stats.ms.toFixed(1)}ms ${ctx.views.stats.diagrams}) | 中央値 ${s.median.toFixed(1)} / p95 ${s.p95.toFixed(1)} / 最大 ${s.max.toFixed(1)} (n=${s.n})`,
        );
      });
    });
  });

  return { latency, idle: () => queue };
}
